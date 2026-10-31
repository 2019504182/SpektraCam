import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// App-level input controls precede the pinned photographic model. Auto metering uses the
/// unchanged baseline source so it cannot cancel the user's source exposure adjustment.
nonisolated enum SourceImageRenderer {
    struct Input: Sendable { let pixels: [SIMD4<Float>], width: Int, height: Int }
    enum Failure: LocalizedError {
        case decode, raw
        var errorDescription: String? {
            switch self {
            case .decode: "The source photo could not be decoded."
            case .raw: "This RAW file is not supported by the system decoder."
            }
        }
    }
    private static let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private static let context = CIContext(options: [
        .workingColorSpace: linear, .workingFormat: CIFormat.RGBAf, .cacheIntermediates: false,
    ])

    static func prepare(data: Data?, fallback: CGImage, recipe: EditRecipe, maximum: Int) throws -> Input {
        try autoreleasepool {
            try preparePixels(data: data, fallback: fallback, recipe: recipe, maximum: maximum)
        }
    }
    private static func preparePixels(data: Data?, fallback: CGImage, recipe: EditRecipe, maximum: Int) throws
        -> Input
    {
        var image: CIImage
        var rawInput = false
        if let data, recipe.temperature != nil {
            guard let raw = CIRAWFilter(imageData: data, identifierHint: nil),
                raw.nativeSize.width > 0, raw.nativeSize.height > 0
            else { throw Failure.raw }
            rawInput = true
            raw.scaleFactor = Float(
                min(1, Double(maximum) / max(raw.nativeSize.width, raw.nativeSize.height)))
            // Scene-linear RAW avoids baking Apple's display tone mapping into the film model.
            raw.baselineExposure = 0
            raw.boostAmount = 0
            raw.localToneMapAmount = 0
            raw.isGamutMappingEnabled = false
            raw.exposure = Float(recipe.source.exposureEV)
            if let temperature = recipe.temperature { raw.neutralTemperature = Float(temperature) }
            raw.neutralTint = min(max(raw.neutralTint + Float(recipe.source.tint), -150), 150)
            guard let output = raw.outputImage else { throw Failure.raw }
            image = output
        } else {
            image = CIImage(cgImage: fallback)
        }
        if !rawInput {
            if recipe.source.exposureEV != 0 {
                image = image.applyingFilter(
                    "CIExposureAdjust", parameters: [kCIInputEVKey: recipe.source.exposureEV])
            }
            if recipe.source.warmth != 0 || recipe.source.tint != 0 {
                // Rendered RGB has a defined display white, not a recoverable camera Kelvin value.
                let kelvin = 1_000_000 / (1_000_000 / 6500 + recipe.source.warmth)
                image = image.applyingFilter(
                    "CITemperatureAndTint",
                    parameters: [
                        "inputNeutral": CIVector(x: 6500, y: 0),
                        "inputTargetNeutral": CIVector(x: kelvin, y: recipe.source.tint),
                    ])
            }
        }
        if recipe.source.saturation != 1 {
            image = image.applyingFilter(
                "CIColorControls", parameters: [kCIInputSaturationKey: recipe.source.saturation])
        }
        image = image.composited(over: CIImage(color: CIColor.black).cropped(to: image.extent))
        image = image.transformed(
            by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let width = Int(image.extent.width.rounded())
        let height = Int(image.extent.height.rounded())
        guard width > 0, height > 0 else { throw Failure.decode }
        var pixels = Array(repeating: SIMD4<Float>.zero, count: width * height)
        pixels.withUnsafeMutableBytes { bytes in
            context.render(
                image, toBitmap: bytes.baseAddress!, rowBytes: width * 16,
                bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: linear)
        }
        guard pixels.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw Failure.decode
        }
        return .init(pixels: pixels, width: width, height: height)
    }

    /// Blend in linear light, then return the same explicit SDR sRGB boundary as film output.
    static func blend(film: CGImage, source: Input, amount: Double) throws -> CGImage {
        if amount >= 1 { return film }
        let bytes = source.pixels.withUnsafeBytes { Data($0) }
        let original = CIImage(
            bitmapData: bytes, bytesPerRow: source.width * 16,
            size: CGSize(width: source.width, height: source.height), format: .RGBAf, colorSpace: linear)
        let output = original.applyingFilter(
            "CIDissolveTransition",
            parameters: [
                kCIInputTargetImageKey: CIImage(cgImage: film), kCIInputTimeKey: min(max(amount, 0), 1),
            ])
        guard
            let image = context.createCGImage(
                output, from: original.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, deferred: false)
        else { throw Failure.decode }
        return image
    }
}
