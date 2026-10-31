// CIECAM16 / CAM16-UCS, matching Colour 0.4.6 at spektrafilm's viewing conditions.
// See ThirdPartyNotices.txt for the Colour BSD-3-Clause notice.
import Foundation

nonisolated enum AppearanceCore {
    typealias XYZ = SIMD3<Double>
    struct CAM16: Sendable {
        let adaptation: XYZ
        let fl: Double
        let n: Double
        let nbb: Double
        let z: Double
        let aw: Double
        let c = 0.69
        let m16 = [
            XYZ(0.401288, 0.650173, -0.051461), XYZ(-0.250268, 1.204414, 0.045854),
            XYZ(-0.002079, 0.048952, 0.953127),
        ]
        let inverse16: [XYZ]

        init(white: XYZ, adaptingLuminance: Double = 64, backgroundY: Double = 20) {
            let white100 = white * 100
            let yw = white100.y
            let rgbWhite = Self.multiply(m16, white100)
            let d = min(max(1 - exp((-adaptingLuminance - 42) / 92) / 3.6, 0), 1)
            adaptation = XYZ(repeating: d * yw) / rgbWhite + XYZ(repeating: 1 - d)
            n = backgroundY / yw
            let k = 1 / (5 * adaptingLuminance + 1)
            let k4 = pow(k, 4)
            fl = 0.2 * k4 * 5 * adaptingLuminance + 0.1 * pow(1 - k4, 2) * cbrt(5 * adaptingLuminance)
            nbb = 0.725 * pow(1 / n, 0.2)
            z = 1.48 + sqrt(n)
            let rgb = adaptation * rgbWhite
            let response = XYZ(Self.response(rgb.x, fl), Self.response(rgb.y, fl), Self.response(rgb.z, fl))
            aw = (2 * response.x + response.y + 0.05 * response.z - 0.305) * nbb
            inverse16 = Self.inverse(m16)
        }
        func ucs(_ xyz: XYZ) -> XYZ {
            let rgb = adaptation * Self.multiply(m16, xyz * 100)
            let r = Self.response(rgb.x, fl)
            let g = Self.response(rgb.y, fl)
            let b = Self.response(rgb.z, fl)
            let a = r - 12 * g / 11 + b / 11
            let opponentB = (r + g - 2 * b) / 9
            let h = atan2(opponentB, a)
            let et = (cos(h + 2) + 3.8) / 4
            let achromatic = (2 * r + g + 0.05 * b - 0.305) * nbb
            let j = 100 * Self.signedPower(achromatic / aw, c * z)
            let denominator = r + g + 21 * b / 20
            let t = denominator == 0 ? 0 : (50000 / 13.0) * nbb * et * hypot(a, opponentB) / denominator
            let chroma =
                Self.signedPower(t, 0.9) * Self.signedPower(j / 100, 0.5) * pow(1.64 - pow(0.29, n), 0.73)
            let m = chroma * pow(fl, 0.25)
            let jp = 1.7 * j / (1 + 0.007 * j)
            let mp = log1p(0.0228 * m) / 0.0228
            return XYZ(jp, mp * cos(h), mp * sin(h))
        }
        func xyz(_ jab: XYZ) -> XYZ {
            let j = jab.x / (1.7 - 0.007 * jab.x)
            let mp = hypot(jab.y, jab.z)
            let h = atan2(jab.z, jab.y)
            let m = expm1(0.0228 * mp) / 0.0228
            let chroma = m / pow(fl, 0.25)
            let t = Self.signedPower(
                chroma / (sqrt(max(j, Double.ulpOfOne) / 100) * pow(1.64 - pow(0.29, n), 0.73)), 1 / 0.9)
            let et = (cos(h + 2) + 3.8) / 4
            let achromatic = aw * Self.signedPower(j / 100, 1 / (c * z))
            let p2 = achromatic / nbb + 0.305
            let gamma = 23 * p2 * t / (23 * (50000 / 13.0) * nbb * et + 11 * t * cos(h) + 108 * t * sin(h))
            let a = gamma * cos(h)
            let b = gamma * sin(h)
            let ra = (460 * p2 + 451 * a + 288 * b) / 1403
            let ga = (460 * p2 - 891 * a - 261 * b) / 1403
            let ba = (460 * p2 - 220 * a - 6300 * b) / 1403
            let rgb =
                XYZ(Self.inverseResponse(ra, fl), Self.inverseResponse(ga, fl), Self.inverseResponse(ba, fl))
                / adaptation
            return Self.multiply(inverse16, rgb) / 100
        }
        private static func response(_ x: Double, _ fl: Double) -> Double {
            let power = pow(fl * abs(x) / 100, 0.42)
            return 400 * (x.sign == .minus ? -1 : 1) * power / (27.13 + power) + 0.1
        }
        private static func inverseResponse(_ x: Double, _ fl: Double) -> Double {
            let value = x - 0.1
            return (value.sign == .minus ? -1 : 1) * (100 / fl)
                * signedPower(27.13 * abs(value) / (400 - abs(value)), 1 / 0.42)
        }
        private static func signedPower(_ x: Double, _ power: Double) -> Double {
            (x.sign == .minus ? -1 : 1) * pow(abs(x), power)
        }
        private static func multiply(_ matrix: [XYZ], _ vector: XYZ) -> XYZ {
            func dot(_ row: XYZ) -> Double { row.x * vector.x + row.y * vector.y + row.z * vector.z }
            return XYZ(dot(matrix[0]), dot(matrix[1]), dot(matrix[2]))
        }
        private static func inverse(_ matrix: [XYZ]) -> [XYZ] {
            func cross(_ a: XYZ, _ b: XYZ) -> XYZ {
                XYZ(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
            }
            let a = matrix[0]
            let b = matrix[1]
            let c = matrix[2]
            let x = cross(b, c)
            let y = cross(c, a)
            let z = cross(a, b)
            let determinant = a.x * x.x + a.y * x.y + a.z * x.z
            return [
                XYZ(x.x, y.x, z.x) / determinant, XYZ(x.y, y.y, z.y) / determinant,
                XYZ(x.z, y.z, z.z) / determinant,
            ]
        }
    }
}
