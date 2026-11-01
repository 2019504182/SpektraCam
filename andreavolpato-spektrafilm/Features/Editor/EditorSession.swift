import CoreGraphics
import OSLog
import Observation
import SwiftUI

/// One source, one recipe, and bounded recipe history; never copies source bytes for undo.
@Observable final class EditorSession: Identifiable, Hashable {
    let id = UUID()
    let photo: ImportedPhoto
    var recipe: EditRecipe
    var geometryImage: UIImage
    var histogram = PhotoHistogram.empty
    var originalHistogram = PhotoHistogram.empty
    @ObservationIgnored private var filmHistogram = PhotoHistogram.empty
    var displayImage: UIImage
    var isRendering = false
    var renderFailed = false
    var isProcessingFilm = false
    var filmRenderFailed = false
    @ObservationIgnored private var failureTask: Task<Void, Never>?
    @ObservationIgnored private static let logger = Logger(
        subsystem: "io.github.runzeni.andreavolpato-spektrafilm", category: "Rendering")
    var hasFilmPreview = false
    var isBusy: Bool { isRendering || isProcessingFilm }
    @ObservationIgnored private let filmRenderer: PhotoRenderer
    @ObservationIgnored private var filmSource: CGImage
    @ObservationIgnored private var renderedSource: CGImage
    @ObservationIgnored private var filmTask: Task<Void, Never>?
    @ObservationIgnored private var filmRevision: UInt64 = 0
    @ObservationIgnored private var filmEpoch = UUID()
    @ObservationIgnored private var renderedFilmRecipe: EditRecipe?
    private var renderedGeometry = ImageGeometry()
    private var renderedCrop = CropSelection.fullImage
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var renderRevision: UInt64 = 0
    @ObservationIgnored private var renderEpoch = UUID()
    private var undoStack: [EditRecipe] = []
    private var redoStack: [EditRecipe] = []
    private var lastChange = Date.distantPast
    private var lastKey = ""
    @ObservationIgnored private var interactionKey: String?

    @ObservationIgnored var recipeDidChange: ((EditRecipe, Bool) -> Void)?

