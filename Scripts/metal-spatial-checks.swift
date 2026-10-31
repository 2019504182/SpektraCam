import Foundation

private struct Case: Decodable {
    let kind: String, width: Int, height: Int, scale: [Double], input: [[Double]], expected: [[Double]]
}
private struct Fixture: Decodable { let cases: [Case] }
@main struct Checks {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "andreavolpato-spektrafilm/ModelData/Spatial.metalSource"), encoding: .utf8)
        let gpu = try MetalSpatial(source: source)
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Reference/Fixtures/spatial-stages.json")))
        func v(_ x: [Double]) -> SIMD3<Double> { .init(x[0], x[1], x[2]) }
        var maximum = 0.0
        var count = 0
        for f in fixture.cases {
            let image = try SpatialCore.Image(width: f.width, height: f.height, pixels: f.input.map(v))
            let result = try await gpu.filter(image, scale: v(f.scale), exponential: f.kind == "exponential")
            for i in result.pixels.indices {
                for ch in 0..<3 {
                    let error = abs(result.pixels[i][ch] - f.expected[i][ch])
                    precondition(
                        error.isFinite && error < 1e-5,
                        "Metal \(f.kind) \(f.width)x\(f.height) sigma \(f.scale), channel \(ch), index \(i): \(error)"
                    )
                    maximum = max(maximum, error)
                    count += 1
                }
            }
        }
        // Long recurrence / large radius: catches coefficient precision and accumulation drift.
        let w = 1080
        let h = 37
        let pixels = (0..<w * h).map { i in
            SIMD3<Double>(Double(i % 97) / 13, Double(i % 13) / 7, Double(i % 19) / 11)
        }
        let image = try SpatialCore.Image(width: w, height: h, pixels: pixels)
        for scale in [SIMD3<Double>(3, 20, 100), SIMD3<Double>(100, 250, 500)] {
            let expected = image.gaussian(scale)
            let result = try await gpu.filter(image, scale: scale)
            for i in pixels.indices {
                for ch in 0..<3 {
                    let error = abs(result.pixels[i][ch] - expected.pixels[i][ch])
                    precondition(error.isFinite && error < 1e-5, "Long recurrence \(scale): \(error)")
                    maximum = max(maximum, error)
                    count += 1
                }
            }
        }
        print(
            "PASS: Metal spatial, \(fixture.cases.count) source fixtures plus long-recursion stress cases; \(count) values; max absolute error \(maximum)"
        )
    }
}
