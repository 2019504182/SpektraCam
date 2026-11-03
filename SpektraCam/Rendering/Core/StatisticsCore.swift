// Philox4x32-10: D. E. Shaw Research, Random123 (BSD-3-Clause).
// Poisson PTRS: Hörmann (1993), checked against NumPy distributions (BSD-3-Clause).
// Notices are retained in ThirdPartyNotices.txt. Native Swift adaptation.
import Foundation

nonisolated enum StatisticsCore {
    enum Failure: Error { case invalidDistribution }

    static func philox(_ counter: SIMD4<UInt32>, key: SIMD2<UInt32>) -> SIMD4<UInt32> {
        var c = counter
        var k = key
        for _ in 0..<10 {
            let a = UInt64(c.x) * 0xD251_1F53
            let b = UInt64(c.z) * 0xCD9E_8D57
            c = SIMD4(
                UInt32(truncatingIfNeeded: b >> 32) ^ c.y ^ k.x, UInt32(truncatingIfNeeded: b),
                UInt32(truncatingIfNeeded: a >> 32) ^ c.w ^ k.y, UInt32(truncatingIfNeeded: a))
            k.x &+= 0x9E37_79B9
            k.y &+= 0xBB67_AE85
        }
        return c
    }
    /// Global pixel index and stage/layer domain give tile-order-independent streams.
    struct Stream: Sendable {
        private let pixel: UInt64, domain: UInt32, seed: UInt64
        private var block: UInt32 = 0, lane = 4
        private var words = SIMD4<UInt32>.zero
        init(pixel: UInt64, domain: UInt32, seed: UInt64) {
            self.pixel = pixel
            self.domain = domain
            self.seed = seed
        }
        mutating func uniform() -> Double {
            if lane == 4 {
                words = StatisticsCore.philox(
                    SIMD4(
                        UInt32(truncatingIfNeeded: pixel), UInt32(truncatingIfNeeded: pixel >> 32), domain,
                        block),
                    key: SIMD2(UInt32(truncatingIfNeeded: seed), UInt32(truncatingIfNeeded: seed >> 32)))
                block &+= 1
                lane = 0
            }
            defer { lane += 1 }
            return (Double(words[lane]) + 0.5) / 4_294_967_296
        }
        mutating func normal() -> Double {
            sqrt(-2 * log(uniform())) * cos(2 * Double.pi * uniform())
        }
        mutating func lognormal(mean: Double, standardDeviation: Double) throws -> Double {
            guard mean.isFinite, mean > 0, standardDeviation.isFinite, standardDeviation >= 0 else {
                throw Failure.invalidDistribution
            }
            let variance = log1p(pow(standardDeviation / mean, 2))
            return exp(log(mean) - variance / 2 + sqrt(variance) * normal())
        }
        /// Exact-distribution sampler (no Gaussian approximation); sequence differs from NumPy.
        mutating func poisson(mean: Double) throws -> Double {
            guard mean.isFinite, mean >= 0, mean <= 1e15 else { throw Failure.invalidDistribution }
            if mean == 0 { return 0 }
            if mean < 10 {
                let limit = exp(-mean)
                var product = 1.0
                var count = 0.0
                repeat {
                    product *= uniform()
                    count += 1
                } while product > limit
                return count - 1
            }
            let b = 0.931 + 2.53 * sqrt(mean)
            let a = -0.059 + 0.02483 * b
            let inverseAlpha = 1.1239 + 1.1328 / (b - 3.4)
            let squeeze = 0.9277 - 3.6224 / (b - 2)
            while true {
                let u = uniform() - 0.5
                let v = uniform()
                let us = 0.5 - abs(u)
                let count = floor((2 * a / us + b) * u + mean + 0.43)
                if count < 0 { continue }
                if us >= 0.07 && v <= squeeze { return count }
                if us < 0.013 && v > us { continue }
                let threshold = log(v) + log(inverseAlpha) - log(a / (us * us) + b)
                if threshold <= StatisticsCore.poissonLogProbability(count, mean: mean) { return count }
            }
        }
    }
    /// Stable near the mode even for very large particle counts.
    static func poissonLogProbability(_ count: Double, mean: Double) -> Double {
        if count == 0 { return -mean }
        if count < 16 { return -mean + count * log(mean) - lgamma(count + 1) }
        let inverse = 1 / count
        let square = inverse * inverse
        let stirlingError =
            inverse
            * (1 / 12.0 - square
                * (1 / 360.0 - square * (1 / 1260.0 - square * (1 / 1680.0 - square / 1188.0))))
        let delta = (count - mean) / mean
        let deviance: Double
        if abs(delta) < 0.1 {
            var power = delta * delta
            var total = power / 2
            for n in 3...24 {
                power *= -delta
                total += power / Double(n * (n - 1))
            }
            deviance = mean * total
        } else {
            deviance = count * log(count / mean) + mean - count
        }
        return -stirlingError - 0.5 * log(2 * Double.pi * count) - deviance
    }
}
