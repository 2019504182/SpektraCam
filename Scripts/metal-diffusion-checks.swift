import Foundation

private struct Parameters: Decodable {
    let active: Bool, filter_family: String, strength: Double, spatial_scale: Double, halo_warmth: Double
    let core_intensity: Double, halo_intensity: Double, bloom_intensity: Double, core_size: Double,
        halo_size: Double, bloom_size: Double
}
private struct Case: Decodable {
    let width: Int, height: Int, pitch: Double, radius: Int, parameters: Parameters, input: [[Double]],
        kernel: [[Double]], expected: [[Double]]
}
private struct Strength: Decodable { let family: String, strength: Double, expected: Double }
private struct Fixture: Decodable { let cases: [Case], strengths: [Strength] }
@main struct Checks {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let f = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Reference/Fixtures/diffusion-stages.json")))
        func rgb(_ x: [Double]) -> SIMD3<Double> { .init(x[0], x[1], x[2]) }
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "andreavolpato-spektrafilm/ModelData/Diffusion.metalSource"), encoding: .utf8)
        let gpu = try MetalDiffusion(source: source)
        var count = 0
        var maximum = 0.0
        func check(_ a: Double, _ b: Double) {
            let error = abs(a - b)
            precondition(error.isFinite && error < 3e-5, "Diffusion mismatch \(a) != \(b)")
            count += 1
            maximum = max(maximum, error)
        }
        for c in f.cases {
            let q = c.parameters
            var p = DiffusionCore.Parameters()
            p.active = q.active
            p.family = q.filter_family
            p.strength = q.strength
            p.spatialScale = q.spatial_scale
            p.warmth = q.halo_warmth
            p.intensity = SIMD3(q.core_intensity, q.halo_intensity, q.bloom_intensity)
            p.size = SIMD3(q.core_size, q.halo_size, q.bloom_size)
            let kernel = try DiffusionCore.kernel(radius: c.radius, pixelSize: c.pitch, parameters: p)
            for i in kernel.pixels.indices {
                for ch in 0..<3 { check(kernel.pixels[i][ch], c.kernel[i][ch]) }
            }
            let input = try SpatialCore.Image(width: c.width, height: c.height, pixels: c.input.map(rgb))
            let output = try await gpu.filter(input, pixelSize: c.pitch, parameters: p)
            for i in output.pixels.indices {
                for ch in 0..<3 { check(output.pixels[i][ch], c.expected[i][ch]) }
            }
        }
        for s in f.strengths {
            check(try DiffusionCore.scatter(strength: s.strength, family: s.family), s.expected)
        }
        print(
            "PASS: \(f.cases.count) GPU-generated diffusion PSF/MPSGraph FFT cases, \(f.strengths.count) strength mappings; \(count) values; max absolute error \(maximum)"
        )
    }
}
