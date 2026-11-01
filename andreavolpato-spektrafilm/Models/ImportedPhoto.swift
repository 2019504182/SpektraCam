import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct ImportedPhoto: Sendable {
    static let previewMaximumPixelSize = 1080

    let data: Data
    let preview: CGImage
    let width: Int
    let height: Int
    let rawTemperature: Double?
    var metadata = PhotoMetadata()

    static func decode(_ data: Data) -> Self? {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
            let preview = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: previewMaximumPixelSize,
                ] as CFDictionary)
        else { return nil }
        // Materialize ImageIO's lazy provider before UI and renderer share it.
        // A plain bitmap also avoids concurrent lazy-decoder locks on Simulator.
        let space =
            preview.colorSpace?.model == .rgb ? preview.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let bitmap = CGContext(
                data: nil, width: preview.width, height: preview.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        bitmap.draw(preview, in: CGRect(x: 0, y: 0, width: preview.width, height: preview.height))
        guard let decodedPreview = bitmap.makeImage() else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var temperature: Double?
        if let type = CGImageSourceGetType(source), UTType(type as String)?.conforms(to: .rawImage) == true {
            // A RAW embedded thumbnail is not a substitute for a supported RAW decoder.
            guard let raw = CIRAWFilter(imageData: data, identifierHint: type as String),
                raw.nativeSize.width > 0, raw.nativeSize.height > 0
            else { return nil }
            let value = Double(raw.neutralTemperature)
            guard value.isFinite, (1000...50000).contains(value) else { return nil }
            temperature = value
        }
        return .init(
            data: data, preview: decodedPreview,
            width: properties?[kCGImagePropertyPixelWidth] as? Int ?? preview.width,
            height: properties?[kCGImagePropertyPixelHeight] as? Int ?? preview.height,
            rawTemperature: temperature,
            metadata: PhotoMetadata(
                properties: properties ?? [:], type: CGImageSourceGetType(source), image: decodedPreview))
    }
}
