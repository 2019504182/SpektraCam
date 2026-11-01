import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Owns one source and one GPU worker. Preview input, baseline metering and the latest film
/// frame are cached independently. Mix reuses the film frame; export uses original bytes.
actor PhotoRenderer {
    private let source: CGImage, directory: URL, data: Data?, initialTemperature: Double?
    private var library: ModelLibrary?
    private var gpu: MetalFilmPipeline?
    private var baseline: SourceImageRenderer.Input?
    private var baselineImage: CIImage?
    private var input: SourceImageRenderer.Input?
    private var inputKey: EditRecipe.Source?
    private var inputTemperature: Double?
    private var meter: MeteringCore.Image?
    private var meteredEV = [String: Double]()
    private var filmRecipe: EditRecipe?
    private var filmImage: CGImage?
    private var exportKey: EditRecipe?
    private var exportSize: PhotoExporter.Size?
    private var exportImage: CGImage?

    init(source: CGImage, directory: URL, data: Data? = nil, temperature: Double? = nil) {
        self.source = source
        self.directory = directory
        self.data = data
        initialTemperature = temperature
    }
    private func resources() throws -> (ModelLibrary, MetalFilmPipeline) {
        if library == nil { library = try ModelLibrary(directory: directory) }
        if gpu == nil {
            let sources = try ["ColorPipeline", "Spatial", "Grain", "Diffusion", "FilmPipeline"].map {
                try String(contentsOf: directory.appendingPathComponent($0 + ".metalSource"), encoding: .utf8)
            }
            gpu = try MetalFilmPipeline(sources: sources)
        }
        return (library!, gpu!)
    }
    private func baselineInput() throws -> SourceImageRenderer.Input {
        if let baseline { return baseline }
        var recipe = EditRecipe()
        recipe.temperature = initialTemperature
        let result = try SourceImageRenderer.prepare(
            data: data, fallback: source, recipe: recipe, maximum: 1080)
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
    private func previewInput(_ recipe: EditRecipe) throws -> SourceImageRenderer.Input {
        if inputKey == recipe.source, inputTemperature == recipe.temperature, let input { return input }
        let result: SourceImageRenderer.Input
        if recipe.source == EditRecipe.Source(), recipe.temperature == initialTemperature {
            result = try baselineInput()
        } else {
            let canReuse =
                initialTemperature == nil
                || (recipe.temperature == initialTemperature && recipe.source.tint == 0)
            if canReuse { _ = try baselineInput() }
            result = try SourceImageRenderer.prepare(
                data: canReuse ? nil : data, fallback: source, recipe: recipe, maximum: 1080,
                renderedSource: canReuse ? baselineImage : nil)
        }
        input = result
        inputKey = recipe.source
        inputTemperature = recipe.temperature
        return result
    }
    func render(_ recipe: EditRecipe) async throws -> CGImage {
        try Task.checkCancellation()
        let (library, gpu) = try resources()
        let input = try previewInput(recipe)
        var key = recipe.processingRecipe
        key.mix = 1
        key.tone = EditRecipe.Tone()
        let film: CGImage
        if filmRecipe == key, let cached = filmImage {
            film = cached
        } else {
            let pipeline = try FilmPipeline(library: library, recipe: recipe)
            film = try await gpu.processImage(
                input.pixels, width: input.width, height: input.height,
                pipeline: pipeline, autoExposureEV: exposure(recipe, library: library))
            filmRecipe = key
            filmImage = film
        }
        try Task.checkCancellation()
        let mixed = try SourceImageRenderer.blend(film: film, source: input, amount: recipe.mix)
        return try ToneRenderer.render(mixed, tone: recipe.tone)
    }

    func export(_ recipe: EditRecipe, size: PhotoExporter.Size, format: PhotoExporter.Format, quality: Double)
        async throws -> (URL, Int, Int)
    {
        if exportKey != recipe || exportSize != size { exportImage = nil }
        let image: CGImage
        if let cached = exportImage {
            image = cached
        } else {
            guard let data, let cgSource = CGImageSourceCreateWithData(data as CFData, nil),
                let props = CGImageSourceCopyPropertiesAtIndex(cgSource, 0, nil) as? [CFString: Any],
                let width = props[kCGImagePropertyPixelWidth] as? Int,
                let height = props[kCGImagePropertyPixelHeight] as? Int
            else { throw PhotoExporter.Failure.decode }
            let originalLong = max(width, height)
            let oriented =
                recipe.geometry.quarterTurns % 2 == 0
                ? CGSize(width: source.width, height: source.height)
                : CGSize(width: source.height, height: source.width)
            let crop = recipe.crop.pixelRect(in: oriented)
            let fraction = max(crop.width, crop.height) / max(oriented.width, oriented.height)
            let maximum = min(
                originalLong, size.maximum.map { Int(ceil(Double($0) / max(fraction, 1e-6))) } ?? originalLong
            )
            let scale = Double(maximum) / Double(originalLong)
            try RenderMemoryBudget.check(
                width: max(1, Int(ceil(Double(width) * scale))),
                height: max(1, Int(ceil(Double(height) * scale))), recipe: recipe)
            let decoded = try PhotoExporter.decodeSource(data, maximum: maximum)
            let input = try SourceImageRenderer.prepare(
                data: data, fallback: decoded, recipe: recipe, maximum: maximum)
            let (library, gpu) = try resources()
            let pipeline = try FilmPipeline(library: library, recipe: recipe)
            let film: CGImage
            do {
                film = try await gpu.processImage(
                    input.pixels, width: input.width, height: input.height,
                    pipeline: pipeline, autoExposureEV: exposure(recipe, library: library))
            } catch {
                await gpu.releaseWorkingCaches()
                throw error
            }
            await gpu.releaseWorkingCaches()
            try Task.checkCancellation()
            let mixed = try SourceImageRenderer.blend(film: film, source: input, amount: recipe.mix)
            let graded = try ToneRenderer.render(mixed, tone: recipe.tone)
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
            "CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        let rect = CGRect(
            x: 0, y: 0, width: floor(Double(image.width) * scale), height: floor(Double(image.height) * scale)
        )
        guard
            let resized = CIContext(options: [.cacheIntermediates: false]).createCGImage(
                output, from: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        else { throw PhotoExporter.Failure.render }
        return resized
    }
}
