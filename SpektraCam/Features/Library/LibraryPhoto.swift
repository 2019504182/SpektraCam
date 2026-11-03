import CryptoKit
import Foundation
import SwiftData

/// Freeze released schemas. Add a new schema and migration for later changes.
nonisolated enum LibrarySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Record.self] }

    @Model final class Record {
        @Attribute(.unique) var id: UUID
        var filename: String
        var fileExtension: String
        var contentHash: String
        var isRAW: Bool
        var importedAt: Date
        var capturedAt: Date?
        var metadataData: Data
        var recipeData: Data?
        var renderKey: String
        var locationName: String?

        init(_ photo: LibraryPhoto) throws {
            id = photo.id
            filename = photo.filename
            fileExtension = photo.fileExtension
            contentHash = photo.contentHash
            isRAW = photo.isRAW
            importedAt = photo.importedAt
            capturedAt = photo.metadata.capturedAt
            metadataData = try JSONEncoder().encode(photo.metadata)
            recipeData = photo.recipeData
            renderKey = photo.renderKey
            locationName = photo.locationName
        }
        func snapshot() throws -> LibraryPhoto {
            LibraryPhoto(
                id: id, filename: filename, fileExtension: fileExtension,
                contentHash: contentHash, isRAW: isRAW, importedAt: importedAt,
                metadata: try JSONDecoder().decode(PhotoMetadata.self, from: metadataData),
                recipeData: recipeData, renderKey: renderKey, locationName: locationName)
        }
    }
}

/// Keep Photos identifiers separate from the immutable original and edit recipe.
nonisolated enum LibrarySchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [LibrarySchemaV1.Record.self, PhotosSource.self]
    }
    @Model final class PhotosSource {
        @Attribute(.unique) var assetIdentifier: String
        var photoID: UUID
        init(assetIdentifier: String, photoID: UUID) {
            self.assetIdentifier = assetIdentifier
            self.photoID = photoID
        }
    }
}

nonisolated enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self, LibrarySchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self)]
    }
}

/// Send value snapshots to views and file workers, not live database records.
nonisolated struct LibraryPhoto: Identifiable, Equatable, Sendable {
    let id: UUID
    let filename: String
    let fileExtension: String
    let contentHash: String
    let isRAW: Bool
    let importedAt: Date
    let metadata: PhotoMetadata
    var recipeData: Data? = nil
    var renderKey = "original"
    var locationName: String? = nil
    var date: Date { metadata.capturedAt ?? importedAt }
    var hasEdits: Bool { recipeData != nil }
    static func recipeData(_ recipe: EditRecipe) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(recipe)
    }
    static func key(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case raw = "RAW"
    case rendered = "Rendered"
    var title: String {
        switch self {
        case .all: String(localized: "library.filter.all", defaultValue: "All")
        case .raw: "RAW"
        case .rendered: String(localized: "library.filter.rendered", defaultValue: "Rendered")
        }
    }
    var id: Self { self }
    func includes(_ photo: LibraryPhoto) -> Bool {
        self == .all || (self == .raw ? photo.isRAW : !photo.isRAW)
    }
}
