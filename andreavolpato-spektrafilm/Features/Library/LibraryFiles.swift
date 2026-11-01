import CoreGraphics
import CoreTransferable
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Own the transfer file until the app has copied it into its library.
nonisolated final class LibraryImportFile: Transferable, Sendable {
    let url: URL
    private let temporaryDirectory: URL
    init(received: ReceivedTransferredFile) throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        url = temporaryDirectory.appendingPathComponent(received.file.lastPathComponent)
        do { try FileManager.default.copyItem(at: received.file, to: url) } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }
    }
    deinit { try? FileManager.default.removeItem(at: temporaryDirectory) }
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .rawImage) { try LibraryImportFile(received: $0) }
        FileRepresentation(importedContentType: .image) { try LibraryImportFile(received: $0) }
    }
}

actor LibraryFiles {
    enum Failure: LocalizedError {
        case image, missing
        var errorDescription: String? {
            switch self {
            case .image: "This image format is not supported."
            case .missing: "The original photo is not available."
            }
        }
    }
    nonisolated let root: URL
    nonisolated let cache: URL
    init(root: URL, cache: URL, validIDs: Set<UUID>) throws {
        self.root = root
        self.cache = cache
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Originals"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        // A delete stages files before the database commit. Restore an interrupted delete.
        let manager = FileManager.default
        let originals = root.appendingPathComponent("Originals")
        let trash = root.appendingPathComponent("Trash")
        if manager.fileExists(atPath: trash.path) {
            for folder in try manager.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) {
                let target = originals.appendingPathComponent(folder.lastPathComponent)
                if let id = UUID(uuidString: folder.lastPathComponent), validIDs.contains(id),
                    !manager.fileExists(atPath: target.path)
                {
                    try manager.moveItem(at: folder, to: target)
                } else {
                    try manager.removeItem(at: folder)
                }
            }
        }
        // Imports become visible only after an index commit. Remove incomplete app copies.
        for folder in try manager.contentsOfDirectory(at: originals, includingPropertiesForKeys: nil) {
            if folder.lastPathComponent.hasPrefix(".incoming-")
                || UUID(uuidString: folder.lastPathComponent).map({ !validIDs.contains($0) }) == true
            {
                try manager.removeItem(at: folder)
            }
        }
    }
    nonisolated func sourceURL(_ photo: LibraryPhoto) -> URL {
        root.appendingPathComponent("Originals").appendingPathComponent(photo.id.uuidString)
            .appendingPathComponent("original." + photo.fileExtension)
    }
    private func cacheURL(_ photo: LibraryPhoto, thumbnail: Bool) -> URL {
        cache.appendingPathComponent(photo.id.uuidString)
            .appendingPathComponent(photo.renderKey + (thumbnail ? "-thumb.jpg" : "-preview.jpg"))
    }
    func importPhoto(from url: URL, now: Date = Date()) throws -> LibraryPhoto {
        try Task.checkCancellation()
        guard
            let source = CGImageSourceCreateWithURL(
                url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let type = CGImageSourceGetType(source), let thumbnail = Self.thumbnail(source, maximum: 384)
        else { throw Failure.image }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let metadata = PhotoMetadata(properties: properties, type: type, image: thumbnail)
        let identifier = type as String
        let uti = UTType(identifier)
        let ext = uti?.preferredFilenameExtension ?? "image"
        let hash = try Self.digest(url)
        let photo = LibraryPhoto(
            id: UUID(), filename: url.lastPathComponent, fileExtension: ext,
            contentHash: hash, isRAW: uti?.conforms(to: .rawImage) == true,
            importedAt: now, metadata: metadata)
        let folder = sourceURL(photo).deletingLastPathComponent()
        let staging = folder.deletingLastPathComponent().appendingPathComponent(
            ".incoming-" + photo.id.uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: url, to: staging.appendingPathComponent("original." + ext))
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: staging, to: folder)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        try? Self.writeJPEG(thumbnail, to: cacheURL(photo, thumbnail: true))
        return photo
    }
    func cachedImage(_ photo: LibraryPhoto, thumbnail: Bool) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(cacheURL(photo, thumbnail: thumbnail) as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
    func originalImage(_ photo: LibraryPhoto, thumbnail: Bool) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithURL(
                sourceURL(photo) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let image = Self.thumbnail(source, maximum: thumbnail ? 384 : 1080)
        else { throw Failure.image }
        try? Self.writeJPEG(image, to: cacheURL(photo, thumbnail: thumbnail))
        return image
    }
    func decodedPhoto(_ photo: LibraryPhoto) throws -> ImportedPhoto {
        let data = try Data(contentsOf: sourceURL(photo))
        guard let result = ImportedPhoto.decode(data) else { throw Failure.image }
        return result
    }
    func storePreview(_ image: CGImage, photo: LibraryPhoto) throws {
        try Self.writeJPEG(image, to: cacheURL(photo, thumbnail: false))
        guard let source = CGImageSourceCreateWithURL(cacheURL(photo, thumbnail: false) as CFURL, nil),
            let small = Self.thumbnail(source, maximum: 384)
        else { throw Failure.image }
        try Self.writeJPEG(small, to: cacheURL(photo, thumbnail: true))
        // Retain one cached recipe per photo. The original can rebuild older frames.
        let keep = Set([cacheURL(photo, thumbnail: true), cacheURL(photo, thumbnail: false)])
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: cache.appendingPathComponent(photo.id.uuidString), includingPropertiesForKeys: nil)
        {
            for url in entries where !keep.contains(url) { try? FileManager.default.removeItem(at: url) }
        }
    }
    func removeFiles(_ photo: LibraryPhoto) throws {
        let folder = sourceURL(photo).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        try? FileManager.default.removeItem(at: cache.appendingPathComponent(photo.id.uuidString))
    }
    func stageRemoval(_ photo: LibraryPhoto) throws -> URL {
        let trash = root.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let target = trash.appendingPathComponent(photo.id.uuidString)
        let source = sourceURL(photo).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: source.path) {
            try FileManager.default.moveItem(at: source, to: target)
        }
        return target
    }
    func restore(_ staged: URL, photo: LibraryPhoto) throws {
        if FileManager.default.fileExists(atPath: staged.path) {
            try FileManager.default.moveItem(at: staged, to: sourceURL(photo).deletingLastPathComponent())
        }
    }
    func finishRemoval(_ staged: URL, photo: LibraryPhoto) {
        try? FileManager.default.removeItem(at: staged)
        try? FileManager.default.removeItem(at: cache.appendingPathComponent(photo.id.uuidString))
    }
    private static func thumbnail(_ source: CGImageSource, maximum: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximum,
            ] as CFDictionary)
    }
    private static func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = NSMutableData()
        guard let out = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw Failure.image }
        CGImageDestinationAddImage(
            out, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(out) else { throw Failure.image }
        try (data as Data).write(to: url, options: .atomic)
    }
}
