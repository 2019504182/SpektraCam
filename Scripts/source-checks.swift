import CoreGraphics
import Foundation

@main struct Checks {
    static func main() throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(
            data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(colorSpace: space, components: [0.4, 0.4, 0.4, 1])!)
        c.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        let source = c.makeImage()!
        var recipe = EditRecipe()
        let baseline = try SourceImageRenderer.prepare(
            data: nil, fallback: source, recipe: recipe, maximum: 1080)
        recipe.source.exposureEV = 1
        let brighter = try SourceImageRenderer.prepare(
            data: nil, fallback: source, recipe: recipe, maximum: 1080)
        precondition(
            abs(brighter.pixels[0].x / baseline.pixels[0].x - 2) < 1e-4, "Source exposure is not linear +1 EV"
        )
        recipe = EditRecipe()
        recipe.source.warmth = 50
        let warm = try SourceImageRenderer.prepare(data: nil, fallback: source, recipe: recipe, maximum: 1080)
        print("Warmth +50 neutral RGB:", warm.pixels[0])
        precondition(warm.pixels[0].x > warm.pixels[0].z, "Positive warmth cooled the image")
        let blended = try SourceImageRenderer.blend(film: source, source: brighter, amount: 0)
        let roundTrip = try PhotoColorBridge.decode(blended)
        precondition(
            abs(roundTrip[0].x - brighter.pixels[0].x) < 0.005, "Mix 0 did not preserve adjusted source")
        let middle = try SourceImageRenderer.blend(film: source, source: brighter, amount: 0.5)
        let middlePixels = try PhotoColorBridge.decode(middle)
        precondition(
            abs(middlePixels[0].x - (brighter.pixels[0].x + baseline.pixels[0].x) / 2) < 0.005,
            "Mix did not blend in linear light")
        let colorContext = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        colorContext.setFillColor(CGColor(colorSpace: space, components: [0.7, 0.3, 0.15, 1])!)
        colorContext.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        recipe = EditRecipe()
        recipe.source.saturation = 0
        let gray = try SourceImageRenderer.prepare(
            data: nil, fallback: colorContext.makeImage()!, recipe: recipe, maximum: 1080)
        precondition(
            abs(gray.pixels[0].x - gray.pixels[0].y) < 0.001
                && abs(gray.pixels[0].y - gray.pixels[0].z) < 0.001,
            "Source saturation zero did not remove chroma before the model")
        let old = try JSONDecoder().decode(EditRecipe.self, from: Data("{}".utf8))
        precondition(old.source == EditRecipe.Source() && old.mix == 1, "Older recipes changed")
        print(
            "PASS: source EV, warm/cool direction, linear-light Mix endpoints and midpoint, source saturation and backwards-compatible recipes"
        )
    }
}
