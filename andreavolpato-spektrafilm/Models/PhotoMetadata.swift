import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct PhotoMetadata: Codable, Equatable, Sendable {
    var format = "Photo"
    var colorSpace = "Unknown profile"
    var camera: String?
    var lens: String?
    var exposure: String?
    var width = 0
    var height = 0
    var capturedAt: Date?
    var latitude: Double?
    var longitude: Double?
    var sizeLine: String { "\(format) · \(width) × \(height)" }

    init() {}
    init(properties p: [CFString: Any], type: CFString?, image: CGImage) {
        width = p[kCGImagePropertyPixelWidth] as? Int ?? image.width
        height = p[kCGImagePropertyPixelHeight] as? Int ?? image.height
        if let type, let ext = UTType(type as String)?.preferredFilenameExtension {
            format = ext.uppercased()
        }
        if format == "JPG" { format = "JPEG" }
        if format == "HEIC" { format = "HEIF" }
        colorSpace =
            p[kCGImagePropertyProfileName] as? String ?? image.colorSpace?.name as String?
            ?? "Unknown profile"
        if colorSpace.contains("sRGB") { colorSpace = "sRGB" }
        if colorSpace.contains("Display P3") { colorSpace = "Display P3" }
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        camera = tiff?[kCGImagePropertyTIFFModel] as? String
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any]
        lens = exif?[kCGImagePropertyExifLensModel] as? String
        capturedAt = Self.captureDate(exif: exif, tiff: tiff)
        if let gps = p[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
            let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
            lat.isFinite, lon.isFinite, (0...90).contains(lat), (0...180).contains(lon)
        {
            latitude = gps[kCGImagePropertyGPSLatitudeRef] as? String == "S" ? -lat : lat
            longitude = gps[kCGImagePropertyGPSLongitudeRef] as? String == "W" ? -lon : lon
        }
        var parts = [String]()
        if let seconds = exif?[kCGImagePropertyExifExposureTime] as? Double, seconds.isFinite, seconds >= 1e-9
        {
            parts.append(
                seconds < 1
                    ? "1/\(Int((1 / seconds).rounded()))s"
                    : seconds.formatted(.number.precision(.fractionLength(0...1))) + "s")
        }
        if let f = exif?[kCGImagePropertyExifFNumber] as? Double, f.isFinite, f > 0 {
            parts.append("ƒ/" + f.formatted(.number.precision(.fractionLength(0...1))))
        }
        if let iso = (exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first {
            parts.append("ISO \(iso.intValue)")
        }
        if !parts.isEmpty { exposure = parts.joined(separator: " · ") }
    }
    private static func captureDate(exif: [CFString: Any]?, tiff: [CFString: Any]?) -> Date? {
        guard
            let text = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
                ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
                ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        if let offset = exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXX"
            return formatter.date(from: text + offset)
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: text)
    }

}
