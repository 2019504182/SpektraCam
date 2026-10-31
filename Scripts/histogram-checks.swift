import CoreGraphics
import Foundation

@main struct Checks {
    static func main() {
        let bytes: [UInt8] = [255,0,0,255, 0,255,0,255, 0,0,255,255, 0,0,0,255, 255,255,255,255]
        let image = CGImage(width: 5,height: 1,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: 20,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let histogram = PhotoHistogram.make(image)
        for bins in [histogram.brightness,histogram.red,histogram.green,histogram.blue] { precondition(bins.reduce(0,+)==5,"Histogram lost pixels") }
        precondition(histogram.red[255]==2 && histogram.red[0]==3)
        precondition(histogram.green[255]==2 && histogram.blue[255]==2)
        precondition(histogram.brightness[0]==1 && histogram.brightness[255]==1)
        print("PASS: native histogram channel ordering, brightness endpoints and count conservation")
    }
}
