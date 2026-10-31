import Foundation

private struct CurveCase: Decodable {
    let axis: [Double], curves: [[Double]], gamma: Double, input: [[Double]], expected: [[Double]]
}
private struct SpectralCase: Decodable {
    let channels: [[Double]], base: [Double], illuminant: [Double], cmfs: [[Double]], density: [[Double]], xyz: [[Double]]
}
private struct Fixtures: Decodable { let curveCases: [CurveCase], spectralCase: SpectralCase }
@main struct MetalChecks {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let fixture = try decoder.decode(Fixtures.self, from: Data(contentsOf: root.appending(path: "Reference/Fixtures/core-stages.json")))
        let engine = try MetalStages(source: String(contentsOf: root.appending(path: "Scripts/SpectralStages.metal"), encoding: .utf8))
        func vector(_ a: [Double]) -> SIMD4<Float> { .init(Float(a[0]), Float(a[1]), Float(a[2]), 1) }
        var maximum = 0.0, count = 0
        func check(_ actual: Float, _ expected: Double) {
            let error = abs(Double(actual) - expected)
            precondition(error <= 2e-6 + abs(expected) * 3e-6, "GPU parity failure: \(actual) versus \(expected)")
            maximum = max(maximum, error); count += 1
        }
        for f in fixture.curveCases {
            let result = try await engine.densities(f.input.map(vector), axis: f.axis.map { Float($0 / f.gamma) }, curves: f.curves.map(vector))
            for i in result.indices { for ch in 0..<3 { check(result[i][ch], f.expected[i][ch]) } }
        }
        let f = fixture.spectralCase
        let normalization = zip(f.illuminant, f.cmfs).reduce(0) { $0 + $1.0 * $1.1[1] }
        let channels = f.channels.indices.map { i in SIMD4<Float>(Float(f.channels[i][0]), Float(f.channels[i][1]), Float(f.channels[i][2]), Float(f.base[i])) }
        let weights = f.cmfs.indices.map { i in vector(f.cmfs[i].map { $0 * f.illuminant[i] / normalization }) }
        let result = try await engine.xyz(f.density.map(vector), channels: channels, weights: weights)
        for i in result.indices { for ch in 0..<3 { check(result[i][ch], f.xyz[i][ch]) } }
        print("PASS: Metal Float32 stages; \(count) values; max absolute error \(maximum)")
    }
}
