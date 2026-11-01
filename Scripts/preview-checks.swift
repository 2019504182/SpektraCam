import CoreGraphics
import Foundation
import ImageIO

@main struct Checks {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = root.appendingPathComponent("andreavolpato-spektrafilm/Resources/ModelData")
        let width = 1080
        let height = 810
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: space, components: [0.4, 0.5, 0.6, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let source = context.makeImage()!
        let renderer = PhotoRenderer(source: source, directory: data)
        var recipe = EditRecipe()
        let first = try await renderer.render(recipe)
        let started = ProcessInfo.processInfo.systemUptime
        let same = try await renderer.render(recipe)
        let frameMilliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
        let firstPixels = try PhotoColorBridge.decode(first)
        let samePixels = try PhotoColorBridge.decode(same)
        precondition(firstPixels == samePixels, "Stable recipe changed preview")
        recipe.numbers["camera.exposure_compensation_ev"] = 2
        let adjusted = try await renderer.render(recipe)
        let adjustedPixels = try PhotoColorBridge.decode(adjusted)
        precondition(adjustedPixels != firstPixels, "Exposure did not reach preview")
        precondition(
            source.width == width && first.width == width && adjusted.height == height,
            "Preview dimensions changed")
        var sourceEV = EditRecipe()
        sourceEV.source.exposureEV = 1
        let sourceAdjusted = try await renderer.render(sourceEV)
        let sourcePixels = try PhotoColorBridge.decode(sourceAdjusted)
        precondition(sourcePixels != firstPixels, "Auto metering canceled the master source exposure")
        sourceEV.mix = 0
        let unmixed = try await renderer.render(sourceEV)
        let input = try SourceImageRenderer.prepare(
            data: nil, fallback: source, recipe: sourceEV, maximum: 1080)
        let unmixedPixels = try PhotoColorBridge.decode(unmixed)
        precondition(
            abs(unmixedPixels[0].x - input.pixels[0].x) < 0.005, "Mix cache ignored source adjustments")
        sourceEV.mix = 1
        let restored = try await renderer.render(sourceEV)
        let restoredPixels = try PhotoColorBridge.decode(restored)
        precondition(restoredPixels == sourcePixels, "Mix invalidated the wrong film frame")
        var toneRecipe = sourceEV
        toneRecipe.tone.contrast = 1.4
        let toneStart = ProcessInfo.processInfo.systemUptime
        let graded = try await renderer.render(toneRecipe)
        let toneMilliseconds = (ProcessInfo.processInfo.systemUptime - toneStart) * 1000
        let gradedPixels = try PhotoColorBridge.decode(graded)
        precondition(gradedPixels != sourcePixels, "RAW contrast did not reach Develop")
        let neutralAgain = try await renderer.render(sourceEV)
        let neutralPixels = try PhotoColorBridge.decode(neutralAgain)
        precondition(neutralPixels == sourcePixels, "RAW contrast reset changed the reference frame")
        print("1080 px RAW contrast and Develop, Debug ms:", toneMilliseconds)
        print(
            "PASS: preview worker loads bundled resources, stable film frame, film and source exposure changes, Mix cache and immutable source; cached Debug frame \(frameMilliseconds) ms on Mac"
        )
        try await checkLUTRendering(directory: data)
        try await checkLUTEdges(directory: data)
        try await checkOpticalParity(directory: data)
    }

