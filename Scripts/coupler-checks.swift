import Foundation
private struct Case: Decodable {
    let stock: String, positive: Bool, gamma: Double, axis: [Double]
    let curves: [[Double]], matrix: [[Double]], input: [[Double]], expected: [[Double]]
}
private struct Fixtures: Decodable { let cases: [Case] }
@main struct CouplerChecks {
    static func main() throws {
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        func rgb(_ a: [Double]) -> SIMD3<Double> { .init(a[0],a[1],a[2]) }
        var maximum = 0.0, count = 0
        for f in fixtures.cases {
            let matrix = try CouplerCore.Matrix(rows: f.matrix.map(rgb))
            let development = try CouplerCore.NonSpatialDevelopment(axis: f.axis, normalizedCurves: f.curves.map(rgb), gamma: f.gamma, matrix: matrix, positive: f.positive)
            for (input, expected) in zip(f.input, f.expected) {
                let result = development.density(at: rgb(input))
                for channel in 0..<3 {
                    let error = abs(result[channel] - expected[channel])
                    precondition(error < 1e-11, "Coupler mismatch \(f.stock): \(error)")
                    maximum = max(maximum,error);count += 1
                }
            }
        }
        print("PASS: \(fixtures.cases.count) non-spatial coupler cases; \(count) values; max absolute error \(maximum)")
    }
}
