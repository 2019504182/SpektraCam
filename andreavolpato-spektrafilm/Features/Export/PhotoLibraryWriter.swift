import Foundation
import Photos

nonisolated enum PhotoLibraryWriter {
    enum Failure: LocalizedError {
        case permission
        var errorDescription: String? { "Allow adding photos in Settings to save this image." }
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
