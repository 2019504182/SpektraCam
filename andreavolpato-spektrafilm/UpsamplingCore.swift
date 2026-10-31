// Hanatos 2025 runtime interpolation ported from spektrafilm 3bb2c2d. GPLv3.
import Foundation

nonisolated enum UpsamplingCore {
    typealias RGB = SpectralCore.RGB
    struct Table2D: Sendable {
        let size: Int
        let samples: [RGB]
        init(size: Int, samples: [RGB]) throws {
            guard size >= 2, samples.count == size * size else { throw SpectralCore.Failure.invalidShape }
            self.size = size
            self.samples = samples
        }
        func sample(_ coordinate: SIMD2<Double>) -> RGB {
            guard coordinate.x.isFinite, coordinate.y.isFinite else { return RGB(repeating: .nan) }
            let scale = Double(size - 1)
            let x = min(max(coordinate.x * scale, 0), scale)
            let y = min(max(coordinate.y * scale, 0), scale)
            let xb = x >= scale ? size - 2 : Int(floor(x))
            let yb = y >= scale ? size - 2 : Int(floor(y))
            let xf = x - Double(xb)
            let yf = y - Double(yb)
            let wx = (0..<4).map { mitchell(xf + 1 - Double($0)) }
            let wy = (0..<4).map { mitchell(yf + 1 - Double($0)) }
            var output = RGB.zero
            var weightSum = 0.0
            for i in 0..<4 {
                let xi = reflected(xb - 1 + i)
                for j in 0..<4 {
                    let yj = reflected(yb - 1 + j)
                    let weight = wx[i] * wy[j]
                    weightSum += weight
                    output += samples[xi * size + yj] * weight
                }
            }
            return weightSum == 0 ? output : output / weightSum
        }
        private func reflected(_ index: Int) -> Int {
            if index < 0 { return -index }
            if index >= size { return 2 * (size - 1) - index }
            return index
        }
        private func mitchell(_ t: Double) -> Double {
            let x = abs(t)
            let b = 1.0 / 3
            let c = 1.0 / 3
            if x < 1 {
                return ((12 - 9 * b - 6 * c) * x * x * x + (-18 + 12 * b + 6 * c) * x * x + 6 - 2 * b) / 6
            }
            if x < 2 {
                return
                    ((-b - 6 * c) * x * x * x + (6 * b + 30 * c) * x * x + (-12 * b - 48 * c) * x + 8 * b + 24
                    * c) / 6
            }
            return 0
        }
    }
    struct FilmExposure: Sendable {
        /// Rows are XYZ outputs for unit R, G and B in the declared linear input space.
        let rgbBasisXYZ: [RGB]
        let table: Table2D
        init(rgbBasisXYZ: [RGB], table: Table2D) throws {
            guard rgbBasisXYZ.count == 3 else { throw SpectralCore.Failure.invalidShape }
            self.rgbBasisXYZ = rgbBasisXYZ
            self.table = table
        }
        func raw(_ linearRGB: RGB) -> RGB {
            let xyz =
                rgbBasisXYZ[0] * linearRGB.x + rgbBasisXYZ[1] * linearRGB.y + rgbBasisXYZ[2] * linearRGB.z
            let brightness = xyz.x + xyz.y + xyz.z
            let xy = SIMD2(xyz.x, xyz.y) / max(brightness, 1e-10)
            let inverseX = 1 - xy.x
            let tc = SIMD2(
                min(max(inverseX * inverseX, 0), 1),
                min(max(xy.y / max(inverseX, 1e-10), 0), 1))
            return table.sample(tc) * (brightness.isNaN ? 0 : brightness)
        }
    }
}
