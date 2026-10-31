import CoreGraphics
import Foundation
import ImageIO

@main struct Checks {
    static func main() throws {
        let colors: [[UInt8]] = [
            [255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [128, 128, 128, 255],
            [22, 78, 146, 255], [240, 186, 85, 255],
        ]
        for name in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
            let space = CGColorSpace(name: name)!
            let data = Data(colors.flatMap { $0 })
            let source = CGImage(
                width: 3, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 12, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)!
            let pixels = try PhotoColorBridge.decode(source)
            if name == CGColorSpace.sRGB {
                for i in colors.indices {
                    for ch in 0..<3 {
                        let x = Double(colors[i][ch]) / 255
                        let expected = x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
                        precondition(
                            abs(Double(pixels[i][ch]) - expected) < 5e-5,
                            "sRGB decoding or row orientation at \(i)/\(ch): \(pixels[i][ch]) vs \(expected)")
                    }
                }
            } else {
                precondition(
                    pixels[0].x > 1 && pixels[0].y < 0, "P3 red was silently clipped or treated as sRGB")
            }
            let encoded = pixels.map { pixel -> SIMD4<Float> in
                var result = pixel
                for ch in 0..<3 {
                    let x = Double(pixel[ch])
                    result[ch] = Float(x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055)
                }
                return result
            }
            let image = try PhotoColorBridge.encode(encoded, width: 3, height: 2)
            let decoded = try PhotoColorBridge.decode(image)
            if name == CGColorSpace.sRGB {
                for i in pixels.indices {
                    for ch in 0..<3 {
                        precondition(
                            abs(pixels[i][ch] - decoded[i][ch]) < 5e-5, "Round-trip row/color mismatch")
                    }
                }
                precondition(image.width == 3 && image.height == 2, "Output dimensions changed")
            }
        }
        print("PASS: sRGB transfer/row order round-trip and extended Display P3 conversion")
    }
}
