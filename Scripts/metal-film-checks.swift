import Foundation

private struct Case: Decodable { let recipe: EditRecipe, expected: [[Double]] }
private struct Fixture: Decodable { let width: Int, height: Int, input: [[Double]], cases: [Case] }
@main struct Checks {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = root.appendingPathComponent("andreavolpato-spektrafilm/ModelData")
        let names = ["ColorPipeline", "Spatial", "Grain", "Diffusion", "FilmPipeline"]
        let sources = try names.map {
            try String(contentsOf: data.appendingPathComponent($0 + ".metalSource"), encoding: .utf8)
        }
        let gpu = try MetalFilmPipeline(sources: sources)
        let library = try ModelLibrary(directory: data)
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Reference/Fixtures/spatial-pipeline.json")))
        let input = fixture.input.map { SIMD4<Float>(Float($0[0]), Float($0[1]), Float($0[2]), 1) }
        var count = 0
        var maximum = 0.0
        for test in fixture.cases {
            let model = try FilmPipeline(library: library, recipe: test.recipe)
            let result = try await gpu.process(
                input, width: fixture.width, height: fixture.height, pipeline: model, stochastic: false)
            for i in result.pixels.indices {
                for ch in 0..<3 {
                    let error = abs(Double(result.pixels[i][ch]) - test.expected[i][ch])
                    precondition(
                        error.isFinite && error < 1e-4,
                        "GPU film \(test.recipe.filmID) index \(i), channel \(ch): \(error)")
                    count += 1
                    maximum = max(maximum, error)
                }
            }
        }
        for path in ["film_render.grain.n_sub_layers", "film_render.halation.halation_n_bounces"] {
            for value in [0.0, 1.5, 1e100, Double.infinity] {
                var invalid = EditRecipe()
                invalid.numbers[path] = value
                do {
                    _ = try FilmPipeline(library: library, recipe: invalid)
                    preconditionFailure("Malformed integer recipe was accepted")
                } catch SpectralCore.Failure.invalidShape {}
            }
        }
        var recipe = EditRecipe()
        recipe.flags["camera.auto_exposure"] = false
        let model = try FilmPipeline(library: library, recipe: recipe)
        let first = try await gpu.process(
            input, width: fixture.width, height: fixture.height, pipeline: model, seed: 17)
        let second = try await gpu.process(
            input, width: fixture.width, height: fixture.height, pipeline: model, seed: 17)
        precondition(
            first.pixels == second.pixels,
            "Stochastic GPU graph is not stable for an unchanged source/recipe/seed")
        print(
            "PASS: combined GPU film graph, \(fixture.cases.count) deterministic reference cases / \(count) values, max error \(maximum); stable default stochastic route"
        )
    }
}
