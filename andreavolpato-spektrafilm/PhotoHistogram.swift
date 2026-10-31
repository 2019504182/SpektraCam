import Accelerate
import CoreGraphics
import Foundation

/// Display-referred, sRGB code-value histograms. Accelerate performs conversion/counting;
/// no image work is performed while SwiftUI lays out the chart.
nonisolated struct PhotoHistogram: Sendable {
    let brightness: [UInt], red: [UInt], green: [UInt], blue: [UInt]
    static let empty = Self(
        brightness: Array(repeating: 0, count: 256), red: Array(repeating: 0, count: 256),
        green: Array(repeating: 0, count: 256), blue: Array(repeating: 0, count: 256))
    static func make(_ image: CGImage) -> Self {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var format = vImage_CGImageFormat(
            bitsPerComponent: 8, bitsPerPixel: 32,
            colorSpace: Unmanaged.passUnretained(space),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            version: 0, decode: nil, renderingIntent: .defaultIntent)
        var buffer = vImage_Buffer()
        guard
            withExtendedLifetime(
                space,
                { vImageBuffer_InitWithCGImage(&buffer, &format, nil, image, vImage_Flags(kvImageNoFlags)) })
                == kvImageNoError
        else { return .empty }
        defer { free(buffer.data) }
        var channels = Array(repeating: UInt(0), count: 4 * 256)
        channels.withUnsafeMutableBufferPointer { counts in
            var pointers = (0..<4).map {
                counts.baseAddress!.advanced(by: $0 * 256) as UnsafeMutablePointer<UInt>?
            }
            pointers.withUnsafeMutableBufferPointer {
                _ = vImageHistogramCalculation_ARGB8888(
                    &buffer, $0.baseAddress!, vImage_Flags(kvImageNoFlags))
            }
        }
        var luma = Array(repeating: UInt8(0), count: image.width * image.height)
        var brightness = Array(repeating: UInt(0), count: 256)
        luma.withUnsafeMutableBytes { bytes in
            var plane = vImage_Buffer(
                data: bytes.baseAddress!, height: buffer.height, width: buffer.width, rowBytes: image.width)
            let matrix: [Int16] = [0, 54, 183, 19]
            matrix.withUnsafeBufferPointer { weights in
                _ = vImageMatrixMultiply_ARGB8888ToPlanar8(
                    &buffer, &plane, weights.baseAddress!, 256, nil, 0, vImage_Flags(kvImageNoFlags))
            }
            brightness.withUnsafeMutableBufferPointer {
                _ = vImageHistogramCalculation_Planar8(&plane, $0.baseAddress!, vImage_Flags(kvImageNoFlags))
            }
        }
        return .init(
            brightness: brightness, red: Array(channels[256..<512]), green: Array(channels[512..<768]),
            blue: Array(channels[768..<1024]))
    }
}

actor HistogramWorker {
    static let shared = HistogramWorker()
    func make(_ image: CGImage) -> PhotoHistogram { PhotoHistogram.make(image) }
}
