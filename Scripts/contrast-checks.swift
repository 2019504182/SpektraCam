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
        let pixels = (0..<128).map { i -> SIMD4<Float> in
            let x = Float(pow(10, -4 + 4 * Double(i) / 127))
            return .init(x, x, x, 1)
        }
        var spans: [Float] = []
        for amount in [0.5, 1, 1.5] {
            var recipe = EditRecipe()
            recipe.tone.contrast = amount
            recipe.flags["camera.auto_exposure"] = false
            recipe.flags["film_render.grain.active"] = false
            recipe.flags["film_render.halation.active"] = false
            let result = try await gpu.process(
                pixels, width: 128, height: 1,
                pipeline: FilmPipeline(library: library, recipe: recipe), stochastic: false,
                autoExposureEV: 0)
            spans.append(result.pixels[112].y - result.pixels[48].y)
            print(
                "contrast", amount, "samples",
                [32, 48, 64, 80, 96, 112].map { result.pixels[$0].y })
        }
        precondition(
            spans[0] < spans[1] && spans[1] < spans[2],
            "Displayed film contrast runs in the wrong direction")
        print("PASS: higher control value increases displayed contrast after Develop")
    }
}
