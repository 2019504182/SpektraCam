import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Full-resolution SDR geometry export. Film processing must supply its own renderer.
nonisolated enum PhotoExporter {
    enum Format: String, CaseIterable, Identifiable, Sendable {
        case jpeg = "JPEG", png = "PNG"
        var id: Self { self }
        var type: UTType { self == .jpeg ? .jpeg : .png }
        var suffix: String { self == .jpeg ? "jpg" : "png" }
    }
    enum Failure: LocalizedError {
        case decode, render, encode
        var errorDescription: String? {
            switch self {
            case .decode: "The original photo could not be decoded."
            case .render: "The full-resolution image could not be rendered."
            case .encode: "The export file could not be created."
            }
        }
    }
    enum Size: String, CaseIterable, Identifiable, Sendable {
        case full = "Full", large = "L", medium = "M", small = "S"
        var id: Self { self }
        var maximum: Int? {
            switch self {
            case .full: nil
            case .large: 4096
            case .medium: 2048
            case .small: 1080
            }
        }
    }
    static func decodeSource(_ data: Data, maximum: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            let upright = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: min(
                        maximum ?? max(width, height), max(width, height)),
                ] as CFDictionary)
        else { throw Failure.decode }
        return upright
    }
    static func renderOriginal(_ data: Data, crop: CropSelection, geometry: ImageGeometry) throws -> CGImage {
        let upright = try decodeSource(data)
        // Export has an explicit SDR sRGB contract; source bytes remain untouched.
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: upright.width, height: upright.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.render }
        context.draw(upright, in: CGRect(x: 0, y: 0, width: upright.width, height: upright.height))
        guard let bitmap = context.makeImage(),
            let transformed = GeometryRenderer.render(bitmap, geometry: geometry),
            let result = transformed.cropping(
                to: crop.pixelRect(in: CGSize(width: transformed.width, height: transformed.height)))
        else { throw Failure.render }
        return result
    }
    static func write(
        _ image: CGImage, format: Format, quality: Double = 0.95,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let folder = directory.appending(path: "Spektrafilm-Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Spektrafilm-\(UUID().uuidString).\(format.suffix)")
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, format.type.identifier as CFString, 1, nil)
        else { throw Failure.encode }
        let options: [CFString: Any] =
            format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encode }
        return url
    }
}
