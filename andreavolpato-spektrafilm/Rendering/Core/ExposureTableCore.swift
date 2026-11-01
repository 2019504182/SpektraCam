// Native runtime Hanatos-table preparation and spectral UV/IR filters. spektrafilm 3bb2c2d, GPLv3.
import Accelerate
import Foundation

nonisolated enum ExposureTableCore {
    typealias RGB = SIMD3<Double>
    /// Immutable mapped source; expand to Double once, only if spectral filtering is used.
    /// The sole mutable field is protected by the lock, including every read.
    final class Spectra: @unchecked Sendable {
        private let data: Data
        private let lock = NSLock()
        private var decoded: [Double]?
        init(data: Data) { self.data = data }
        func doubles() -> [Double] {
            lock.withLock {
                if let decoded { return decoded }
                let values = data.withUnsafeBytes { bytes in
                    stride(from: 0, to: bytes.count, by: 2).map {
                        Double(
                            Float16(
                                bitPattern: UInt16(
                                    littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt16.self))))
                    }
                }
                decoded = values
                return values
            }
        }
    }
    static func prepare(
        spectra: [Double], size: Int, wavelengths: [Double], sensitivity: [RGB], window: [RGB],
        illuminant: [Double], coordinates: [SIMD2<Double>], uv: RGB, ir: RGB
    ) throws -> [RGB] {
        let samples = size * size
        let n = wavelengths.count
        guard n > 0, size >= 2, spectra.count == samples * n, coordinates.count == samples,
            sensitivity.count == n, window.count == n, illuminant.count == n,
            uv.y.isFinite, uv.z.isFinite, uv.z > 0, ir.y.isFinite, ir.z.isFinite, ir.z > 0,
            uv.x.isFinite, ir.x.isFinite
        else { throw SpectralCore.Failure.invalidShape }
        let au = min(max(uv.x, 0), 1)
        let ai = min(max(ir.x, 0), 1)
        let band = wavelengths.map { w in
            (1 - au + au * (erf((w - uv.y) / uv.z) * 0.5 + 0.5))
                * (1 - ai + ai * (erf((w - ir.y) / (-ir.z)) * 0.5 + 0.5))
        }
        var source = RGB.zero
        var filtered = RGB.zero
        for i in 0..<n {
            source += sensitivity[i] * illuminant[i]
            filtered += sensitivity[i] * (illuminant[i] * band[i])
        }
        guard (0..<3).allSatisfy({ source[$0] > 0 && filtered[$0] > 0 }) else {
            throw SpectralCore.Failure.invalidCurve
        }
        let normalization = filtered / source
        let modified = (0..<n).map { sensitivity[$0] * band[$0] / normalization }
        var numerator = RGB.zero
        var denominator = RGB.zero
        for i in 0..<n {
            numerator += modified[i] * illuminant[i] * window[i]
            denominator += modified[i] * illuminant[i]
        }
        let windowNormalization = numerator / denominator
        guard (0..<3).allSatisfy({ windowNormalization[$0].isFinite && windowNormalization[$0] > 0 }) else {
            throw SpectralCore.Failure.invalidCurve
        }
        let weights = (0..<n).flatMap { i -> [Double] in
            let v = modified[i] * window[i] / windowNormalization
            return [v.x, v.y, v.z]
        }
        var integrated = Array(repeating: 0.0, count: samples * 3)
        spectra.withUnsafeBufferPointer { a in
            weights.withUnsafeBufferPointer { b in
                integrated.withUnsafeMutableBufferPointer { c in
                    vDSP_mmulD(
                        a.baseAddress!, 1, b.baseAddress!, 1, c.baseAddress!, 1,
                        vDSP_Length(samples), 3, vDSP_Length(n))
                }
            }
        }
        func pixel(_ row: Int, _ column: Int) -> RGB {
            let i = (row * size + column) * 3
            return RGB(integrated[i], integrated[i + 1], integrated[i + 2])
        }
        // Input-gamut compression is a stock-white-specific bilinear remap of this spectral table.
        return coordinates.map { point in
            let x = min(max(point.x, 0), Double(size - 1))
            let y = min(max(point.y, 0), Double(size - 1))
            let ix = Int(floor(x))
            let iy = Int(floor(y))
            let nx = min(ix + 1, size - 1)
            let ny = min(iy + 1, size - 1)
            let tx = x - Double(ix)
            let ty = y - Double(iy)
            return pixel(ix, iy) * (1 - tx) * (1 - ty) + pixel(ix, ny) * (1 - tx) * ty + pixel(nx, iy) * tx
                * (1 - ty) + pixel(nx, ny) * tx * ty
        }
    }
}
