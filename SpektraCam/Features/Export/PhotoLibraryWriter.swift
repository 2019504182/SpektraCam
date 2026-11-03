import Foundation
import Photos

nonisolated enum PhotoLibraryWriter {
    enum Failure: LocalizedError {
        case permission
        var errorDescription: String? {
            String(
                localized: "photo_library_writer.allow_adding_photos_in_settings_to_save",
                defaultValue: "Allow adding photos in Settings to save this image.")
        }
    }
    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.permission }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: url, options: nil)
        }
    }
}
