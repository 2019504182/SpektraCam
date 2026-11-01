import CoreGraphics
import CoreImage
import Foundation

@main struct Checks {
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(
            "andreavolpato-spektrafilm/Resources/ModelData")
        let library = try ModelLibrary(directory: directory)
        let sources = try ["ColorPipeline", "Spatial", "Grain", "Diffusion", "FilmPipeline"].map {
            try String(contentsOf: directory.appendingPathComponent($0 + ".metalSource"), encoding: .utf8)
        }
        let gpu = try MetalFilmPipeline(sources: sources)
        let width = 32
        let height = 24
        let pixels = (0..<(width * height)).map { index -> SIMD4<Float> in
            let x = Float(index % width) / Float(width - 1)
            return .init(0.02 + x * 1.4, 0.01 + x * 0.8, 0.03 + x * 0.4, 1)
        }
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let bytes = pixels.withUnsafeBytes { Data($0) }
        let input = CIImage(
            bitmapData: bytes, bytesPerRow: width * 16, size: CGSize(width: width, height: height),
            format: .RGBAf, colorSpace: linear)
        let context = CIContext(options: [.workingColorSpace: linear, .workingFormat: CIFormat.RGBAf])
        let image = context.createCGImage(input, from: input.extent, format: .RGBAf, colorSpace: linear)!
        var recipe = EditRecipe()
        recipe.flags["camera.auto_exposure"] = false
        recipe.flags["film_render.grain.active"] = false
        recipe.tone.exposureEV = 1.3
        recipe.tone.contrast = 1.2
        recipe.tone.pivot = 0.35
        recipe.tone.shadows = 0.4
        recipe.tone.highlights = -0.8
        let before = try PhotoColorBridge.decode(ToneRenderer.working(image, tone: recipe.tone.rawStage))
        let actual = try await gpu.process(
            pixels, width: width, height: height, pipeline: FilmPipeline(library: library, recipe: recipe),
            stochastic: false, autoExposureEV: 0)
        var neutral = recipe
        neutral.tone = EditRecipe.Tone()
        let reference = try await gpu.process(
            before, width: width, height: height, pipeline: FilmPipeline(library: library, recipe: neutral),
            stochastic: false, autoExposureEV: 0)
        let largest = zip(actual.pixels, reference.pixels).map { a, b in
            max(abs(a.x - b.x), abs(a.y - b.y), abs(a.z - b.z))
        }.max()!
        precondition(largest < 0.0001, "RAW controls did not run before Develop: \(largest)")
        // A post-development grade differs; this protects the order against a later refactor.
        let ungraded = try await gpu.process(
            pixels, width: width, height: height, pipeline: FilmPipeline(library: library, recipe: neutral),
            stochastic: false, autoExposureEV: 0)
        let code = ungraded.pixels.withUnsafeBytes { Data($0) }
        let developed = try PhotoColorBridge.workingImage(code, width: width, height: height)
        let after = try PhotoColorBridge.decode(ToneRenderer.working(developed, tone: recipe.tone.rawStage))
        let difference = zip(after, actual.pixels).map { a, b in
            abs(a.x - (b.x <= 0.04045 ? b.x / 12.92 : pow((b.x + 0.055) / 1.055, 2.4)))
        }.max()!
        precondition(difference > 0.01, "The fixture does not distinguish pre- and post-development grading")
        print(
            "PASS: exposure, S-curve/pivot and both tonal controls precede Develop; max pre-grade agreement error \(largest)"
        )
    }
}
