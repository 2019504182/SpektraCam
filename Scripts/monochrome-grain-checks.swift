import Foundation

private func linear(_ x: Float) -> Double {
    let v = Double(x)
    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
}
@main struct Checks {
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
            .appendingPathComponent("andreavolpato-spektrafilm/Resources/ModelData")
        let sources = try ["ColorPipeline", "Spatial", "Grain", "Diffusion", "FilmPipeline"].map {
            try String(contentsOf: directory.appendingPathComponent($0 + ".metalSource"), encoding: .utf8)
        }
        let gpu = try MetalFilmPipeline(sources: sources)
        let library = try ModelLibrary(directory: directory)
        let width = 96
        let height = 72
        let input = Array(repeating: SIMD4<Float>(0.3, 0.16, 0.08, 1), count: width * height)
        for direct in [false, true] {
            var clean = EditRecipe()
            clean.scanFilm = direct
            clean.flags["camera.auto_exposure"] = false
            clean.flags["film_render.grain.active"] = false
            let baseline = try await gpu.process(
                input, width: width, height: height,
                pipeline: FilmPipeline(library: library, recipe: clean), seed: 17, autoExposureEV: 0)
            var mono = clean
            mono.flags["film_render.grain.active"] = true
            mono.monochromeGrain = true
            let result = try await gpu.process(
                input, width: width, height: height,
                pipeline: FilmPipeline(library: library, recipe: mono), seed: 17, autoExposureEV: 0)
            var largestChroma = 0.0
            var energy = 0.0
            for (a, b) in zip(result.pixels, baseline.pixels) {
                let delta = SIMD3(
                    linear(a.x) - linear(b.x), linear(a.y) - linear(b.y), linear(a.z) - linear(b.z))
                largestChroma = max(largestChroma, abs(delta.x - delta.y), abs(delta.y - delta.z))
                energy += delta.x * delta.x
            }
            precondition(largestChroma < 1e-5, "Monochrome grain changed chroma: \(largestChroma)")
            precondition(energy > 1e-8, "Monochrome grain has no texture")
            clean.monochromeGrain = true
            let disabled = try await gpu.process(
                input, width: width, height: height,
                pipeline: FilmPipeline(library: library, recipe: clean), seed: 17, autoExposureEV: 0)
            precondition(disabled.pixels == baseline.pixels, "Disabled grain changed the image")
            print(
                "PASS: monochrome grain preserves linear chroma; direct scan \(direct), max chroma residual \(largestChroma)"
            )
        }
    }
}
