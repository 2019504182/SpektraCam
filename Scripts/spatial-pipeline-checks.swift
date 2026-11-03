import Foundation

private struct Case: Decodable { let recipe: EditRecipe, expected: [[Double]] }
private struct Fixture: Decodable { let width: Int, height: Int, input: [[Double]], cases: [Case] }
@main struct Checks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Reference/Fixtures/spatial-pipeline.json")))
        let library = try ModelLibrary(
            directory: root.appendingPathComponent("SpektraCam/Resources/ModelData"))
        let input = fixture.input.map(ModelLibrary.vector)
        var maximum = 0.0
        var count = 0
        for test in fixture.cases {
            let pipeline = try FilmPipeline(library: library, recipe: test.recipe)
            let output = try pipeline.process(
                input, width: fixture.width, height: fixture.height, stochastic: false)
            for i in output.indices {
                for channel in 0..<3 {
                    let error = abs(output[i][channel] - test.expected[i][channel])
                    precondition(
                        error.isFinite && error < 1e-8,
                        "Spatial composition \(test.recipe.filmID) index \(i) channel \(channel): \(error)")
                    maximum = max(maximum, error)
                    count += 1
                }
            }
        }
        var recipe = EditRecipe()
        recipe.flags["camera.auto_exposure"] = false
        let pipeline = try FilmPipeline(library: library, recipe: recipe)
        let first = try pipeline.process(input, width: fixture.width, height: fixture.height, seed: 101)
        let second = try pipeline.process(input, width: fixture.width, height: fixture.height, seed: 101)
        precondition(first == second, "Identical recipe and seed must produce stable preview")
        precondition(first.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        for unsupported in [
            "camera.filter_uv[0]", "camera.filter_ir[0]",
        ] {
            var r = recipe
            r.numbers[unsupported] = 1
            r.numbers[unsupported.replacingOccurrences(of: "[0]", with: "[2]")] = 0
            do {
                _ = try FilmPipeline(library: library, recipe: r)
                preconditionFailure("Invalid spectral filter accepted: \(unsupported)")
            } catch SpectralCore.Failure.invalidShape {}
        }
        print(
            "PASS: \(fixture.cases.count) deterministic spatial pipeline cases; \(count) values; max absolute error \(maximum); stable stochastic default route and invalid-filter rejection"
        )
    }
}
