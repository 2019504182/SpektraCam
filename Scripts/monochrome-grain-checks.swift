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
        let edgeWidth = 384
        let edgeHeight = 192
        for peak: Float in [1, 4] {
            var pixels = Array(repeating: SIMD4<Float>(0.02, 0.02, 0.02, 1), count: edgeWidth * edgeHeight)
            for y in 0..<edgeHeight {
                for x in edgeWidth / 2..<edgeWidth {
                    pixels[y * edgeWidth + x] = .init(peak, peak, peak, 1)
                }
            }
            var recipe = EditRecipe()
            for key in [
                "camera.auto_exposure", "film_render.halation.active", "camera.diffusion_filter.active",
                "enlarger.diffusion_filter.active", "print_render.glare.active",
            ] { recipe.flags[key] = false }
            recipe.numbers["film_render.grain.blur"] = 3
            recipe.numbers["film_render.grain.particle_area_um2"] = 10
            let pipeline = try FilmPipeline(library: library, recipe: recipe)
            let oldNoisy = try await gpu.processImage(
                pixels, width: edgeWidth, height: edgeHeight,
                pipeline: pipeline, autoExposureEV: 0)
            let oldMean = try await gpu.processImage(
                pixels, width: edgeWidth, height: edgeHeight,
                pipeline: pipeline, autoExposureEV: 0, grainMean: true)
            let restored = try await gpu.processGrainPair(
                pixels, width: edgeWidth, height: edgeHeight,
                pipeline: pipeline, autoExposureEV: 0)
            let oldA = try PhotoColorBridge.decode(oldNoisy)
            let oldB = try PhotoColorBridge.decode(oldMean)
            let newA = try PhotoColorBridge.decode(restored.0)
            let newB = try PhotoColorBridge.decode(restored.1)
            var before: Float = 0
            var after: Float = 0
            var count: Float = 0
            for y in 8..<edgeHeight - 8 {
                for x in edgeWidth / 2..<edgeWidth / 2 + 8 {
                    let i = y * edgeWidth + x
                    before +=
                        abs(oldA[i].x - oldB[i].x) + abs(oldA[i].y - oldB[i].y) + abs(oldA[i].z - oldB[i].z)
                    after +=
                        abs(newA[i].x - newB[i].x) + abs(newA[i].y - newB[i].y) + abs(newA[i].z - newB[i].z)
                    count += 3
                }
            }
            print(
                "Grain highlight edge, peak", peak, "old mean", before / count, "restored mean", after / count
            )
            precondition(
                after < before * 0.8, "Density restoration did not reduce highlight-edge grain artifacts")
        }
    }
}
