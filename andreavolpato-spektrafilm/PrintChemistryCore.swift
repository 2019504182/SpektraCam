// Coupled print-curve gamma/exhaustion model from spektrafilm 3bb2c2d. GPLv3.
import Foundation

nonisolated enum PrintChemistryCore {
    struct Parameters: Codable, Sendable {
        var active = false
        var gamma = 1.0
        var fastGamma = 1.0
        var slowGamma = 1.0
        var redGamma = 1.0
        var greenGamma = 1.0
        var blueGamma = 1.0
        var exhaustion = 0.0
        enum CodingKeys: String, CodingKey {
            case active, gamma = "gamma_factor", fastGamma = "gamma_factor_fast", slowGamma =
                "gamma_factor_slow"
            case redGamma = "gamma_factor_red", greenGamma = "gamma_factor_green", blueGamma =
                "gamma_factor_blue"
            case exhaustion = "developer_exhaustion"
        }
    }
    struct Model: Sendable {
        let centers: [[Double]], amplitudes: [[Double]], sigmas: [[Double]]
        init(centers: [[Double]], amplitudes: [[Double]], sigmas: [[Double]]) throws {
            guard centers.count == 3, amplitudes.count == 3, sigmas.count == 3,
                centers.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }),
                amplitudes.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }),
                sigmas.allSatisfy({ $0.count == 3 && $0.allSatisfy({ $0.isFinite && $0 > 0 }) })
            else { throw SpectralCore.Failure.invalidShape }
            self.centers = centers
            self.amplitudes = amplitudes
            self.sigmas = sigmas
        }
        func curves(axis: [Double], parameters p: Parameters, positive: Bool) throws -> [SIMD3<Double>] {
            let channelGammas = [p.redGamma, p.greenGamma, p.blueGamma]
            guard
                !p.active
                    || ([p.gamma, p.fastGamma, p.slowGamma] + channelGammas).allSatisfy({
                        $0.isFinite && $0 > 0
                    }) && (0...1).contains(p.exhaustion)
            else { throw SpectralCore.Failure.invalidCurve }
            var output = Array(repeating: SIMD3<Double>.zero, count: axis.count)
            for channel in 0..<3 {
                var mu = centers[channel]
                var sigma = sigmas[channel]
                let amplitude = amplitudes[channel]
                let mix = p.active ? p.exhaustion : 0
                if p.active {
                    let speed = mu.indices.sorted { mu[$0] < mu[$1] }
                    for (rank, layer) in speed.enumerated() {
                        let gamma = p.gamma * channelGammas[channel] * (rank == 0 ? p.fastGamma : p.slowGamma)
                        mu[layer] /= gamma
                        sigma[layer] = max(sigma[layer] / gamma, 0.05)
                    }
                    let offset = Self.centerOffset(
                        mu: mu, amplitude: amplitude, sigma: sigma, mix: mix, positive: positive)
                    mu = mu.map { $0 + offset }
                }
                for i in axis.indices {
                    output[i][channel] = Self.density(
                        axis[i], mu: mu, amplitude: amplitude, sigma: sigma, mix: mix, positive: positive)
                }
            }
            return output
        }
        private static func density(
            _ x: Double, mu: [Double], amplitude: [Double], sigma: [Double], mix: Double, positive: Bool
        ) -> Double {
            var total = 0.0
            let location = -log(log(2.0))
            let width = 0.5 * log(2.0) * sqrt(2 * Double.pi)
            for layer in mu.indices {
                let z = (positive ? -1.0 : 1.0) * (x - mu[layer]) / sigma[layer]
                let gaussian = 0.5 * erfc(-z / sqrt(2))
                let cdf: Double
                if mix > 0 {
                    let gumbel = exp(-exp(-(z / width + location)))
                    cdf = (1 - mix) * gaussian + mix * gumbel
                } else {
                    cdf = gaussian
                }
                total += amplitude[layer] * cdf
            }
            return total
        }
        private static func centerOffset(
            mu: [Double], amplitude: [Double], sigma: [Double], mix: Double, positive: Bool
        ) -> Double {
            if mix <= 1e-8 { return 0 }
            let target = density(0, mu: mu, amplitude: amplitude, sigma: sigma, mix: 0, positive: positive)
            func residual(_ offset: Double) -> Double {
                density(
                    0, mu: mu.map { $0 + offset }, amplitude: amplitude, sigma: sigma, mix: mix,
                    positive: positive) - target
            }
            if abs(residual(0)) <= 1e-12 { return 0 }
            var low = -0.25
            var high = 0.25
            var rLow = residual(-0.25)
            var rHigh = residual(0.25)
            for _ in 0..<12 {
                if rLow == 0 { return low }
                if rHigh == 0 { return high }
                if rLow * rHigh < 0 {
                    // Bracketed solve; tighter than the reference's 1e-10 root tolerance.
                    for _ in 0..<80 {
                        let middle = (low + high) / 2
                        let rMiddle = residual(middle)
                        if rMiddle == 0 || high - low < 1e-12 { return middle }
                        if rLow * rMiddle < 0 {
                            high = middle
                        } else {
                            low = middle
                            rLow = rMiddle
                        }
                    }
                    return (low + high) / 2
                }
                low *= 2
                high *= 2
                rLow = residual(low)
                rHigh = residual(high)
            }
            return 0
        }
    }
}
