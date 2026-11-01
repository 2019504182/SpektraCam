// CAM16-UCS output compression ported from spektrafilm 3bb2c2d. GPLv3.
import Foundation

nonisolated enum GamutCore {
    typealias RGB = SIMD3<Double>
    struct Knee: Sendable {
        let threshold: Double, limit: Double, power: Double
        func compress(_ value: Double) -> Double {
            guard value > threshold else { return value }
            let scale = limit - threshold
            let x = (value - threshold) / scale
            return threshold + scale * x / pow(1 + pow(x, power), 1 / power)
        }
    }
    struct Boundary: Sendable {
        let lightness: [Double], hue: [Double], values: [Double]
        init(lightness: [Double], hue: [Double], values: [Double]) throws {
            guard lightness.count >= 2, hue.count >= 2, values.count == lightness.count * hue.count,
                lightness.last! > lightness.first!, hue[1] > hue[0]
            else { throw SpectralCore.Failure.invalidShape }
            self.lightness = lightness
            self.hue = hue
            self.values = values
        }
        func chroma(_ l: Double, _ h: Double) -> Double {
            let bounded = min(max(l, lightness[0]), lightness.last!)
            let hi = (h - hue[0]) / (hue[1] - hue[0])
            let hf = hi - floor(hi)
            let h0 = ((Int(floor(hi)) % hue.count) + hue.count) % hue.count
            let h1 = (h0 + 1) % hue.count
            let li = (bounded - lightness[0]) / (lightness.last! - lightness[0]) * Double(lightness.count - 1)
            let l0 = min(max(Int(floor(li)), 0), lightness.count - 2)
            let l1 = l0 + 1
            let lf = li - Double(l0)
            return values[l0 * hue.count + h0] * (1 - lf) * (1 - hf) + values[l0 * hue.count + h1] * (1 - lf)
                * hf + values[l1 * hue.count + h0] * lf * (1 - hf) + values[l1 * hue.count + h1] * lf * hf
        }
    }
    struct CAM16Compression: Sendable {
        let appearance: AppearanceCore.CAM16
        let boundary: Boundary
        let matrixToXYZ: [RGB], matrixFromXYZ: [RGB]
        let chromaKnee = Knee(threshold: 0, limit: 1, power: 6)
        let lightnessKnee = Knee(threshold: 0.7, limit: 1, power: 2.2)
        let whiteJ: Double
        init(white: RGB, boundary: Boundary, matrixToXYZ: [RGB], matrixFromXYZ: [RGB]) throws {
            guard matrixToXYZ.count == 3, matrixFromXYZ.count == 3 else {
                throw SpectralCore.Failure.invalidShape
            }
            appearance = AppearanceCore.CAM16(white: white)
            self.boundary = boundary
            self.matrixToXYZ = matrixToXYZ
            self.matrixFromXYZ = matrixFromXYZ
            whiteJ = appearance.ucs(white).x
        }
        func compress(_ rgb: RGB) -> RGB {
            func apply(_ basis: [RGB], _ input: RGB) -> RGB {
                basis[0] * input.x + basis[1] * input.y + basis[2] * input.z
            }
            let jab = appearance.ucs(apply(matrixToXYZ, rgb))
            let j = lightnessKnee.compress(jab.x / whiteJ) * whiteJ
            let c = hypot(jab.y, jab.z)
            let h = atan2(jab.z, jab.y)
            guard j.isFinite else { return RGB(repeating: .nan) }
            // Colour's safe division yields achromatic output for non-finite
            // CAM16 chroma in image arrays (e.g. ProPhoto's imaginary blue).
            if !c.isFinite || !h.isFinite {
                return apply(matrixFromXYZ, appearance.xyz(RGB(j, 0, 0)))
            }
            let maximum = max(boundary.chroma(j, h), 1e-9)
            let newC = chromaKnee.compress(c / maximum) * maximum
            let xyz = appearance.xyz(RGB(j, newC * cos(h), newC * sin(h)))
            return apply(matrixFromXYZ, xyz)
        }
    }
}
