import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

@main struct Checks {
    @MainActor static func main() async throws {
        let project = URL(fileURLWithPath: CommandLine.arguments[1])
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SpektraCam-Library-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("Library")
        let cache = temporary.appendingPathComponent("Caches")
        let source = temporary.appendingPathComponent("fixture.jpg")
        let context = CGContext(
            data: nil, width: 24, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 32))
        let destination = CGImageDestinationCreateWithURL(
            source as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(
            destination, context.makeImage()!,
            [
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifDateTimeOriginal: "2020:06:15 12:34:56",
                    kCGImagePropertyExifOffsetTimeOriginal: "+02:00",
                ],
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 37.7, kCGImagePropertyGPSLatitudeRef: "N",
                    kCGImagePropertyGPSLongitude: 122.4, kCGImagePropertyGPSLongitudeRef: "W",
                ],
            ] as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        let originalBytes = try Data(contentsOf: source)
        let dataDirectory = project.appendingPathComponent("andreavolpato-spektrafilm/Resources/ModelData")
        var library: PhotoLibrary? = try PhotoLibrary(root: root, cache: cache, modelDirectory: dataDirectory)
        precondition(library!.photos.isEmpty)
        let photo = try await library!.importPhoto(source, assetIdentifier: "fixture")
        precondition(!photo.isRAW && photo.metadata.width == 24 && photo.metadata.height == 32)
        precondition(photo.metadata.capturedAt == ISO8601DateFormatter().date(from: "2020-06-15T10:34:56Z"))
        precondition(photo.metadata.latitude == 37.7 && photo.metadata.longitude == -122.4)
        let copied = try Data(contentsOf: library!.files.sourceURL(photo))
        precondition(copied == originalBytes, "Import changed original bytes")
        let originalExporter = OriginalPhotoExporter(source: source)
        let unedited = try await originalExporter.export(size: .small, format: .png, quality: 1)
        let exported = try PhotoExporter.decodeSource(Data(contentsOf: unedited.0))
        let expected = try PhotoExporter.renderOriginal(
            originalBytes, crop: CropSelection(), geometry: ImageGeometry())
        func pixel(_ image: CGImage) -> [UInt8] {
            let sample = CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            sample.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return Array(
                UnsafeBufferPointer(start: sample.data!.assumingMemoryBound(to: UInt8.self), count: 4))
        }
        precondition(
            zip(pixel(expected), pixel(exported)).allSatisfy { abs(Int($0) - Int($1)) <= 1 },
            "Untouched export applied a look")
        await originalExporter.discard()
        var recipe = EditRecipe()
        recipe.source.exposureEV = 1.25
        recipe.mix = 0.6
        recipe.tone.contrast = 1.2
        recipe.monochromeGrain = true
        try await library!.finishEditing(photo.id, recipe: recipe, preview: nil)
        let duplicate = try await library!.importPhoto(source, assetIdentifier: "alias")
        precondition(duplicate.id == photo.id && library!.photos.count == 1)
        let preserved = try library!.recipe(photo.id)
        precondition(preserved == recipe, "Duplicate import reset edits")
        let edited = library!.photo(photo.id)!
        let rendered = try await library!.images.image(edited, thumbnail: false)
        precondition(rendered.width == 24 && rendered.height == 32)
        library = nil
        library = try PhotoLibrary(root: root, cache: cache, modelDirectory: dataDirectory)
        precondition(library!.photos.count == 1)
        precondition(
            library!.importedAssetIdentifiers == ["alias", "fixture"],
            "Photos identifiers did not survive restart")
        // Simulate termination between staging a delete and committing it to the index.
        _ = try await library!.files.stageRemoval(library!.photo(photo.id)!)
        library = nil
        library = try PhotoLibrary(root: root, cache: cache, modelDirectory: dataDirectory)
        precondition(
            FileManager.default.fileExists(atPath: library!.files.sourceURL(photo).path),
            "Interrupted delete lost the original")
        let restored = try library!.recipe(photo.id)
        precondition(restored == recipe, "Restart lost edits")
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let rebuilt = try await library!.images.image(library!.photo(photo.id)!, thumbnail: false)
        precondition(rebuilt.width == rendered.width && rebuilt.height == rendered.height)
        // Real local sources use the same importer. They stay outside the app store.
        for path in CommandLine.arguments.dropFirst(2) {
            let url = URL(fileURLWithPath: path)
            let bytes = try Data(contentsOf: url)
            let imported = try await library!.importPhoto(url)
            let raw = path.lowercased().hasSuffix(".dng")
            precondition(imported.isRAW == raw)
            precondition(LibraryFilter.raw.includes(imported) == raw)
            let copy = try Data(contentsOf: library!.files.sourceURL(imported))
            precondition(copy == bytes)
            try await library!.delete([imported.id])
            let after = try Data(contentsOf: url)
            precondition(after == bytes)
            print("PASS: library import, type filter and source preservation: \(url.lastPathComponent)")
        }
        let fallback = temporary.appendingPathComponent("fallback.png")
        let png = CGImageDestinationCreateWithURL(
            fallback as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(png, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(png))
        let fallbackDate = Date(timeIntervalSince1970: 1_700_000_000)
        let noDate = try await library!.importPhoto(fallback, now: fallbackDate)
        precondition(noDate.metadata.capturedAt == nil && noDate.date == fallbackDate)
        precondition(library!.photos.first?.id == photo.id && library!.photos.last?.id == noDate.id)
        try await library!.delete([noDate.id])
        try await library!.delete([photo.id])
        precondition(library!.photos.isEmpty)
        let outsideBytes = try Data(contentsOf: source)
        precondition(outsideBytes == originalBytes, "Delete changed the external original")
        library = nil
        let final = try PhotoLibrary(root: root, cache: cache, modelDirectory: dataDirectory)
        precondition(final.photos.isEmpty, "Deleted photo returned after restart")
        precondition(final.importedAssetIdentifiers.isEmpty, "Deleted photo stayed preselected")
        let legacyRoot = temporary.appendingPathComponent("Legacy")
        let legacyCache = temporary.appendingPathComponent("LegacyCache")
        let legacy = try await makeLegacyStore(
            root: legacyRoot, cache: legacyCache, source: source, recipe: recipe)
        let migrated = try PhotoLibrary(root: legacyRoot, cache: legacyCache, modelDirectory: dataDirectory)
        let recovered = try migrated.recipe(legacy.id)
        precondition(
            migrated.photos.count == 1 && recovered == recipe, "Version 1 migration lost a photo or recipe")
        let migratedBytes = try Data(contentsOf: migrated.files.sourceURL(legacy))
        precondition(migratedBytes == originalBytes)
        let linked = try await migrated.importPhoto(source, assetIdentifier: "legacy-source")
        precondition(linked.id == legacy.id && migrated.importedAssetIdentifiers == ["legacy-source"])
        print("PASS: version 1 migration, Photos source links, duplicate linking and deletion cleanup")
        print(
            "PASS: import bytes, capture date/GPS, RAW classification, duplicate preservation, recipe restart, interrupted-delete recovery, cache rebuild, date fallback, original export and app-only deletion"
        )
    }
    @MainActor private static func makeLegacyStore(root: URL, cache: URL, source: URL, recipe: EditRecipe)
        async throws -> LibraryPhoto
    {
        let files = try LibraryFiles(root: root, cache: cache, validIDs: [])
        let photo = try await files.importPhoto(from: source)
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let config = ModelConfiguration(
            "Library", schema: schema, url: root.appendingPathComponent("Library.store"),
            cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let record = try LibrarySchemaV1.Record(photo)
        record.recipeData = try LibraryPhoto.recipeData(recipe)
        record.renderKey = LibraryPhoto.key(record.recipeData!)
        context.insert(record)
        try context.save()
        return photo
    }

}
