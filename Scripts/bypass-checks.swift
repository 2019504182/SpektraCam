import CoreImage
import Foundation

@main struct Checks {
    static func main() async throws {
        for path in CommandLine.arguments.dropFirst(2) {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let photo = ImportedPhoto.decode(data)!
            var recipe = EditRecipe()
            recipe.look.mode = .lut
            let input = try SourceImageRenderer.prepare(
                data: data, fallback: photo.preview, recipe: recipe, maximum: 1080)
            let review = try PhotoExporter.write(ToneRenderer.resolve(SourceImageRenderer.workingImage(input)), format: .png)
            print("SDR review:", review.path)
            let original = CIImage(
                data: data, options: [.applyOrientationProperty: true, .expandToHDR: false])!
            let scale = min(1, 1080 / max(original.extent.width, original.extent.height))
            let resized = original.clampedToExtent().applyingFilter(
                "CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
            let bounds = CGRect(x: 0, y: 0, width: input.width, height: input.height)
            var reference = [SIMD4<Float>](repeating: .zero, count: input.width * input.height)
            let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
            let context = CIContext(options: [
                .workingColorSpace: space, .workingFormat: CIFormat.RGBAf, .cacheIntermediates: false,
            ])
            reference.withUnsafeMutableBytes {
                context.render(
                    resized, toBitmap: $0.baseAddress!, rowBytes: input.width * 16, bounds: bounds,
                    format: .RGBAf, colorSpace: space)
            }
            let error = zip(input.pixels, reference).map {
                max(abs($0.x - $1.x), abs($0.y - $1.y), abs($0.z - $1.z))
            }.max()!
            precondition(error < 0.00001, "No-LUT SDR input differs from native SDR decode")
            recipe.look.mode = .spektrafilm
            let hdr = try SourceImageRenderer.prepare(
                data: data, fallback: photo.preview, recipe: recipe, maximum: 1080)
            let sdrMean = input.pixels.reduce(0.0) { $0 + Double($1.y) } / Double(input.pixels.count)
            let hdrMean = hdr.pixels.reduce(0.0) { $0 + Double($1.y) } / Double(hdr.pixels.count)
            let renderer = PhotoRenderer(
                source: photo.preview,
                directory: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(
                    "andreavolpato-spektrafilm/Resources/ModelData"), data: data)
            for key in [
                "film_render.grain.active", "film_render.halation.active", "camera.diffusion_filter.active",
                "enlarger.diffusion_filter.active",
            ] { recipe.flags[key] = false }
            _ = try await renderer.render(recipe)
            recipe.look.mode = .lut
            let firstBypass = try PhotoColorBridge.decode(await renderer.render(recipe))
            recipe.look.mode = .spektrafilm
            _ = try await renderer.render(recipe)
            recipe.look.mode = .lut
            let secondBypass = try PhotoColorBridge.decode(await renderer.render(recipe))
            let cacheError = zip(firstBypass, secondBypass).map { abs($0.y - $1.y) }.max()!
            precondition(cacheError < 0.00001, "HEIF HDR/LUT cache changed the bypass image")
            let inputMean = input.pixels.reduce(0.0) { $0 + Double($1.y) } / Double(input.pixels.count)
            let bypassMean = secondBypass.reduce(0.0) { $0 + Double($1.y) } / Double(secondBypass.count)
            precondition(abs(bypassMean / inputMean - 1) < 0.01, "Cached HEIF bypass reused HDR input")
            print("PASS: film/LUT/film/LUT cache isolation; SDR bypass mean ratio", bypassMean / inputMean)
            print(
                "PASS: no-LUT input matches native SDR; max error", error, "HDR/SDR mean ratio",
                hdrMean / sdrMean)
        }
    }
}
