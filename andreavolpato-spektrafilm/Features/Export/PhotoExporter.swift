import CoreGraphics
import CoreImage
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
    static func sourceDimensions(_ data: Data) throws -> CGSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.decode }
        if let type = CGImageSourceGetType(source), UTType(type as String)?.conforms(to: .rawImage) == true {
            guard let raw = CIRAWFilter(imageData: data, identifierHint: type as String) else {
                throw Failure.decode
            }
            return raw.nativeSize
        }
        guard let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = p[kCGImagePropertyPixelWidth] as? Int,
            let height = p[kCGImagePropertyPixelHeight] as? Int
        else { throw Failure.decode }
        return CGSize(width: width, height: height)
    }
    static func decodeSource(_ data: Data, maximum: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.decode }
        if let type = CGImageSourceGetType(source), UTType(type as String)?.conforms(to: .rawImage) == true {
            guard let raw = CIRAWFilter(imageData: data, identifierHint: type as String) else {
                throw Failure.decode
            }
            raw.scaleFactor = Float(
                min(1, Double(maximum ?? Int.max) / max(raw.nativeSize.width, raw.nativeSize.height)))
            guard let image = raw.outputImage,
                let space = CGColorSpace(name: CGColorSpace.sRGB),
                let result = CIContext().createCGImage(
                    image, from: image.extent, format: .RGBA8, colorSpace: space)
            else { throw Failure.decode }
            return result
        }
        guard
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
    static func renderOriginal(
        _ data: Data, crop: CropSelection, geometry: ImageGeometry, maximum: Int? = nil
    ) throws -> CGImage {
        let upright = try decodeSource(data, maximum: maximum)
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

/// Export an untouched library item without applying the editor's default film look.
actor OriginalPhotoExporter {
    private let source: URL
    private var size: PhotoExporter.Size?
    private var image: CGImage?
    private var output: URL?
    init(source: URL) { self.source = source }
    func dimensions() throws -> CGSize {
        try PhotoExporter.sourceDimensions(Data(contentsOf: source))
    }
    func export(size: PhotoExporter.Size, format: PhotoExporter.Format, quality: Double) throws -> (
        URL, Int, Int
    ) {
        try Task.checkCancellation()
        if self.size != size || image == nil {
            let data = try Data(contentsOf: source)
            image = try PhotoExporter.renderOriginal(
                data, crop: CropSelection(), geometry: ImageGeometry(), maximum: size.maximum)
            self.size = size
        }
        try Task.checkCancellation()
        guard let image else { throw PhotoExporter.Failure.render }
        let url = try PhotoExporter.write(image, format: format, quality: quality)
        if let output { try? FileManager.default.removeItem(at: output) }
        output = url
        return (url, image.width, image.height)
    }
    func discard() {
        image = nil
        size = nil
        if let output { try? FileManager.default.removeItem(at: output) }
        output = nil
    }
}
