import CoreGraphics
import CoreImage
import Foundation

/// Color-managed boundary: tagged photo → linear extended sRGB → encoded SDR sRGB.
/// No transfer curve is applied twice; the film graph consumes linear RGB and returns encoded RGB.
nonisolated enum PhotoColorBridge {
    enum Failure: Error { case invalidImage, bitmap }
    private static let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private static let display = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let context = CIContext(options: [
        .workingColorSpace: linear, .workingFormat: CIFormat.RGBAf,
        .cacheIntermediates: false,
    ])

    static func decode(_ source: CGImage) throws -> [SIMD4<Float>] {
        let count = source.width * source.height
        guard count > 0 else { throw Failure.invalidImage }
        var pixels = Array(repeating: SIMD4<Float>.zero, count: count)
        pixels.withUnsafeMutableBytes { bytes in
            context.render(
                CIImage(cgImage: source), toBitmap: bytes.baseAddress!,
                rowBytes: source.width * 16,
                bounds: CGRect(x: 0, y: 0, width: source.width, height: source.height),
                format: .RGBAf, colorSpace: linear)
        }
        // Photograph editing uses an opaque black background, matching the preview/export contract.
        for i in pixels.indices { pixels[i].w = 1 }
        guard pixels.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw Failure.invalidImage
        }
        return pixels
    }

    static func encode(_ encoded: [SIMD4<Float>], width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0, encoded.count == width * height else { throw Failure.invalidImage }
        let data = encoded.withUnsafeBytes { Data($0) }
        return try encode(data, width: width, height: height)
    }
    static func encode(_ data: Data, width: Int, height: Int) throws -> CGImage {
        guard data.count == width * height * 16 else { throw Failure.invalidImage }
        let input = CIImage(
            bitmapData: data, bytesPerRow: width * 16,
            size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: display)
        guard
            let image = context.createCGImage(
                input, from: input.extent,
                format: .RGBA8, colorSpace: display, deferred: false)
        else { throw Failure.bitmap }
        return image
    }
}
