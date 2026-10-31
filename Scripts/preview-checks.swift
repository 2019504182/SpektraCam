import CoreGraphics
import Foundation

@main struct Checks {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = root.appendingPathComponent("andreavolpato-spektrafilm/ModelData")
        let width = 1080
        let height = 810
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: space, components: [0.4, 0.5, 0.6, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let source = context.makeImage()!
        let renderer = PhotoRenderer(source: source, directory: data)
        var recipe = EditRecipe()
        let first = try await renderer.render(recipe)
        let started = ProcessInfo.processInfo.systemUptime
        let same = try await renderer.render(recipe)
        let frameMilliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
        let firstPixels = try PhotoColorBridge.decode(first)
        let samePixels = try PhotoColorBridge.decode(same)
        precondition(firstPixels == samePixels, "Stable recipe changed preview")
        recipe.numbers["camera.exposure_compensation_ev"] = 2
        let adjusted = try await renderer.render(recipe)
        let adjustedPixels = try PhotoColorBridge.decode(adjusted)
        precondition(adjustedPixels != firstPixels, "Exposure did not reach preview")
        precondition(
            source.width == width && first.width == width && adjusted.height == height,
            "Preview dimensions changed")
        var sourceEV = EditRecipe()
        sourceEV.source.exposureEV = 1
        let sourceAdjusted = try await renderer.render(sourceEV)
        let sourcePixels = try PhotoColorBridge.decode(sourceAdjusted)
        precondition(sourcePixels != firstPixels, "Auto metering canceled the master source exposure")
        sourceEV.mix = 0
        let unmixed = try await renderer.render(sourceEV)
        let input = try SourceImageRenderer.prepare(
            data: nil, fallback: source, recipe: sourceEV, maximum: 1080)
        let unmixedPixels = try PhotoColorBridge.decode(unmixed)
        precondition(
            abs(unmixedPixels[0].x - input.pixels[0].x) < 0.005, "Mix cache ignored source adjustments")
        sourceEV.mix = 1
        let restored = try await renderer.render(sourceEV)
        let restoredPixels = try PhotoColorBridge.decode(restored)
        precondition(restoredPixels == sourcePixels, "Mix invalidated the wrong film frame")
        print(
            "PASS: preview worker loads bundled resources, stable film frame, film and source exposure changes, Mix cache and immutable source; cached Debug frame \(frameMilliseconds) ms on Mac"
        )
    }
}
