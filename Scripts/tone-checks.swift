import CoreGraphics
import CoreImage
import Foundation

@main struct Checks {
    static func main() throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let values: [UInt8] = (0..<256).flatMap { [UInt8($0), UInt8($0), UInt8($0), UInt8(255)] }
        let image = CGImage(
            width: 256, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 1024, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(values) as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
        var tone = EditRecipe.Tone()
        let neutral = try ToneRenderer.render(image, tone: tone)
        precondition(neutral === image, "Neutral tone changed the frame")
        for pivot in [0.0, 0.1, 0.35, 0.435, 0.9, 1.0] {
            tone.pivot = pivot
            for contrast in [0.25, 0.5, 1.0, 1.5, 2.0] {
                tone.contrast = contrast
                let ramp = (0...1000).map { ToneRenderer.curve(Double($0) / 1000, tone: tone) }
                precondition(ramp.allSatisfy { $0.isFinite && (0...1).contains($0) })
                precondition(
                    zip(ramp, ramp.dropFirst()).allSatisfy { $0 <= $1 }, "Curve reversed tonal order")
                precondition(ramp.first == 0 && ramp.last == 1, "Curve clipped its endpoints")
                if (0.001...0.999).contains(pivot) {
                    precondition(abs(ToneRenderer.curve(pivot, tone: tone) - pivot) < 1e-10)
                }
            }
        }
        for shadow in [-1.0, 0, 1] {
            for highlight in [-1.0, 0, 1] {
                tone = EditRecipe.Tone()
                tone.shadows = shadow
                tone.highlights = highlight
                tone.contrast = 1.4
                let ramp = (0...1000).map { ToneRenderer.curve(Double($0) / 1000, tone: tone) }
                precondition(zip(ramp, ramp.dropFirst()).allSatisfy { $0 <= $1 })
                let p = tone.pivot
                let h = 0.000001
                let left = (ToneRenderer.curve(p, tone: tone) - ToneRenderer.curve(p - h, tone: tone)) / h
                let right = (ToneRenderer.curve(p + h, tone: tone) - ToneRenderer.curve(p, tone: tone)) / h
                precondition(abs(left - right) < 0.0001, "Tonal controls create a kink at the pivot")
            }
        }
        tone = EditRecipe.Tone()
        tone.contrast = 1.5
        let rendered = try ToneRenderer.render(image, tone: tone)
        let pixels = try PhotoColorBridge.decode(rendered)
        var error = 0.0
        for i in 0..<256 {
            let expected = ToneRenderer.curve(Double(i) / 255, tone: tone)
            let y = expected <= 0.04045 ? expected / 12.92 : pow((expected + 0.055) / 1.055, 2.4)
            error = max(error, abs(Double(pixels[i].x) - y))
        }
        precondition(error < 0.01, "Native curve uses the wrong working space: \(error)")
        tone = EditRecipe.Tone()
        tone.shadows = 1
        precondition(ToneRenderer.curve(0.15, tone: tone) > 0.15)
        tone = EditRecipe.Tone()
        tone.highlights = -1
        precondition(ToneRenderer.curve(0.75, tone: tone) < 0.75)
        let color = try PhotoColorBridge.encode([SIMD4<Float>(0.7, 0.35, 0.2, 1)], width: 1, height: 1)
        tone = EditRecipe.Tone()
        tone.monochrome = true
        let gray = try PhotoColorBridge.decode(ToneRenderer.render(color, tone: tone))[0]
        precondition(abs(gray.x - gray.y) < 0.0001 && abs(gray.y - gray.z) < 0.0001)
        let legacy = try JSONDecoder().decode(EditRecipe.self, from: Data("{\"version\":1}".utf8))
        precondition(legacy.version == 2 && legacy.tone.isIdentity && !legacy.monochromeGrain)
        var recipe = EditRecipe()
        recipe.tone.contrast = 1.3
        recipe.monochromeGrain = true
        let restored = try JSONDecoder().decode(EditRecipe.self, from: JSONEncoder().encode(recipe))
        precondition(restored == recipe, "New controls did not survive recipe restart")
        print(
            "PASS: identity, monotonic S-curve, fixed pivot, bounded endpoints, native curve color space (max linear error \(error)), tonal direction, neutral B&W and recipe migration"
        )
    }
}