    init(photo: ImportedPhoto, recipe restored: EditRecipe? = nil) {
        self.photo = photo
        filmSource = photo.preview
        renderedSource = photo.preview
        filmRenderer = PhotoRenderer(
            source: photo.preview, directory: Bundle.main.resourceURL!, data: photo.data,
            temperature: photo.rawTemperature)
        var initial = restored ?? EditRecipe()
        if initial.temperature == nil { initial.temperature = photo.rawTemperature }
        recipe = initial
        let initialPreview = UIImage(cgImage: photo.preview)
        geometryImage = initialPreview
        displayImage = initialPreview
    }
    static func == (lhs: EditorSession, rhs: EditorSession) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasEdits: Bool {
        var initial = EditRecipe()
        initial.temperature = photo.rawTemperature
        return recipe != initial
    }
    func binding<Value>(_ keyPath: WritableKeyPath<EditRecipe, Value>, key: String) -> Binding<Value> {
        Binding(
            get: { self.recipe[keyPath: keyPath] },
            set: { value in
                self.update(key: key) { $0[keyPath: keyPath] = value }
            })
    }
    func setInteraction(key: String, active: Bool) {
        if active {
            failureTask?.cancel()
            filmRenderFailed = false
            interactionKey = key
            lastKey = ""
        } else if interactionKey == key {
            interactionKey = nil
            lastKey = ""
            renderFilmIfNeeded()
            recipeDidChange?(recipe, true)
        }
    }
    func update(key: String, _ change: (inout EditRecipe) -> Void) {
        var next = recipe
        change(&next)
        next.removeDefaultOverrides()
        guard next != recipe else { return }
        let now = Date()
        if lastKey != key || (interactionKey != key && now.timeIntervalSince(lastChange) > 0.4) {
            undoStack.append(recipe)
            if undoStack.count > 100 { undoStack.removeFirst() }
        }
        redoStack.removeAll()
        lastKey = key
        lastChange = now
        let oldGeometry = recipe.geometry
        let oldRect = recipe.crop.normalizedRect
        let changedFilm = recipe.processingRecipe != next.processingRecipe
        recipe = next
        recipeDidChange?(recipe, false)
        if changedFilm { renderFilm() }
        if oldGeometry != next.geometry || oldRect != next.crop.normalizedRect { renderGeometry() }
    }
    func selectFilm(_ stock: FilmStock) {
        update(key: "film") { $0.selectFilm(stock) }
    }
    func resetGrain() {
        update(key: "grain.reset") { recipe in
            recipe.monochromeGrain = false
            recipe.numbers = recipe.numbers.filter { !$0.key.hasPrefix("film_render.grain.") }
            recipe.flags = recipe.flags.filter { !$0.key.hasPrefix("film_render.grain.") }
        }
    }
    func export(size: PhotoExporter.Size, format: PhotoExporter.Format, quality: Double) async throws -> (
        URL, Int, Int
    ) {
        let snapshot = recipe
        await filmTask?.value
        try Task.checkCancellation()
        return try await filmRenderer.export(snapshot, size: size, format: format, quality: quality)
    }
    /// Cache only a frame which matches the recipe that is being saved.
    func currentPreview() async -> CGImage? {
        await filmTask?.value
        await renderTask?.value
        guard renderedFilmRecipe == recipe.processingRecipe,
            renderedGeometry == recipe.geometry, renderedCrop == recipe.crop.normalizedRect,
            renderedSource === filmSource
        else { return nil }
        return displayImage.cgImage
    }
    func discardExport() { Task { await filmRenderer.discardExport() } }
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(recipe)
        recipe = previous
        recipeDidChange?(recipe, true)
        lastKey = ""
        renderFilmIfNeeded()
        renderGeometry()
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(recipe)
        recipe = next
        recipeDidChange?(recipe, true)
        lastKey = ""
        renderFilmIfNeeded()
        renderGeometry()
    }
    /// One render in flight and one latest desired state. Completed frames remain visible
    /// during a drag; a continuous stream of slider events never postpones rendering.
    func renderGeometry() {
        renderRevision &+= 1
        let geometry = recipe.geometry
        let crop = recipe.crop
        if geometry.isIdentity && crop.normalizedRect == CropSelection.fullImage {
            renderTask?.cancel()
            renderTask = nil
            renderEpoch = UUID()
            if !renderedGeometry.isIdentity || renderedSource !== filmSource {
                geometryImage = UIImage(cgImage: filmSource)
            }
            renderedSource = filmSource
            histogram = filmHistogram
            displayImage = geometryImage
            renderedGeometry = geometry
            renderedCrop = crop.normalizedRect
            isRendering = false
            renderFailed = false
            return
        }
        isRendering = geometry != renderedGeometry || renderedSource !== filmSource
        renderFailed = false
        guard renderTask == nil else { return }
        let epoch = UUID()
        renderEpoch = epoch
        renderTask = Task {
            while !Task.isCancelled {
                let source = filmSource
                let revision = renderRevision
                let geometry = recipe.geometry
                let crop = recipe.crop
                let frame = await GeometryWorker.shared.render(source, geometry: geometry, crop: crop)
                guard !Task.isCancelled, renderEpoch == epoch else { return }
                guard let frame else {
                    if revision != renderRevision { continue }
                    renderFailed = true
                    isRendering = false
                    renderTask = nil
                    return
                }
                if renderedGeometry != geometry || renderedSource !== source {
                    geometryImage = UIImage(cgImage: frame.geometry)
                }
                displayImage = UIImage(cgImage: frame.display)
                histogram = frame.histogram
                renderedSource = source
                renderedGeometry = geometry
                renderedCrop = crop.normalizedRect
                isRendering = recipe.geometry != geometry || renderedSource !== filmSource
                if revision == renderRevision {
                    renderTask = nil
                    return
                }
                await Task.yield()
            }
        }
    }

    func resumeRendering() {
        let source = photo.preview
        Task { originalHistogram = await HistogramWorker.shared.make(source) }
        renderFilmIfNeeded()
        if renderedSource !== filmSource || recipe.geometry != renderedGeometry
            || recipe.crop.normalizedRect != renderedCrop
        {
            renderGeometry()
        }
    }
    private func renderFilmIfNeeded() {
        if filmTask != nil || renderedFilmRecipe != recipe.processingRecipe {
            renderFilm()
        } else {
            filmRevision &+= 1
            failureTask?.cancel()
            filmRenderFailed = false
        }
    }

    /// Keep one active GPU frame and the latest desired recipe, without debouncing a continuous drag.
    func renderFilm() {
        filmRevision &+= 1
        failureTask?.cancel()
        filmRenderFailed = false
        isProcessingFilm = true
        guard filmTask == nil else { return }
        let epoch = UUID()
        filmEpoch = epoch
        filmTask = Task {
            while !Task.isCancelled {
                let revision = filmRevision
                let requested = recipe.processingRecipe
                do {
                    let image = try await filmRenderer.render(requested)
                    let stats = await HistogramWorker.shared.make(image)
                    guard !Task.isCancelled, filmEpoch == epoch else { return }
                    filmSource = image
                    filmHistogram = stats
                    renderedFilmRecipe = requested
                    hasFilmPreview = true
                    renderGeometry()
                } catch {
                    guard !Task.isCancelled, filmEpoch == epoch else { return }
                    if revision != filmRevision { continue }
                    Self.logger.error(
                        "Preview failed: \(String(describing: error), privacy: .public), film \(requested.filmID, privacy: .public)"
                    )
                    if interactionKey == nil {
                        failureTask = Task {
                            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                            guard !Task.isCancelled, filmEpoch == epoch, filmRevision == revision else {
                                return
                            }
                            filmRenderFailed = true
                        }
                    }
                }
                if revision == filmRevision {
                    filmTask = nil
                    isProcessingFilm = false
                    return
                }
                await Task.yield()
            }
        }
    }

    func cancelRendering() {
        failureTask?.cancel()
        filmTask?.cancel()
        filmTask = nil
        filmEpoch = UUID()
        isProcessingFilm = false
        renderTask?.cancel()
        renderTask = nil
        renderEpoch = UUID()
        isRendering = false
        let source = filmSource
        Task { await GeometryWorker.shared.discard(source) }
    }
}

