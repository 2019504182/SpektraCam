import Foundation

private struct Case: Decodable {
    let width: Int, height: Int, pitch: Double, parameters: Parameters, input: [[Double]],
        expected: [[Double]]
}
private struct Parameters: Decodable {
    let active: Bool, scatter_amount: Double, scatter_spatial_scale: Double, halation_amount: Double,
        halation_spatial_scale: Double
    let scatter_core_um: [Double], scatter_tail_um: [Double], scatter_tail_weight: [Double],
        halation_strength: [Double], halation_first_sigma_um: [Double]
    let halation_n_bounces: Int, halation_bounce_decay: Double, halation_renormalize: Bool
}
private struct Boost: Decodable {
    let width: Int, height: Int, ev: Double, range: Double, protect: Double, input: [[Double]],
        expected: [[Double]]
}
private struct Fixture: Decodable { let cases: [Case], boost: [Boost] }
@main struct HalationChecks {
    static func main() throws {
        let fixture = try JSONDecoder().decode(
            Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        func v(_ x: [Double]) -> SIMD3<Double> { .init(x[0], x[1], x[2]) }
        var maximum = 0.0
        var count = 0
        func check(_ result: SpatialCore.Image, _ expected: [[Double]]) {
            for i in result.pixels.indices {
                for ch in 0..<3 {
                    let error = abs(result.pixels[i][ch] - expected[i][ch])
                    precondition(error < 1e-9, "Halation/boost mismatch: \(error)")
                    maximum = max(maximum, error)
                    count += 1
                }
            }
        }
        for c in fixture.cases {
            let image = try SpatialCore.Image(width: c.width, height: c.height, pixels: c.input.map(v))
            let q = c.parameters
            var p = HalationCore.Parameters()
            p.active = q.active
            p.scatterAmount = q.scatter_amount
            p.scatterScale = q.scatter_spatial_scale
            p.amount = q.halation_amount
            p.scale = q.halation_spatial_scale
            p.scatterCore = v(q.scatter_core_um)
            p.scatterTail = v(q.scatter_tail_um)
            p.tailWeight = v(q.scatter_tail_weight)
            p.strength = v(q.halation_strength)
            p.firstSigma = v(q.halation_first_sigma_um)
            p.bounces = q.halation_n_bounces
            p.decay = q.halation_bounce_decay
            p.renormalize = q.halation_renormalize
            check(try HalationCore.apply(image, parameters: p, pixelSizeMicrometers: c.pitch), c.expected)
        }
        for c in fixture.boost {
            let image = try SpatialCore.Image(width: c.width, height: c.height, pixels: c.input.map(v))
            check(
                try HighlightBoostCore.apply(image, ev: c.ev, range: c.range, protectEV: c.protect),
                c.expected)
        }
        print(
            "PASS: \(fixture.cases.count) scatter/halation and \(fixture.boost.count) boost cases; \(count) values; max absolute error \(maximum)"
        )
    }
}
