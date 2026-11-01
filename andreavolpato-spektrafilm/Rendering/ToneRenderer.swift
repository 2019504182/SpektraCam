import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Native GPU 1D curves in encoded sRGB (Rec.709 primaries). Not a Resolve algorithm clone.
/// The pivot and endpoints stay fixed. Neutral settings bypass this stage.
nonisolated enum ToneRenderer {
    enum Failure: LocalizedError {
        case parameters, render
        var errorDescription: String? { "The tone adjustment could not be rendered." }
    }
    private static let display = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private static let context = CIContext(options: [
        .workingColorSpace: linear, .workingFormat: CIFormat.RGBAf, .cacheIntermediates: false,
    ])

    static func curve(_ value: Double, tone: EditRecipe.Tone) -> Double {
        let p = min(max(tone.pivot, 0.0001), 0.9999)
        if value <= 0 { return 0 }
        if value >= 1 { return 1 }
        if value <= p {
            let t = value / p
            let shifted = t + tone.shadows * t * (1 - t) * (1 - t)
            return p * pow(shifted, tone.contrast)
        }
        let t = (1 - value) / (1 - p)
        let shifted = t - tone.highlights * t * (1 - t) * (1 - t)
        return 1 - (1 - p) * pow(shifted, tone.contrast)
    }
    static func render(_ image: CGImage, tone: EditRecipe.Tone) throws -> CGImage {
        guard [tone.contrast, tone.pivot, tone.shadows, tone.highlights].allSatisfy(\.isFinite),
            (0.25...2).contains(tone.contrast), (0...1).contains(tone.pivot),
            (-1...1).contains(tone.shadows), (-1...1).contains(tone.highlights)
        else { throw Failure.parameters }
        guard !tone.isIdentity else { return image }
        return try autoreleasepool {
            var output = CIImage(cgImage: image)
            if tone.contrast != 1 || tone.shadows != 0 || tone.highlights != 0 {
                var table = [Float]()
                table.reserveCapacity(4096 * 3)
                for i in 0..<4096 {
                    let y = Float(curve(Double(i) / 4095, tone: tone))
                    table.append(contentsOf: [y, y, y])
                }
                let curves = CIFilter.colorCurves()
                curves.inputImage = output
                curves.curvesDomain = CIVector(x: 0, y: 1)
                curves.curvesData = table.withUnsafeBytes { Data($0) }
                curves.colorSpace = display
                guard let transformed = curves.outputImage else { throw Failure.render }
                output = transformed
            }
            if tone.monochrome {
                let y = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
                output = output.applyingFilter(
                    "CIColorMatrix",
                    parameters: [
                        "inputRVector": y, "inputGVector": y, "inputBVector": y,
                    ])
            }
            guard
                let result = context.createCGImage(
                    output, from: output.extent,
                    format: .RGBA8, colorSpace: display, deferred: false)
            else { throw Failure.render }
            return result
        }
    }
}
