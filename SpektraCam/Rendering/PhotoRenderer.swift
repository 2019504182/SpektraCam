import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Owns one source and one GPU worker. Preview input, baseline metering and the latest film
/// frame are cached independently. Mix reuses the film frame; export uses original bytes.
actor PhotoRenderer {
    private let source: CGImage, data: Data?, initialTemperature: Double?
    private let previewMaximum: Int
    private let renderResources: FilmRenderResources
    private let lutDirectory: URL?
    private var cubes: [String: CubeLUT] = [:]
    private var opticsKey: EditRecipe?
    private var opticsSize = CGSize.zero
    private var opticsImage: CGImage?
    private var grainKey: EditRecipe?
    private var grainSize = CGSize.zero
    private var grainImages: (CGImage, CGImage)?
    private var previousMode: EditRecipe.LookMode?
    private var baseline: SourceImageRenderer.Input?
    private var baselineImage: CIImage?
    private var input: SourceImageRenderer.Input?
    private var inputKey: EditRecipe.Source?
    private var inputTemperature: Double?
    private var inputLookMode: EditRecipe.LookMode?
    private var meter: MeteringCore.Image?
    private var meteredEV = [String: Double]()
    private var filmRecipe: EditRecipe?
    private var filmImage: CGImage?
    private var exportKey: EditRecipe?
    private var exportSize: PhotoExporter.Size?
    private var exportImage: CGImage?

    init(
        source: CGImage, directory: URL, data: Data? = nil, temperature: Double? = nil,
        lutDirectory: URL? = nil, previewMaximum: Int = 1080, resources: FilmRenderResources? = nil
    ) {
        self.source = source
        self.previewMaximum = previewMaximum
        renderResources = resources ?? FilmRenderResources(directory: directory)
        self.data = data
        initialTemperature = temperature
        self.lutDirectory = lutDirectory
    }
    private func baselineInput() throws -> SourceImageRenderer.Input {
        if let baseline { return baseline }
        var recipe = EditRecipe()
        recipe.look.mode = inputLookMode ?? .spektrafilm
        recipe.temperature = initialTemperature
        let result = try SourceImageRenderer.prepare(
            data: data, fallback: source, recipe: recipe, maximum: previewMaximum)
        baseline = result
        baselineImage = SourceImageRenderer.image(result)
        return result
    }
    private func exposure(_ recipe: EditRecipe, library: ModelLibrary) throws -> Double {
        guard recipe.flag("camera.auto_exposure") else { return 0 }
        let method = recipe.choice("camera.auto_exposure_method")
        if let value = meteredEV[method] { return value }
        if meter == nil {
            let baseline = try baselineInput()
            let y = ModelLibrary.vector(library.index.meteringY)
            let luminance = baseline.pixels.map {
                Double($0.x) * y.x + Double($0.y) * y.y + Double($0.z) * y.z
            }
            meter = try MeteringCore.Image(
                width: baseline.width, height: baseline.height, luminance: luminance
            ).smallPreview()
        }
        let value = meter!.exposureEV(method: method)
        meteredEV[method] = value
        return value
    }
    private func selectInputMode(_ mode: EditRecipe.LookMode) {
        if inputLookMode != mode {
            // Film/RAW and SDR photo-LUT input have different rendering intents, including HEIF gain maps.
            baseline = nil
            baselineImage = nil
            input = nil
            meter = nil
            meteredEV.removeAll()
        }
        inputLookMode = mode
    }
    private func previewInput(_ recipe: EditRecipe) throws -> SourceImageRenderer.Input {
        selectInputMode(recipe.look.mode)
        if inputKey == recipe.source, inputTemperature == recipe.temperature, let input {
            return input
        }
        let result: SourceImageRenderer.Input
        if recipe.source == EditRecipe.Source(), recipe.temperature == initialTemperature {
            result = try baselineInput()
        } else {
            let canReuse =
                initialTemperature == nil
                || (recipe.temperature == initialTemperature && recipe.source.tint == 0)
            if canReuse { _ = try baselineInput() }
            result = try SourceImageRenderer.prepare(
                data: canReuse ? nil : data, fallback: source, recipe: recipe,
                maximum: previewMaximum,
                renderedSource: canReuse ? baselineImage : nil)
        }
        input = result
        inputKey = recipe.source
        inputTemperature = recipe.temperature
        return result
    }
    func render(_ recipe: EditRecipe) async throws -> CGImage {
        try Task.checkCancellation()
        let (library, gpu) = try await renderResources.load()
        let input = try previewInput(recipe)
        if previousMode != recipe.look.mode {
            filmRecipe = nil
            filmImage = nil
            opticsKey = nil
            opticsImage = nil
            grainKey = nil
            grainImages = nil
            previousMode = recipe.look.mode
        }
        return try await frame(input, recipe: recipe, library: library, gpu: gpu, preview: true)
    }
    private func applications(_ recipe: EditRecipe) throws -> [CubeLUT.Application] {
        var active: [String: CubeLUT] = [:]
        var result: [CubeLUT.Application] = []
        for slot in [recipe.look.first, recipe.look.second] {
            guard let id = slot.id, slot.mix > 0 else { continue }
            guard let lutDirectory else { throw CubeLUT.Failure.missing }
            let cube = try active[id] ?? cubes[id] ?? CubeLUT.load(id: id, directory: lutDirectory)
            active[id] = cube
            result.append(.init(cube: cube, mix: slot.mix))
        }
        cubes = active
        return result
    }
    private func effectFrames(
        _ input: SourceImageRenderer.Input, recipe: EditRecipe,
        library: ModelLibrary, gpu: MetalFilmPipeline, preview: Bool
    ) async throws -> (CGImage, CGImage?, CGImage?) {
        var physical = EditRecipe()
        // The carrier uses film optics, but its RAW controls share the LUT source reference.
        physical.look.mode = .lut
        let prefixes = [
            "film_render.grain.", "film_render.halation.", "camera.diffusion_filter.",
            "enlarger.diffusion_filter.",
        ]
        physical.numbers = recipe.numbers.filter { entry in
            prefixes.contains { entry.key.hasPrefix($0) }
        }
        physical.flags = recipe.flags.filter { entry in
            prefixes.contains { entry.key.hasPrefix($0) }
        }
        physical.choices = recipe.choices.filter { entry in
            prefixes.contains { entry.key.hasPrefix($0) }
        }
        physical.numbers["camera.film_format_mm"] = recipe.number("camera.film_format_mm")
        physical.monochromeGrain = false
        physical.tone = recipe.tone.rawStage
        physical.source = recipe.source
        physical.temperature = recipe.temperature
        // Scatter is an energy mixture in RGB. Extrapolating it creates negative edge light.
        physical.numbers["film_render.halation.scatter_amount"] = min(
            max(physical.number("film_render.halation.scatter_amount"), 0), 1)
        let size = CGSize(width: input.width, height: input.height)
        let opticalFlags = [
            "film_render.halation.active", "camera.diffusion_filter.active",
            "enlarger.diffusion_filter.active",
        ]
        var optics = physical
        optics.numbers = optics.numbers.filter { !$0.key.hasPrefix("film_render.grain.") }
        optics.flags = optics.flags.filter { !$0.key.hasPrefix("film_render.grain.") }
        optics.flags["film_render.grain.active"] = false
        let source: CGImage
        if preview, opticsKey == optics, opticsSize == size, let image = opticsImage {
            source = image
        } else {
            if opticalFlags.contains(where: { optics.flag($0) }) || !optics.tone.rawStage.isIdentity
            {
                source = try await gpu.processOptics(
                    input.pixels, width: input.width, height: input.height,
                    pipeline: FilmPipeline(library: library, recipe: optics))
            } else {
                source = try SourceImageRenderer.workingImage(input)
            }
            if preview {
                opticsKey = optics
                opticsSize = size
                opticsImage = source
            }
        }
        var grain = physical
        grain.numbers = grain.numbers.filter {
            $0.key.hasPrefix("film_render.grain.") || $0.key == "camera.film_format_mm"
        }
        grain.flags = grain.flags.filter { $0.key.hasPrefix("film_render.grain.") }
        grain.choices = [:]
        for flag in opticalFlags { grain.flags[flag] = false }
        grain.flags["print_render.glare.active"] = false
        let noise: (CGImage, CGImage)?
        if !grain.flag("film_render.grain.active") {
            noise = nil
            if preview {
                grainImages = nil
                grainKey = nil
            }
        } else if preview, grainKey == grain, grainSize == size, let frames = grainImages {
            noise = frames
        } else {
            let exposure = try exposure(grain, library: library)
            let pipeline = try FilmPipeline(library: library, recipe: grain)
            noise = try await gpu.processGrainPair(
                input.pixels, width: input.width, height: input.height,
                pipeline: pipeline, autoExposureEV: exposure)
            if preview {
                grainKey = grain
                grainSize = size
                grainImages = noise
            }
        }
        return (source, noise?.0, noise?.1)
    }

    private func frame(
        _ input: SourceImageRenderer.Input, recipe: EditRecipe,
        library: ModelLibrary, gpu: MetalFilmPipeline, preview: Bool
    ) async throws -> CGImage {
        var recipe = recipe
        recipe.numbers["film_render.halation.scatter_amount"] = min(
            max(recipe.number("film_render.halation.scatter_amount"), 0), 1)
        if recipe.look.mode == .lut {
            let frames = try await effectFrames(
                input, recipe: recipe, library: library, gpu: gpu, preview: preview)
            let residual: (CGImage, CGImage)? = frames.1.flatMap { dirty in
                frames.2.map { (dirty, $0) }
            }
            return try ToneRenderer.render(
                frames.0, tone: recipe.tone.outputStage, luts: applications(recipe),
                residual: residual,
                monochromeResidual: recipe.monochromeGrain)
        }
        var key = recipe.processingRecipe
        key.mix = 1
        key.tone = recipe.tone.rawStage
        key.look = EditRecipe.Look()
        let film: CGImage
        if preview, filmRecipe == key, let cached = filmImage {
            film = cached
        } else {
            film = try await gpu.processImage(
                input.pixels, width: input.width, height: input.height,
                pipeline: FilmPipeline(library: library, recipe: recipe),
                autoExposureEV: exposure(recipe, library: library))
            if preview {
                filmRecipe = key
                filmImage = film
            }
        }
        try Task.checkCancellation()
        let mixed: CGImage
        if recipe.mix >= 1 {
            mixed = film
        } else {
            let rawSource = try ToneRenderer.working(
                SourceImageRenderer.workingImage(input), tone: recipe.tone.rawStage,
                normalizationEV: exposure(recipe, library: library))
            mixed = try SourceImageRenderer.blend(
                film: film, sourceImage: rawSource, amount: recipe.mix)
        }
        return try ToneRenderer.render(mixed, tone: recipe.tone.outputStage)
    }

    func export(
        _ recipe: EditRecipe, size: PhotoExporter.Size, format: PhotoExporter.Format,
        quality: Double,
        allowOvercommit: Bool = false
    )
        async throws -> (URL, Int, Int)
    {
        if exportKey != recipe || exportSize != size { exportImage = nil }
        let image: CGImage
        if let cached = exportImage {
            image = cached
        } else {
            guard let data else { throw PhotoExporter.Failure.decode }
            let dimensions = try PhotoExporter.sourceDimensions(data)
            let width = Int(dimensions.width)
            let height = Int(dimensions.height)
            let originalLong = max(width, height)
            let oriented =
                recipe.geometry.quarterTurns % 2 == 0
                ? CGSize(width: source.width, height: source.height)
                : CGSize(width: source.height, height: source.width)
            let crop = recipe.crop.pixelRect(in: oriented)
            let fraction = max(crop.width, crop.height) / max(oriented.width, oriented.height)
            let maximum = min(
                originalLong,
                size.maximum.map { Int(ceil(Double($0) / max(fraction, 1e-6))) } ?? originalLong
            )
            let scale = Double(maximum) / Double(originalLong)
            let (_, exportGPU) = try await renderResources.load()
            await exportGPU.releaseWorkingCaches()
            filmImage = nil
            opticsImage = nil
            grainImages = nil
            try RenderMemoryBudget.check(
                width: max(1, Int(ceil(Double(width) * scale))),
                height: max(1, Int(ceil(Double(height) * scale))), recipe: recipe,
                allowOvercommit: allowOvercommit)
            // The RAW input path decodes directly to float; an 8-bit fallback decode is redundant.
            let decoded =
                initialTemperature != nil
                ? source : try PhotoExporter.decodeSource(data, maximum: maximum)
            selectInputMode(recipe.look.mode)
            let input = try SourceImageRenderer.prepare(
                data: data, fallback: decoded, recipe: recipe, maximum: maximum)
            let (library, gpu) = try await renderResources.load()
            let graded: CGImage
            do {
                graded = try await frame(
                    input, recipe: recipe, library: library, gpu: gpu, preview: false)
            } catch {
                await gpu.releaseWorkingCaches()
                throw error
            }
            await gpu.releaseWorkingCaches()
            try Task.checkCancellation()
            guard let transformed = GeometryRenderer.render(graded, geometry: recipe.geometry),
                let cropped = transformed.cropping(
                    to: recipe.crop.pixelRect(
                        in: CGSize(width: transformed.width, height: transformed.height)))
            else { throw PhotoExporter.Failure.render }
            image = try Self.resize(cropped, maximum: size.maximum)
            exportImage = image
            exportKey = recipe
            exportSize = size
        }
        try Task.checkCancellation()
        let url = try PhotoExporter.write(image, format: format, quality: quality)
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        return (url, image.width, image.height)
    }
    func discardExport() {
        exportImage = nil
        exportKey = nil
        exportSize = nil
    }
    private static func resize(_ image: CGImage, maximum: Int?) throws -> CGImage {
        guard let maximum, max(image.width, image.height) > maximum else { return image }
        let scale = Double(maximum) / Double(max(image.width, image.height))
        let output = CIImage(cgImage: image).applyingFilter(
            "CILanczosScaleTransform",
            parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        let rect = CGRect(
            x: 0, y: 0, width: floor(Double(image.width) * scale),
            height: floor(Double(image.height) * scale)
        )
        guard
            let resized = CIContext(options: [.cacheIntermediates: false]).createCGImage(
                output, from: rect, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        else { throw PhotoExporter.Failure.render }
        return resized
    }
}
