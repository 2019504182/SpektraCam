import CoreGraphics
import Foundation

@main struct Checks {
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(
            "andreavolpato-spektrafilm/Resources/ModelData")
        let library = try ModelLibrary(directory: directory)
        let sources = try ["ColorPipeline", "Spatial", "Grain", "Diffusion", "FilmPipeline"].map {
            try String(
                contentsOf: directory.appendingPathComponent($0 + ".metalSource"), encoding: .utf8)
        }
        let gpu = try MetalFilmPipeline(sources: sources)
        let values = (0..<256).map { i -> SIMD4<Float> in
            let x = Float(pow(2, -12 + 18 * Double(i) / 255))
            return .init(x, x, x, 1)
        }
        let image = try PhotoColorBridge.workingImage(
            values.withUnsafeBytes { Data($0) }, width: 256, height: 1, encoded: false)
        for contrast in [0.65, 1, 1.35] {
            for shadows in [-2.0, 0, 2] {
                for highlights in [-2.0, 0, 2] {
                    var tone = EditRecipe.Tone()
                    tone.contrast = contrast
                    tone.shadows = shadows
                    tone.highlights = highlights
                    let result = try PhotoColorBridge.decode(
                        ToneRenderer.working(image, tone: tone))
                    precondition(result.allSatisfy { $0.x.isFinite && $0.x > 0 })
                    precondition(
                        zip(result, result.dropFirst()).allSatisfy { $0.x < $1.x },
                        "Scene tone reversed tonal order")
                    precondition(result.last!.x > 1, "Tone clipped HDR headroom")
                }
            }
        }
        var tone = EditRecipe.Tone()
        tone.contrast = 1.35
        precondition(ToneRenderer.curve(2, tone: tone) > 2, "HDR values bypass the contrast curve")
        for pivot in [0.1, 0.35, 0.7] {
            tone.pivot = pivot
            precondition(
                abs(ToneRenderer.curve(pivot, tone: tone) - pivot) < 1e-10,
                "Pivot moves its own anchor")
        }
        let colors: [SIMD4<Float>] = [.init(2, 0.7, 0.2, 1), .init(0.06, 0.12, 0.3, 1)]
        let colorImage = try PhotoColorBridge.workingImage(
            colors.withUnsafeBytes { Data($0) }, width: 2, height: 1, encoded: false)
        let adjusted = try PhotoColorBridge.decode(ToneRenderer.working(colorImage, tone: tone))
        for (a, b) in zip(colors, adjusted) {
            precondition(
                abs(b.x / a.x - b.y / a.y) < 0.0001 && abs(b.x / a.x - b.z / a.z) < 0.0001,
                "Scene tone shifted RGB ratios")
        }
        var recipe = EditRecipe()
        recipe.tone.contrast = 1.3
        recipe.tone.shadows = 0.6
        recipe.tone.highlights = -0.8
        for flag in [
            "film_render.grain.active", "film_render.halation.active",
            "camera.diffusion_filter.active", "enlarger.diffusion_filter.active",
            "print_render.glare.active",
        ] { recipe.flags[flag] = false }
        func process(_ data: [SIMD4<Float>], ev: Double, recipe: EditRecipe) async throws -> [SIMD4<
            Float
        >] {
            try await gpu.process(
                data, width: data.count, height: 1,
                pipeline: FilmPipeline(library: library, recipe: recipe), stochastic: false,
                autoExposureEV: ev
            ).pixels
        }
        let base = try await process(values, ev: 0, recipe: recipe)
        let scaled = try await process(
            values.map { .init($0.x * 16, $0.y * 16, $0.z * 16, 1) }, ev: -4, recipe: recipe)
        let error = zip(base, scaled).map { abs($0.x - $1.x) }.max()!
        precondition(
            error < 0.0001,
            "Metered scene controls change when source exposure encoding changes: \(error)")
        let highImage = try PhotoColorBridge.workingImage(
            values.map { SIMD4<Float>($0.x * 16, $0.y * 16, $0.z * 16, 1) }.withUnsafeBytes {
                Data($0)
            }, width: 256, height: 1, encoded: false)
        let highGrade = try PhotoColorBridge.decode(
            ToneRenderer.working(highImage, tone: recipe.tone, normalizationEV: -4))
        let baseGrade = try PhotoColorBridge.decode(ToneRenderer.working(image, tone: recipe.tone))
        precondition(
            zip(highGrade, baseGrade).map { abs($0.x / 16 - $1.x) }.max()! < 0.0001,
            "Mix texture grade uses a different exposure reference")
        recipe.tone.algorithm = 4
        let oldBase = try await process(values, ev: 0, recipe: recipe)
        let oldScaled = try await process(
            values.map { .init($0.x * 16, $0.y * 16, $0.z * 16, 1) }, ev: -4, recipe: recipe)
        precondition(
            zip(oldBase, oldScaled).map { abs($0.x - $1.x) }.max()! > 0.01,
            "Test does not distinguish the old unnormalized curve")
        print(
            "PASS: monotonic scene controls, HDR response, fixed pivot, RGB ratios and metered exposure invariance; max error",
            error)
    }
}