    private static func checkOpticalParity(directory: URL) async throws {
        let sources = try ["ColorPipeline", "Spatial", "Grain", "Diffusion", "FilmPipeline"].map {
            try String(contentsOf: directory.appendingPathComponent($0 + ".metalSource"), encoding: .utf8)
        }
        let gpu = try MetalFilmPipeline(sources: sources)
        let library = try ModelLibrary(directory: directory)
        let width = 1080
        let height = 48
        let pixels = (0..<width * height).map { i -> SIMD4<Float> in
            let x = i % width
            return x < 400 || x > 850 ? .init(0, 0, 0, 1) : .init(16, 8, 4, 1)
        }
        let input = try SpatialCore.Image(
            width: width, height: height,
            pixels: pixels.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) })
        for scale in [1.0, 3.0, 10.0] {
            var recipe = EditRecipe()
            recipe.flags["camera.diffusion_filter.active"] = false
            recipe.flags["enlarger.diffusion_filter.active"] = false
            recipe.numbers["film_render.halation.scatter_spatial_scale"] = scale
            recipe.numbers["film_render.halation.halation_amount"] = 20
            let model = try FilmPipeline(library: library, recipe: recipe)
            let expected = try HalationCore.apply(
                input, parameters: model.halation,
                pixelSizeMicrometers: recipe.number("camera.film_format_mm") * 1000 / Double(width))
            let result = try PhotoColorBridge.decode(
                await gpu.processOptics(pixels, width: width, height: height, pipeline: model))
            var maximum: Double = 0
            for i in result.indices {
                for ch in 0..<3 {
                    maximum = max(maximum, abs(Double(result[i][ch]) - expected.pixels[i][ch]))
                    precondition(
                        result[i][ch] >= -0.0001 && result[i][ch] <= pixels[500][ch] + 0.0001,
                        "Scatter generated negative light or an edge overshoot")
                }
            }
            precondition(maximum < 0.0001, "Optical scatter/halation differs from the native reference")
            print("PASS: HDR edge optical parity, scatter scale", scale, "halation 20×, max error", maximum)
        }
    }

    private static func checkLUTEdges(directory: URL) async throws {
        let cg = CGContext(
            data: nil, width: 256, height: 192, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.setFillColor(CGColor(gray: 0.1, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: 256, height: 192))
        cg.setFillColor(CGColor(gray: 0.9, alpha: 1))
        for x in stride(from: 40, to: 120, by: 2) { cg.fill(CGRect(x: x, y: 20, width: 1, height: 150)) }
        cg.fill(CGRect(x: 160, y: 64, width: 40, height: 40))
        let worker = PhotoRenderer(source: cg.makeImage()!, directory: directory)
        var recipe = EditRecipe()
        recipe.look.mode = .lut
        let opticalFlags = [
            "film_render.halation.active", "camera.diffusion_filter.active",
            "enlarger.diffusion_filter.active",
        ]
        for flag in opticalFlags + ["film_render.grain.active"] { recipe.flags[flag] = false }
        let clean = try PhotoColorBridge.decode(await worker.render(recipe))
        recipe.flags["film_render.grain.active"] = true
        recipe.numbers["film_render.grain.blur"] = 0
        let sharp = try PhotoColorBridge.decode(await worker.render(recipe))
        recipe.numbers["film_render.grain.blur"] = 2
        let smooth = try PhotoColorBridge.decode(await worker.render(recipe))
        func error(_ values: [SIMD4<Float>]) -> Float {
            zip(values, clean).reduce(0) {
                $0 + abs($1.0.x - $1.1.x) + abs($1.0.y - $1.1.y) + abs($1.0.z - $1.1.z)
            } / Float(clean.count * 3)
        }
        let sharpError = error(sharp)
        let smoothError = error(smooth)
        precondition(smoothError < 0.015, "Grain Blur transferred the film image's edge blur into LUT mode")
        precondition(smoothError < sharpError, "Grain Blur did not smooth the grain noise")
        recipe.flags["film_render.grain.active"] = false
        recipe.flags["film_render.halation.active"] = true
        recipe.numbers["film_render.halation.scatter_amount"] = 0
        recipe.numbers["film_render.halation.halation_spatial_scale"] = 3
        recipe.numbers["film_render.halation.halation_amount"] = 5
        let halo = try PhotoColorBridge.decode(await worker.render(recipe))
        let additions = zip(halo, clean).map { SIMD3<Float>($0.x - $1.x, $0.y - $1.y, $0.z - $1.z) }
        let red = additions.map(\.x).max()!
        let green = additions.map(\.y).max()!
        precondition(red > 0.001 && red > green, "Halation lost its red-weighted light spread")
        precondition(additions[10 * 256 + 230].x == 0, "Halation changed the distant dark background")
        print(
            "PASS: LUT sharp-edge preservation, noise-only Grain Blur (mean error", smoothError,
            "vs", sharpError, "), red-weighted halation and unchanged distant background")
        for mode in EditRecipe.LookMode.allCases {
            recipe.look.mode = mode
            recipe.numbers["film_render.halation.scatter_spatial_scale"] = 10
            recipe.numbers["film_render.halation.scatter_amount"] = 1
            let physical = try PhotoColorBridge.decode(await worker.render(recipe))
            recipe.numbers["film_render.halation.scatter_amount"] = 3
            let extrapolated = try PhotoColorBridge.decode(await worker.render(recipe))
            precondition(physical == extrapolated, "Saved scatter overdrive generated invalid edge light")
        }
        print("PASS: both look modes bound saved scatter values to a physical light mixture")
    }

    private static func checkLUTRendering(directory: URL) async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var cubes: [CubeLUT] = []
        for swap in [false, true] {
            var text = "LUT_3D_SIZE 2\n"
            for b in 0...1 {
                for g in 0...1 {
                    for r in 0...1 {
                        text += swap ? "\(b) \(g) \(r)\n" : "\(Double(r) * 0.5) \(g) \(b)\n"
                    }
                }
            }
            let bytes = Data(text.utf8)
            let cube = try CubeLUT(data: bytes, filename: "test.cube")
            try bytes.write(to: temporary.appendingPathComponent(cube.id + ".cube"))
            cubes.append(cube)
        }
        let cg = CGContext(
            data: nil, width: 512, height: 384, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<512 {
            cg.setFillColor(CGColor(red: CGFloat(x) / 511, green: 0.45, blue: 0.25, alpha: 1))
            cg.fill(CGRect(x: x, y: 0, width: 1, height: 384))
        }
        let image = cg.makeImage()!
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        let worker = PhotoRenderer(
            source: image, directory: directory, data: bytes as Data,
            lutDirectory: temporary)
        var recipe = EditRecipe()
        recipe.look.mode = .lut
        recipe.look.first = .init(id: cubes[0].id, mix: 0.6)
        recipe.look.second = .init(id: cubes[1].id, mix: 0.4)
        for flag in [
            "film_render.grain.active", "film_render.halation.active",
            "camera.diffusion_filter.active", "enlarger.diffusion_filter.active",
        ] {
            recipe.flags[flag] = false
        }
        recipe.tone.exposureEV = 0.5
        recipe.tone.contrast = 1.15
        let source = try SourceImageRenderer.prepare(
            data: bytes as Data, fallback: image,
            recipe: recipe, maximum: 1080)
        let reference = try ToneRenderer.render(
            SourceImageRenderer.workingImage(source), tone: recipe.tone,
            luts: [.init(cube: cubes[0], mix: 0.6), .init(cube: cubes[1], mix: 0.4)])
        let actual = try await worker.render(recipe)
        let expectedPixels = try PhotoColorBridge.decode(reference)
        let actualPixels = try PhotoColorBridge.decode(actual)
        precondition(expectedPixels == actualPixels, "LUT mode applied film color or changed RAW order")
        let export = try await worker.export(recipe, size: .small, format: .png, quality: 1)
        defer { try? FileManager.default.removeItem(at: export.0) }
        let exported = try PhotoExporter.decodeSource(Data(contentsOf: export.0))
        let exportedPixels = try PhotoColorBridge.decode(exported)
        precondition(actualPixels == exportedPixels, "LUT preview and export differ at the same size")
        for flag in [
            "film_render.grain.active", "film_render.halation.active",
            "camera.diffusion_filter.active", "enlarger.diffusion_filter.active",
        ] {
            var effect = recipe
            effect.flags[flag] = true
            if flag.contains("grain") { effect.numbers["film_render.grain.particle_area_um2"] = 10 }
            if flag.contains("halation") { effect.numbers["film_render.halation.halation_amount"] = 5 }
            if flag.contains("diffusion_filter") {
                effect.numbers[flag.replacingOccurrences(of: "active", with: "strength")] = 1
            }
            let frame = try await worker.render(effect)
            let pixels = try PhotoColorBridge.decode(frame)
            precondition(pixels != actualPixels, "LUT mode lost effect: " + flag)
            precondition(pixels.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        }
        let restored = try await worker.render(recipe)
        let restoredPixels = try PhotoColorBridge.decode(restored)
        precondition(restoredPixels == actualPixels, "Effects changed the clean LUT frame")
        print(
            "PASS: LUT mode bypasses film color; RAW order, both slots, four effects, reset and PNG export agree"
        )
        let files = CommandLine.arguments.dropFirst(2).prefix(2).map { URL(fileURLWithPath: $0) }
        if files.count == 2 {
            let installed = try files.map { file -> CubeLUT in
                let data = try Data(contentsOf: file)
                let cube = try CubeLUT(data: data, filename: file.lastPathComponent)
                try data.write(to: temporary.appendingPathComponent(cube.id + ".cube"))
                return cube
            }
            for ids in [[installed[0].id], [installed[1].id], installed.map(\.id)] {
                var real = recipe
                real.look.first = .init(id: ids[0], mix: 0.6)
                real.look.second = .init(id: ids.count == 2 ? ids[1] : nil, mix: 0.4)
                let clean = try PhotoColorBridge.decode(await worker.render(real))
                for flag in ["film_render.grain.active", "film_render.halation.active"] {
                    var changed = real
                    changed.flags[flag] = true
                    changed.numbers["film_render.grain.particle_area_um2"] = 10
                    changed.numbers["film_render.halation.halation_amount"] = 5
                    let pixels = try PhotoColorBridge.decode(await worker.render(changed))
                    let maximum = zip(pixels, clean).map {
                        abs($0.x - $1.x) + abs($0.y - $1.y) + abs($0.z - $1.z)
                    }.max()!
                    precondition(maximum > 0.001, "Supplied LUT lost grain or halation")
                }
            }
            print("PASS: grain and halation remain effective with each supplied LUT and both LUTs together")
        }
    }
}
