import Foundation

private struct Case: Decodable {
    let stock: String, positive: Bool, curves: [[Double]], layers: [[[Double]]], input: [[Double]],
        expected: [[[Double]]], maximum: [[Double]]
    let pitch: Double, area: Double, scale: [Double], layerScale: [Double], minimum: [Double],
        captured: [[Double]]
}
private struct Particle: Decodable {
    let density: Double, maximum: Double, particles: Double, uniformity: Double, rate: Double, scale: Double,
        mean: Double, variance: Double
}
private struct Fixture: Decodable { let cases: [Case], particles: [Particle] }
@main struct Checks {
    static func main() throws {
        let f = try JSONDecoder().decode(
            Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        func rgb(_ x: [Double]) -> SIMD3<Double> { .init(x[0], x[1], x[2]) }
        var count = 0
        var maximum = 0.0
        func check(_ a: Double, _ b: Double, _ label: String) {
            let error = abs(a - b)
            precondition(error.isFinite && error < 1e-10 * max(1, abs(b)), "\(label): \(a) != \(b)")
            count += 1
            maximum = max(maximum, error)
        }
        for c in f.cases {
            let model = try GrainCore.Layers(
                curves: c.curves.map(rgb), layers: c.layers.map { $0.map(rgb) }, positive: c.positive)
            for i in c.input.indices {
                let result = model.densities(rgb(c.input[i]))
                for layer in 0..<3 {
                    for channel in 0..<3 {
                        check(result[layer][channel], c.expected[i][layer][channel], "\(c.stock) layers")
                    }
                }
            }
            let particles = try model.particlesPerPixel(
                pixelSize: c.pitch, area: c.area, scale: rgb(c.scale), layerScale: rgb(c.layerScale))
            let total = model.maximum.reduce(SIMD3<Double>.zero, +)
            for layer in 0..<3 {
                for channel in 0..<3 {
                    check(model.maximum[layer][channel], c.maximum[layer][channel], "Layer maximum")
                    let captured = c.captured[channel * 3 + layer]
                    check(particles[layer][channel], captured[1], "Particle count")
                    let maxDensity = model.maximum[layer][channel] * (1 + c.minimum[channel] / total[channel])
                    check(maxDensity, captured[0], "Minimum-density allocation")
                }
            }
        }
        for p in f.particles {
            let particle = try GrainCore.Particle(
                density: p.density, maximum: p.maximum, particles: p.particles, uniformity: p.uniformity)
            for (a, b) in [
                (particle.meanCount, p.rate), (particle.densityPerCount, p.scale), (particle.mean, p.mean),
                (particle.variance, p.variance),
            ] { check(a, b, "Particle law") }
        }
        // Validate the marginal noise law after Poisson thinning, including clipping at both ends.
        let draws = 100_000
        for density in [0.02, 0.4, 1.5, 2.2] {
            let p = try GrainCore.Particle(density: density, maximum: 2.2, particles: 60, uniformity: 0.97)
            var sum = 0.0
            var squares = 0.0
            for i in 0..<draws {
                var random = StatisticsCore.Stream(pixel: UInt64(i), domain: 1, seed: 12345)
                let deviation = try p.sample(using: &random) - p.mean
                sum += deviation
                squares += deviation * deviation
            }
            let bias = sum / Double(draws)
            let variance = squares / Double(draws) - bias * bias
            precondition(abs(bias) < 7 * sqrt(p.variance / Double(draws)))
            precondition(abs(variance / p.variance - 1) < 7 * sqrt((2 + 1 / p.meanCount) / Double(draws)))
        }
        // Full flat-field model: independent Poisson layers have additive means/variances.
        // Lognormal microstructure adds the analytically known product variance.
        let stock = f.cases.first { $0.stock == "kodak_portra_400" }!
        let curves = stock.curves.map(rgb)
        let layers = stock.layers.map { $0.map(rgb) }
        let model = try GrainCore.Layers(curves: curves, layers: layers, positive: stock.positive)
        let flat = SIMD3<Double>(0.6, 0.8, 1.1)
        let size = 256
        let pitch = 4.0
        let image = try SpatialCore.Image(
            width: size, height: size, pixels: Array(repeating: flat, count: size * size))
        for multilayer in [false, true] {
            for micro in [false, true] {
                var p = GrainCore.Parameters()
                p.sublayers = multilayer
                p.blur = 0
                p.dyeCloudBlur = 0
                p.microstructure = micro ? SIMD2(0, 1000) : .zero
                let result = try GrainCore.apply(
                    image, curves: curves, layers: layers, positive: stock.positive,
                    pixelSize: pitch, parameters: p, seed: 112358)
                let total = model.maximum.reduce(SIMD3<Double>.zero, +)
                let allocations = model.maximum.map { $0 / total * p.minimum }
                let counts = try model.particlesPerPixel(
                    pixelSize: pitch, area: p.area, scale: p.scale, layerScale: p.layerScale)
                let split = model.densities(flat)
                for ch in 0..<3 {
                    let laws: [GrainCore.Particle]
                    if multilayer {
                        laws = try (0..<3).map { layer in
                            try .init(
                                density: split[layer][ch] + allocations[layer][ch],
                                maximum: model.maximum[layer][ch] + allocations[layer][ch],
                                particles: counts[layer][ch], uniformity: p.uniformity[ch])
                        }
                    } else {
                        let maxCurve = curves.map { $0[ch] }.max()!
                        laws = [
                            try .init(
                                density: flat[ch] + p.minimum[ch], maximum: maxCurve + p.minimum[ch],
                                particles: pitch * pitch / (p.area * p.scale[ch]),
                                uniformity: p.uniformity[ch])
                        ]
                    }
                    let beforeMean = laws.reduce(0) { $0 + $1.mean }
                    var expectedVariance = laws.reduce(0) { $0 + $1.variance }
                    if micro && multilayer {
                        expectedVariance =
                            (expectedVariance + beforeMean * beforeMean) * 1.0625 - beforeMean * beforeMean
                    }
                    let expectedMean = beforeMean - p.minimum[ch]
                    let actualMean = result.pixels.reduce(0) { $0 + $1[ch] } / Double(size * size)
                    let actualVariance =
                        result.pixels.reduce(0) { $0 + pow($1[ch] - actualMean, 2) } / Double(size * size)
                    precondition(
                        abs(actualMean - expectedMean) < 8 * sqrt(expectedVariance / Double(size * size)),
                        "Full grain mean")
                    precondition(abs(actualVariance / expectedVariance - 1) < 0.07, "Full grain variance")
                }
            }
        }
        var blurred = GrainCore.Parameters()
        blurred.microstructure = .zero
        let a = try GrainCore.apply(
            image, curves: curves, layers: layers, positive: stock.positive, pixelSize: pitch,
            parameters: blurred, seed: 7)
        let b = try GrainCore.apply(
            image, curves: curves, layers: layers, positive: stock.positive, pixelSize: pitch,
            parameters: blurred, seed: 7)
        precondition(a.pixels == b.pixels, "Grain flickers with identical source/recipe/seed")
        precondition(a.pixels.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        blurred.active = false
        let bypass = try GrainCore.apply(
            image, curves: curves, layers: layers, positive: stock.positive, pixelSize: pitch,
            parameters: blurred, seed: 7)
        precondition(bypass.pixels == image.pixels)
        print(
            "PASS: \(f.cases.count) stock layer maps, \(f.particles.count) particle cases; \(count) deterministic values (max absolute error \(maximum)); 400,000 particle-law draws"
        )
    }
}
