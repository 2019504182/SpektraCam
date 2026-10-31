// Native mathematical stages ported from spektrafilm 3bb2c2d.
// Copyright Andrea Volpato and contributors. GPLv3; see LICENSE.
import Foundation

/// Double-precision baseline. Optimized implementations must match these fixtures.
nonisolated enum SpectralCore {
    typealias RGB = SIMD3<Double>
    enum Failure: Error { case invalidShape, invalidCurve }

    struct DensityCurve: Sendable {
        let axis: [Double]
        let values: [RGB]
        init(axis: [Double], values: [RGB], gamma: Double = 1) throws {
            guard axis.count == values.count, axis.count >= 2 else { throw Failure.invalidShape }
            guard gamma.isFinite && gamma > 0, axis.allSatisfy(\.isFinite),
                zip(axis, axis.dropFirst()).allSatisfy({ $0 <= $1 }),
                values.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            else { throw Failure.invalidCurve }
            self.axis = axis.map { $0 / gamma }
            self.values = values
        }
        func density(at exposure: RGB) -> RGB {
            RGB(
                interpolate(exposure.x, channel: 0), interpolate(exposure.y, channel: 1),
                interpolate(exposure.z, channel: 2))
        }
        private func interpolate(_ x: Double, channel: Int) -> Double {
            if x.isNaN { return x }
            if x <= axis[0] { return values[0][channel] }
            let last = axis.count - 1
            if x >= axis[last] { return values[last][channel] }
            // Upper bound preserves upstream's right-biased repeated-axis matches.
            var low = 0
            var high = axis.count
            while low < high {
                let middle = (low + high) / 2
                if axis[middle] <= x { low = middle + 1 } else { high = middle }
            }
            let i = low - 1
            let dx = axis[i + 1] - axis[i]
            let t = dx == 0 ? 0 : (x - axis[i]) * (1 / dx)
            return values[i][channel] + t * (values[i + 1][channel] - values[i][channel])
        }
    }

    struct SpectralBasis: Sendable {
        let channels: [RGB]
        let base: [Double]
        let illuminant: [Double]
        let cmfs: [RGB]
        let normalization: Double

        init(channels: [RGB], base: [Double], illuminant: [Double], cmfs: [RGB]) throws {
            guard channels.count == base.count, channels.count == illuminant.count,
                channels.count == cmfs.count, !channels.isEmpty
            else { throw Failure.invalidShape }
            let normalization = zip(illuminant, cmfs).reduce(0) { $0 + $1.0 * $1.1.y }
            guard normalization.isFinite && normalization > 0 else { throw Failure.invalidShape }
            self.channels = channels
            self.base = base
            self.illuminant = illuminant
            self.cmfs = cmfs
            self.normalization = normalization
        }
        func densitySpectrum(_ density: RGB) -> [Double] {
            channels.indices.map { i in
                density.x * channels[i].x + density.y * channels[i].y + density.z * channels[i].z + base[i]
            }
        }
        func transmittedLight(_ spectrum: [Double]) throws -> [Double] {
            guard spectrum.count == channels.count else { throw Failure.invalidShape }
            return spectrum.indices.map { i in
                let value = pow(10, -spectrum[i]) * illuminant[i]
                return value.isNaN ? 0 : value
            }
        }
        func xyz(_ density: RGB) -> RGB {
            var sum = RGB.zero
            for i in channels.indices {
                let d =
                    density.x * channels[i].x + density.y * channels[i].y + density.z * channels[i].z
                    + base[i]
                let light = pow(10, -d) * illuminant[i]
                if !light.isNaN { sum += cmfs[i] * light }
            }
            return sum / normalization
        }
    }
}
