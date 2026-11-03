import Foundation

private struct NoiseCase: Decodable {
    let name: String, recipe: EditRecipe, mean: [Double], variance: [Double], lag: [Double],
        correlation: [[Double]]
}
private struct Fixture: Decodable { let width: Int, height: Int, input: Double, cases: [NoiseCase] }
@main struct Checks {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = root.appendingPathComponent("SpektraCam/Resources/ModelData")
        let sources = try ["ColorPipeline", "Spatial", "Grain", "Diffusion", "FilmPipeline"].map {
            try String(contentsOf: data.appendingPathComponent($0 + ".metalSource"), encoding: .utf8)
        }
        let gpu = try MetalFilmPipeline(sources: sources)
        let library = try ModelLibrary(directory: data)
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Reference/Fixtures/film-noise.json")))
        let count = fixture.width * fixture.height
        let input = Array(
            repeating: SIMD4<Float>(Float(fixture.input), Float(fixture.input), Float(fixture.input), 1),
            count: count)
        var maxVarianceError = 0.0
        var reports = [[String: Any]]()
        for test in fixture.cases {
            let pipeline = try FilmPipeline(library: library, recipe: test.recipe)
            let frame = try await gpu.process(
                input, width: fixture.width, height: fixture.height, pipeline: pipeline, seed: 17,
                autoExposureEV: 0)
            var mean = SIMD3<Double>.zero
            for p in frame.pixels { mean += SIMD3(Double(p.x), Double(p.y), Double(p.z)) }
            mean /= Double(count)
            var variance = SIMD3<Double>.zero
            var lag = SIMD3<Double>.zero
            var covariance = Array(repeating: SIMD3<Double>.zero, count: 3)
            for i in frame.pixels.indices {
                let p = frame.pixels[i]
                let delta = SIMD3(Double(p.x), Double(p.y), Double(p.z)) - mean
                variance += delta * delta
                for ch in 0..<3 { covariance[ch] += delta * delta[ch] }
                if i % fixture.width != fixture.width - 1 {
                    let q = frame.pixels[i + 1]
                    lag += delta * (SIMD3(Double(q.x), Double(q.y), Double(q.z)) - mean)
                }
            }
            variance /= Double(count)
            lag /= Double(fixture.height * (fixture.width - 1))
            lag /= variance
            for ch in 0..<3 {
                // Conservative effective sample count for these spatially filtered finite fields.
                let standardError = sqrt(test.variance[ch] / (Double(count) / 16))
                precondition(
                    abs(mean[ch] - test.mean[ch]) < 7 * standardError + 5e-5,
                    "Film mean \(test.name), \(ch): \(mean[ch]) vs \(test.mean[ch])")
                let relative = abs(variance[ch] / test.variance[ch] - 1)
                maxVarianceError = max(maxVarianceError, relative)
                precondition(
                    relative < 0.16,
                    "Film variance \(test.name), \(ch): \(variance[ch]) vs \(test.variance[ch]) (\(relative))"
                )
                precondition(
                    abs(lag[ch] - test.lag[ch]) < 0.065,
                    "Film lag correlation \(test.name), \(ch): \(lag[ch]) vs \(test.lag[ch])")
                for other in 0..<3 {
                    let correlation =
                        covariance[ch][other] / Double(count) / sqrt(variance[ch] * variance[other])
                    precondition(
                        abs(correlation - test.correlation[ch][other]) < 0.065,
                        "Film RGB correlation \(test.name) \(ch)/\(other): \(correlation) vs \(test.correlation[ch][other])"
                    )
                }
            }
            reports.append([
                "case": test.name, "mean": [mean.x, mean.y, mean.z],
                "variance": [variance.x, variance.y, variance.z], "lag": [lag.x, lag.y, lag.z],
            ])
        }
        let destination = root.appendingPathComponent("Reference/results/film-noise.json")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(
            withJSONObject: ["cases": reports, "maximumRelativeVarianceDifference": maxVarianceError],
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: destination)
        print(
            "PASS: \(fixture.cases.count) whole-film stochastic reference cases; means, RGB covariance, lag-one correlation and variance (maximum relative difference \(maxVarianceError))"
        )
    }
}