/// One active render; cancelled queued requests are skipped. A crop never reruns rotation.
private actor GeometryWorker {
    struct Frame: Sendable { let geometry: CGImage, display: CGImage, histogram: PhotoHistogram }
    static let shared = GeometryWorker()
    private var cachedSource: CGImage?
    private var cachedGeometry: ImageGeometry?
    private var cachedImage: CGImage?

    func render(_ source: CGImage, geometry: ImageGeometry, crop: CropSelection) -> Frame? {
        guard !Task.isCancelled else { return nil }
        let image: CGImage
        if cachedSource === source, cachedGeometry == geometry, let cachedImage {
            image = cachedImage
        } else {
            guard let rendered = GeometryRenderer.render(source, geometry: geometry) else { return nil }
            image = rendered
            cachedSource = source
            cachedGeometry = geometry
            cachedImage = image
        }
        guard !Task.isCancelled else { return nil }
        if crop.normalizedRect == CropSelection.fullImage {
            return Frame(geometry: image, display: image, histogram: PhotoHistogram.make(image))
        }
        guard
            let display = image.cropping(
                to: crop.pixelRect(in: CGSize(width: image.width, height: image.height)))
        else { return nil }
        return Frame(geometry: image, display: display, histogram: PhotoHistogram.make(display))
    }
    func discard(_ source: CGImage) {
        guard cachedSource === source else { return }
        cachedSource = nil
        cachedGeometry = nil
        cachedImage = nil
    }
}
