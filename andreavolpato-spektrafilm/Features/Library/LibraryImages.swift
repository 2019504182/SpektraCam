import CoreGraphics
import Foundation

/// Keep disk reads and image work off the UI actor. Rebuild missing edited caches in order.
actor LibraryImages {
    let files: LibraryFiles
    private let directory: URL
    private let memory = NSCache<NSString, CGImage>()
    private var tail: Task<CGImage, Error>?
    private let resources: FilmRenderResources

    init(files: LibraryFiles, directory: URL) {
        self.files = files
        self.directory = directory
        resources = FilmRenderResources(directory: directory)
        memory.totalCostLimit = 32 * 1024 * 1024
    }
    func image(_ photo: LibraryPhoto, thumbnail: Bool) async throws -> CGImage {
        let key = "\(photo.id)-\(photo.renderKey)-\(thumbnail)" as NSString
        if let image = memory.object(forKey: key) { return image }
        if let image = await files.cachedImage(photo, thumbnail: thumbnail) {
            memory.setObject(image, forKey: key, cost: image.width * image.height * 4)
            return image
        }
        let image: CGImage
        if !photo.hasEdits {
            image = try await files.originalImage(photo, thumbnail: thumbnail)
        } else {
            let previous = tail
            let job = Task {
                if let previous { _ = await previous.result }
                try Task.checkCancellation()
                return try await self.rebuild(photo, thumbnail: thumbnail)
            }
            tail = job
            let preview = try await withTaskCancellationHandler {
                try await job.value
            } onCancel: {
                job.cancel()
            }
            image = preview
        }
        try Task.checkCancellation()
        memory.setObject(image, forKey: key, cost: image.width * image.height * 4)
        return image
    }
    private func rebuild(_ photo: LibraryPhoto, thumbnail: Bool) async throws -> CGImage {
        if let cached = await files.cachedImage(photo, thumbnail: thumbnail) { return cached }
        if thumbnail, let preview = await files.cachedImage(photo, thumbnail: false) {
            return try await files.storeThumbnail(preview, photo: photo)
        }
        guard let data = photo.recipeData else {
            return try await files.originalImage(photo, thumbnail: thumbnail)
        }
        let recipe = try JSONDecoder().decode(EditRecipe.self, from: data)
        guard recipe.upstreamRevision == EditRecipe().upstreamRevision else {
            throw LibraryFiles.Failure.image
        }
        // Keep enough source pixels for a crop, up to the normal editor preview limit.
        let span = min(recipe.crop.normalizedRect.width, recipe.crop.normalizedRect.height)
        let thumbnailLimit = ImportedPhoto.thumbnailMaximumPixelSize
        let previewLimit = ImportedPhoto.previewMaximumPixelSize
        let maximum =
            thumbnail
            ? min(previewLimit, max(thumbnailLimit, Int(ceil(CGFloat(thumbnailLimit) / max(span, 1e-6)))))
            : previewLimit
        let original = try await files.decodedPhoto(photo, maximum: maximum)
        let renderer = PhotoRenderer(
            source: original.preview, directory: directory,
            data: original.data, temperature: original.rawTemperature,
            lutDirectory: files.root.appendingPathComponent("LUTs"), previewMaximum: maximum,
            resources: resources)
        let film = try await renderer.render(recipe)
        try Task.checkCancellation()
        guard let geometry = GeometryRenderer.render(film, geometry: recipe.geometry),
            let cropped = geometry.cropping(
                to: recipe.crop.pixelRect(in: CGSize(width: geometry.width, height: geometry.height)))
        else { throw LibraryFiles.Failure.image }
        if thumbnail { return try await files.storeThumbnail(cropped, photo: photo) }
        try await files.storePreview(cropped, photo: photo)
        return cropped
    }
    func store(_ image: CGImage, photo: LibraryPhoto) async throws {
        try await files.storePreview(image, photo: photo)
        memory.removeAllObjects()
    }
    func discardMemory() {
        memory.removeAllObjects()
    }
}
