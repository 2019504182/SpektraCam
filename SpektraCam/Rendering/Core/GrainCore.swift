// Layer and particle mathematics from spektrafilm 3bb2c2d. GPLv3.
import Foundation

nonisolated enum GrainCore {
    typealias RGB = SIMD3<Double>
    struct Parameters: Sendable {
        var active = true, sublayers = true
        var area = 0.2, scale = RGB(1.6, 1.6, 3.2), layerScale = RGB(2, 1, 0.5)
        var minimum = RGB(repeating: 0.03), uniformity = RGB(0.97, 0.99, 0.97)
        var blur = 0.65, dyeCloudBlur = 1.0, microstructure = SIMD2<Double>(0.2, 30)
        var simpleSublayers = 1
    }

    /// Same statistical model as the reference. Philox gives a stable native noise field;
    /// individual random samples intentionally do not reproduce NumPy's sequence.
    static func apply(
        _ density: SpatialCore.Image, curves: [RGB], layers: [[RGB]], positive: Bool,
        pixelSize: Double, parameters p: Parameters, seed: UInt64
    ) throws -> SpatialCore.Image {
        guard p.active else { return density }
        guard pixelSize.isFinite, pixelSize > 0, p.area.isFinite, p.area > 0,
            (0..<3).allSatisfy({
                p.scale[$0].isFinite && p.scale[$0] > 0 && p.minimum[$0].isFinite && p.minimum[$0] >= 0
            }),
            p.blur.isFinite, p.blur >= 0, p.dyeCloudBlur.isFinite, p.dyeCloudBlur >= 0,
            p.microstructure.x.isFinite, p.microstructure.y.isFinite, p.microstructure.x >= 0,
            p.microstructure.y >= 0,
            p.simpleSublayers >= 1, p.simpleSublayers <= 100
        else { throw StatisticsCore.Failure.invalidDistribution }
        var output = density
        output.pixels = Array(repeating: .zero, count: density.pixels.count)
        if p.sublayers {
            let model = try Layers(curves: curves, layers: layers, positive: positive)
            let particles = try model.particlesPerPixel(
                pixelSize: pixelSize, area: p.area, scale: p.scale, layerScale: p.layerScale)
            let total = model.maximum.reduce(RGB.zero, +)
            let minimum = model.maximum.map { $0 / total * p.minimum }
            let input = density.pixels.map { model.densities($0) }
            for layer in 0..<3 {
                var component = density
                let maximum = model.maximum[layer] + minimum[layer]
                for i in component.pixels.indices {
                    for channel in 0..<3 {
                        let law = try Particle(
                            density: input[i][layer][channel] + minimum[layer][channel],
                            maximum: maximum[channel], particles: particles[layer][channel],
                            uniformity: p.uniformity[channel])
                        var random = StatisticsCore.Stream(
                            pixel: UInt64(i), domain: UInt32(layer * 3 + channel), seed: seed)
                        component.pixels[i][channel] = try law.sample(using: &random)
                    }
                }
                if p.dyeCloudBlur > 0 {
                    let od = maximum / particles[layer]
                    let sigma = RGB(sqrt(od.x), sqrt(od.y), sqrt(od.z)) * p.dyeCloudBlur
                    component = component.gaussian(sigma)
                }
                for i in output.pixels.indices { output.pixels[i] += component.pixels[i] }
            }
            let microSigma = p.microstructure.y * 0.001 / pixelSize
            if microSigma > 0.05 {
                var clumping = density
                for i in clumping.pixels.indices {
                    for channel in 0..<3 {
                        var random = StatisticsCore.Stream(
                            pixel: UInt64(i), domain: UInt32(512 + channel), seed: seed)
                        clumping.pixels[i][channel] = try random.lognormal(
                            mean: 1, standardDeviation: microSigma)
                    }
                }
                let microBlur = p.microstructure.x / pixelSize
                if microBlur > 0.4 { clumping = clumping.gaussian(RGB(repeating: microBlur)) }
                for i in output.pixels.indices { output.pixels[i] *= clumping.pixels[i] }
            }
        } else {
            guard !curves.isEmpty else { throw SpectralCore.Failure.invalidShape }
            let maximum =
                curves.reduce(RGB(repeating: -.infinity)) {
                    RGB(max($0.x, $1.x), max($0.y, $1.y), max($0.z, $1.z))
                } + p.minimum
            let particles =
                RGB(repeating: pixelSize * pixelSize) / (p.scale * p.area * Double(p.simpleSublayers))
            for i in density.pixels.indices {
                for channel in 0..<3 {
                    let law = try Particle(
                        density: density.pixels[i][channel] + p.minimum[channel], maximum: maximum[channel],
                        particles: particles[channel], uniformity: p.uniformity[channel])
                    for layer in 0..<p.simpleSublayers {
                        var random = StatisticsCore.Stream(
                            pixel: UInt64(i), domain: UInt32(layer * 3 + channel), seed: seed)
                        output.pixels[i][channel] +=
                            try law.sample(using: &random) / Double(p.simpleSublayers)
                    }
                }
            }
        }
        for i in output.pixels.indices { output.pixels[i] -= p.minimum }
        // The reference uses different thresholds for its simple and multilayer paths.
        if p.blur > (p.sublayers ? 0 : 0.4) { output = output.gaussian(RGB(repeating: p.blur)) }
        return output
    }
    struct Particle: Sendable {
        let probability: Double, saturation: Double, meanCount: Double, densityPerCount: Double
        let mean: Double, variance: Double
        init(density: Double, maximum: Double, particles: Double, uniformity: Double) throws {
            guard density.isFinite, maximum.isFinite, maximum > 0, particles.isFinite, particles > 0,
                uniformity.isFinite, (0...1).contains(uniformity)
            else { throw StatisticsCore.Failure.invalidDistribution }
            probability = min(max(density / maximum, 1e-6), 1 - 1e-6)
            saturation = 1 - probability * uniformity * (1 - 1e-6)
            // Poisson thinning: Binomial(Poisson(n/s), p) has law Poisson(n*p/s).
            meanCount = particles * probability / saturation
            densityPerCount = maximum / particles * saturation
            mean = meanCount * densityPerCount
            variance = meanCount * densityPerCount * densityPerCount
        }
        func sample(using random: inout StatisticsCore.Stream) throws -> Double {
            try random.poisson(mean: meanCount) * densityPerCount
        }
    }
    /// Source interpolation maps developed channel density back to its three emulsion layers.
    struct Layers: Sendable {
        struct Interpolation: Sendable {
            let axis: [Double], values: [RGB]
            func value(_ x: Double) -> RGB {
                if x <= axis[0] { return values[0] }
                if x >= axis[axis.count - 1] { return values[values.count - 1] }
                var low = 0
                var high = axis.count
                while low < high {
                    let middle = (low + high) / 2
                    if axis[middle] <= x { low = middle + 1 } else { high = middle }
                }
                let i = low - 1
                let dx = axis[i + 1] - axis[i]
                let t = dx == 0 ? 0 : (x - axis[i]) * (1 / dx)
                return values[i] + (values[i + 1] - values[i]) * t
            }
        }
        let interpolation: [Interpolation]
        let maximum: [RGB]
        let positive: Bool
        init(curves: [RGB], layers: [[RGB]], positive: Bool) throws {
            guard curves.count == layers.count, curves.count >= 2, layers.allSatisfy({ $0.count == 3 }) else {
                throw SpectralCore.Failure.invalidShape
            }
            self.positive = positive
            var interpolation = [Interpolation]()
            for channel in 0..<3 {
                let axis = curves.map { positive ? -$0[channel] : $0[channel] }
                let values = layers.map { RGB($0[0][channel], $0[1][channel], $0[2][channel]) }
                guard axis.allSatisfy(\.isFinite),
                    values.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
                else {
                    throw SpectralCore.Failure.invalidCurve
                }
                // Upstream stock density axes contain small local reversals. Preserve its
                // exact searchsorted path; sorting or monotonic fitting would change the model.
                interpolation.append(.init(axis: axis, values: values))
            }
            self.interpolation = interpolation
            maximum = (0..<3).map { layer in
                layers.map { $0[layer] }.reduce(RGB(repeating: -.infinity)) {
                    RGB(max($0.x, $1.x), max($0.y, $1.y), max($0.z, $1.z))
                }
            }
        }
        func densities(_ density: RGB) -> [RGB] {
            var output = Array(repeating: RGB.zero, count: 3)
            for channel in 0..<3 {
                let value = positive ? -density[channel] : density[channel]
                let layers = interpolation[channel].value(value)
                for layer in 0..<3 { output[layer][channel] = layers[layer] }
            }
            return output
        }
        func particlesPerPixel(pixelSize: Double, area: Double, scale: RGB, layerScale: RGB) throws -> [RGB] {
            guard pixelSize.isFinite, pixelSize > 0, area.isFinite, area > 0,
                (0..<3).allSatisfy({
                    scale[$0].isFinite && scale[$0] > 0 && layerScale[$0].isFinite && layerScale[$0] > 0
                })
            else {
                throw StatisticsCore.Failure.invalidDistribution
            }
            let total = maximum.reduce(RGB.zero, +)
            guard (0..<3).allSatisfy({ total[$0] > 0 }) else { throw SpectralCore.Failure.invalidCurve }
            return (0..<3).map {
                maximum[$0] / total * (pixelSize * pixelSize) / (scale * area * layerScale[$0])
            }
        }
    }
}
