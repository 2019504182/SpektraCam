import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main struct Checks {
    static func main() throws {
        guard CommandLine.arguments.count > 1 else {
            print("SKIP: supply genuine RAW/JPEG paths with --input")
            return
        }
        for path in CommandLine.arguments.dropFirst() {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let photo = ImportedPhoto.decode(data) else {
                preconditionFailure("Import failed: \(path)")
            }
            var recipe = EditRecipe()
            recipe.temperature = photo.rawTemperature
            let initial = try SourceImageRenderer.prepare(
                data: data, fallback: photo.preview, recipe: recipe, maximum: 1080)
            precondition(max(initial.width, initial.height) <= 1081)
            let nativeExtent: CGRect
            if photo.rawTemperature != nil {
                nativeExtent =
                    CIRAWFilter(imageData: data, identifierHint: nil)!.outputImage!.extent
            } else {
                nativeExtent =
                    CIImage(data: data, options: [.applyOrientationProperty: true])!.extent
            }
            precondition(
                abs(
                    Double(initial.width) / Double(initial.height) - nativeExtent.width
                        / nativeExtent.height) < 0.005,
                "Prepared pixels differ from the native oriented aspect ratio")
            recipe.source.exposureEV = 1
            let brighter = try SourceImageRenderer.prepare(
                data: data, fallback: photo.preview, recipe: recipe, maximum: 1080)
            let cached = try SourceImageRenderer.prepare(
                data: nil, fallback: photo.preview, recipe: recipe,
                maximum: 1080, renderedSource: SourceImageRenderer.image(initial))
            precondition(cached.width == brighter.width && cached.height == brighter.height)
            let largest = zip(cached.pixels, brighter.pixels).reduce(0.0) { result, pair in
                (0..<3).reduce(result) {
                    max($0, Double(abs(pair.0[$1] - pair.1[$1])) / max(1, Double(abs(pair.1[$1]))))
                }
            }
            precondition(
                largest < 0.0001, "Cached proxy changed source color or row order: \(largest)")
            let mean0 =
                initial.pixels.reduce(0.0) { $0 + Double($1.y) } / Double(initial.pixels.count)
            let mean1 =
                brighter.pixels.reduce(0.0) { $0 + Double($1.y) } / Double(brighter.pixels.count)
            precondition(mean1 > mean0 * 1.5, "Source EV was cancelled or clipped")
            if photo.rawTemperature != nil {
                let raw = CIRAWFilter(imageData: data, identifierHint: nil)!
                raw.scaleFactor = Float(
                    min(1, 1080 / max(raw.nativeSize.width, raw.nativeSize.height)))
                raw.neutralTemperature = Float(photo.rawTemperature!)
                var lutRecipe = EditRecipe()
                lutRecipe.look.mode = .lut
                lutRecipe.temperature = photo.rawTemperature
                let rendered = try SourceImageRenderer.prepare(
                    data: data, fallback: photo.preview, recipe: lutRecipe, maximum: 1080)
                let expected = try SourceImageRenderer.prepare(
                    data: nil, fallback: photo.preview, recipe: lutRecipe, maximum: 1080,
                    renderedSource: raw.outputImage!)
                let largest = zip(rendered.pixels, expected.pixels).reduce(Float(0)) {
                    result, pair in
                    (0..<3).reduce(result) { max($0, abs(pair.0[$1] - pair.1[$1])) }
                }
                precondition(
                    largest < 0.0001, "RAW photo-LUT input differs from Apple's default rendering")
                precondition(
                    max(photo.width, photo.height)
                        == Int(max(raw.nativeSize.width, raw.nativeSize.height)),
                    "RAW dimensions came from the embedded preview")
                let displayMean =
                    rendered.pixels.reduce(0.0) { $0 + Double($1.y) }
                    / Double(rendered.pixels.count)
                print(
                    "RAW LUT input matches native default; baseline EV", raw.baselineExposure,
                    "mean linear green, scene", mean0, "rendered", displayMean,
                    "original", photo.width, photo.height)
                recipe.source.exposureEV = 0
                recipe.temperature! += 1500
                let warm = try SourceImageRenderer.prepare(
                    data: data, fallback: photo.preview, recipe: recipe, maximum: 1080)
                precondition(warm.pixels != initial.pixels, "RAW Kelvin did not affect pixels")
            }
            let type =
                CGImageSourceGetType(CGImageSourceCreateWithData(data as CFData, nil)!)! as String
            print(
                URL(fileURLWithPath: path).lastPathComponent, type, "RAW",
                photo.rawTemperature as Any,
                "oriented", initial.width, initial.height, "EV brightness ratio", mean1 / mean0)
        }
        print(
            "PASS: provided files decode with upright pixels and source exposure; genuine RAW Kelvin affects decoded data"
        )
    }
}
