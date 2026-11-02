import CoreGraphics
import Foundation

@main struct Checks {
    static func main() async throws {
        let args = CommandLine.arguments
        let directory = URL(fileURLWithPath: args[1]).appendingPathComponent(
            "andreavolpato-spektrafilm/Resources/ModelData")
        let library = try ModelLibrary(directory: directory)
        let sources = try ["ColorPipeline", "Spatial", "Grain", "Diffusion", "FilmPipeline"].map {
            try String(
                contentsOf: directory.appendingPathComponent($0 + ".metalSource"), encoding: .utf8)
        }
        let gpu = try MetalFilmPipeline(sources: sources)
        for path in args.dropFirst(2) {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let photo = ImportedPhoto.decode(data) else {
                throw SourceImageRenderer.Failure.decode
            }
            var recipe = EditRecipe()
            recipe.temperature = photo.rawTemperature
            for flag in [
                "film_render.grain.active", "film_render.halation.active",
                "camera.diffusion_filter.active", "enlarger.diffusion_filter.active",
                "print_render.glare.active",
            ] { recipe.flags[flag] = false }
            let input = try SourceImageRenderer.prepare(
                data: data, fallback: photo.preview, recipe: recipe, maximum: 384)
            let y = ModelLibrary.vector(library.index.meteringY)
            let luminance = input.pixels.map {
                Double($0.x) * y.x + Double($0.y) * y.y + Double($0.z) * y.z
            }
            let ev = try MeteringCore.Image(
                width: input.width, height: input.height, luminance: luminance
            ).smallPreview().exposureEV(method: recipe.choice("camera.auto_exposure_method"))
            print(
                "INPUT", URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent,
                "raw", photo.rawTemperature != nil, "max",
                input.pixels.map { max($0.x, max($0.y, $0.z)) }.max()!, "autoEV", ev)
            var review: [CGImage] = []
            for contrast in [0.65, 1.0, 1.35] {
                recipe.tone.contrast = contrast
                let result = try await gpu.process(
                    input.pixels, width: input.width, height: input.height,
                    pipeline: FilmPipeline(library: library, recipe: recipe), stochastic: false,
                    autoExposureEV: ev)
                if ProcessInfo.processInfo.environment["TONE_REVIEW"] == "1" {
                    review.append(
                        try PhotoColorBridge.encode(
                            result.pixels, width: input.width, height: input.height))
                }
                let values = result.pixels.map { 0.2126 * $0.x + 0.7152 * $0.y + 0.0722 * $0.z }
                    .sorted()
                print(
                    "contrast", contrast, "p10", values[values.count / 10], "p50",
                    values[values.count / 2], "p90", values[values.count * 9 / 10], "span",
                    values[values.count * 9 / 10] - values[values.count / 10])
            }
            if review.count == 3,
                let canvas = CGContext(
                    data: nil, width: input.width * 3, height: input.height,
                    bitsPerComponent: 8, bytesPerRow: input.width * 12,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            {
                for (index, image) in review.enumerated() {
                    canvas.draw(
                        image,
                        in: CGRect(
                            x: index * input.width, y: 0, width: input.width, height: input.height))
                }
                let output = try PhotoExporter.write(canvas.makeImage()!, format: .png)
                print("REVIEW low / neutral / high contrast:", output.path)
            }
        }
    }
}
