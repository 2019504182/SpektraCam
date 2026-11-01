import CoreGraphics
import CoreLocation
import Foundation
import ImageIO

@main struct Checks {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func fix(age: Double = 0, accuracy: Double = 15, vertical: Double = 10) -> CLLocation {
            CLLocation(
                coordinate: .init(latitude: -12.5, longitude: -45.25), altitude: -8,
                horizontalAccuracy: accuracy, verticalAccuracy: vertical,
                timestamp: now.addingTimeInterval(-age))
        }
        let gps = CaptureLocation(fix(), now: now)!.gps
        precondition(gps[kCGImagePropertyGPSLatitudeRef as String] as? String == "S")
        precondition(gps[kCGImagePropertyGPSLongitudeRef as String] as? String == "W")
        precondition(gps[kCGImagePropertyGPSAltitudeRef as String] as? Int == 1)
        precondition(gps[kCGImagePropertyGPSAltitude as String] as? Double == 8)
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let metadata = PhotoMetadata(
            properties: [kCGImagePropertyGPSDictionary: gps], type: nil, image: context.makeImage()!)
        precondition(metadata.latitude == -12.5 && metadata.longitude == -45.25)
        precondition(CaptureLocation(fix(age: 61), now: now) == nil)
        precondition(CaptureLocation(fix(accuracy: -1), now: now) == nil)
        precondition(
            CaptureLocation(fix(vertical: -1), now: now)!.gps[kCGImagePropertyGPSAltitude as String] == nil)
        precondition(gps[kCGImagePropertyGPSDateStamp as String] as? String == "1970:01:12")
        precondition(gps[kCGImagePropertyGPSTimeStamp as String] as? String == "13:46:40.000")
        print("PASS: GPS hemisphere, altitude, UTC and library readback; invalid/stale fixes omitted")
    }
}
