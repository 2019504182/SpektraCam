import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct PhotoMetadata: Sendable {
    var format = "Photo"
    var colorSpace = "Unknown profile"
    var camera: String?
    var exposure: String?
    var width = 0
    var height = 0
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
}
