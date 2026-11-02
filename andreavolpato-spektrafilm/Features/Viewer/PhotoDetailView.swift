import MapKit
import SwiftUI

/// Browse the album without loading full-resolution data for each thumbnail.
struct PhotoDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let library: PhotoLibrary
    let filter: LibraryFilter
    @State private var selectedID: UUID
    @State private var sourceLens: String?
    private var displayMetadata: PhotoMetadata {
        var result = photo?.metadata ?? PhotoMetadata()
        if result.lens == nil { result.lens = sourceLens }
        return result
    }
    @State private var histogram = PhotoHistogram.empty
    @State private var image: UIImage?
    @State private var editor: EditorSession?
    @State private var export: ExportRequest?
    @State private var working = false
    @State private var failure: String?
    private struct ExportRequest: Identifiable {
        let id = UUID()
        let session: EditorSession?
        let originalURL: URL
    }
    private var photo: LibraryPhoto? { library.photo(selectedID) }
    private var photos: [LibraryPhoto] { library.photos.filter { filter.includes($0) } }

    init(library: PhotoLibrary, id: UUID, filter: LibraryFilter = .all) {
        self.library = library
        self.filter = filter
        _selectedID = State(initialValue: id)
    }
    var body: some View {
        ZStack {
            AlbumPager(photos: photos, images: library.images, selection: $selectedID)
            if working { ProgressView().padding().background(.regularMaterial, in: .capsule) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PhotoTheme.canvas)
        .overlay(alignment: .bottom) {
            PhotoViewerControls(
                photos: photos, images: library.images, selection: $selectedID,
                working: working, develop: { prepareEditor(exporting: false) },
                export: { prepareEditor(exporting: true) }, revert: revertPhoto,
                canRevert: photo?.hasEdits == true, delete: deletePhoto
            )
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .overlay(alignment: .top) {
            if let photo {
                PhotoInfoPanel(
                    title: filmTitle, subtitle: printTitle, metadata: displayMetadata,
                    location: photo.locationName, histogram: histogram, identifier: "photo"
                )
                .padding(.horizontal, 12).padding(.top, 4)
            }
        }
        .navigationTitle("Photo").navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.navigationStack)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let photo { PhotoBanner(photo: photo) }
            }
            ToolbarItem(placement: .topBarTrailing) { CameraButton() }
        }
        .task(id: "\(selectedID)-\(photo?.renderKey ?? "")") { await loadPreview() }
        .task(id: selectedID) {
            sourceLens = nil
            if let photo {
                let lens = await library.files.lensName(photo)
                guard !Task.isCancelled, photo.id == selectedID else { return }
                sourceLens = lens
            }
            await resolveLocation()
        }
        .onChange(of: selectedID) { _, _ in
            image = nil
            histogram = .empty
        }
        .navigationDestination(item: $editor) { session in
            EditorView(session: session, locationName: photo?.locationName, library: library) {
                let recipe = session.recipe
                let preview = await session.currentPreview()
                try await library.finishEditing(selectedID, recipe: recipe, preview: preview)
            }
        }
        .sheet(item: $export) { request in
            if let session = request.session {
                ExportPanel(session: session)
            } else {
                ExportPanel(originalURL: request.originalURL)
            }
        }
        .alert(
            "Photo",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }
    private var savedRecipe: EditRecipe? {
        photo?.recipeData.flatMap { try? JSONDecoder().decode(EditRecipe.self, from: $0) }
    }
    private var filmTitle: String {
        guard let recipe = savedRecipe else { return "Original" }
        if recipe.look.mode == .lut { return "3D LUT" }
        return FilmStock.films.first { $0.id == recipe.filmID }?.name ?? "Film"
    }
    private var printTitle: String {
        guard let recipe = savedRecipe else {
            return photo?.isRAW == true ? "RAW" : photo?.metadata.format ?? "Photo"
        }
        if recipe.look.mode == .lut {
            let names = [recipe.look.first.id, recipe.look.second.id].compactMap {
                library.luts.name($0)
            }
            return names.isEmpty ? "No LUT selected" : names.joined(separator: " · ")
        }
        return recipe.bypassesPrint
            ? "Direct scan" : FilmStock.prints.first { $0.id == recipe.printID }?.name ?? "Print"
    }
    private func loadPreview() async {
        guard let photo else { return }
        do {
            let frame = try await library.images.image(photo, thumbnail: false)
            try Task.checkCancellation()
            image = UIImage(cgImage: frame)
            let stats = await HistogramWorker.shared.make(frame)
            if !Task.isCancelled { histogram = stats }
        } catch { if !Task.isCancelled { histogram = .empty } }
    }
    private func revertPhoto() {
        working = true
        Task {
            defer { working = false }
            do { try await library.revert([selectedID]) } catch {
                failure = error.localizedDescription
            }
        }
    }
    private func deletePhoto() {
        guard !working else { return }
        let id = selectedID
        let album = photos.map(\.id)
        let index = album.firstIndex(of: id) ?? 0
        let next = album.dropFirst(index + 1).first ?? album.prefix(index).last
        working = true
        Task {
            defer { working = false }
            do {
                try await library.delete([id])
                if let next { selectedID = next } else { dismiss() }
            } catch { failure = error.localizedDescription }
        }
    }
    private func prepareEditor(exporting: Bool) {
        guard !working, let photo else { return }
        do {
            let recipe = try library.recipe(photo.id)
            if exporting && recipe == nil {
                export = ExportRequest(session: nil, originalURL: library.files.sourceURL(photo))
                return
            }
            if let recipe, recipe.upstreamRevision != EditRecipe().upstreamRevision {
                throw LibraryFiles.Failure.image
            }
            working = true
            Task {
                defer { working = false }
                do {
                    let imported = try await library.files.decodedPhoto(photo)
                    let session = EditorSession(photo: imported, recipe: recipe, luts: library.luts)
                    if let image, photo.hasEdits { session.displayImage = image }
                    if exporting {
                        export = ExportRequest(
                            session: session, originalURL: library.files.sourceURL(photo))
                    } else {
                        session.recipeDidChange = { recipe, immediate in
                            library.queueRecipe(recipe, for: photo.id, immediate: immediate)
                        }
                        editor = session
                    }
                } catch { failure = error.localizedDescription }
            }
        } catch { failure = error.localizedDescription }
    }
    private func resolveLocation() async {
        guard let photo, photo.locationName == nil,
            let latitude = photo.metadata.latitude, let longitude = photo.metadata.longitude,
            let request = MKReverseGeocodingRequest(
                location: CLLocation(latitude: latitude, longitude: longitude))
        else { return }
        do {
            let items = try await withTaskCancellationHandler {
                try await request.mapItems
            } onCancel: {
                request.cancel()
            }
            try Task.checkCancellation()
            if let item = items.first,
                let name = item.addressRepresentations?.cityWithContext ?? item.name
            {
                try library.setLocationName(name, for: photo.id)
            }
        } catch { /* Keep the capture date when the optional lookup is unavailable. */  }
    }
}

/// Capture details stay visible without opening the information panel.
private struct PhotoBanner: View {
    let photo: LibraryPhoto
    private var title: String {
        photo.locationName ?? photo.date.formatted(date: .long, time: .omitted)
    }
    private var detail: String {
        photo.date.formatted(
            date: photo.locationName == nil ? .omitted : .abbreviated, time: .shortened)
    }
    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).accessibilityIdentifier(
                "photo.banner.title")
            HStack(spacing: 5) {
                Text(detail).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier(
                    "photo.banner.date")
                if photo.isRAW { PhotoBadge(text: "RAW", compact: true) }
                if photo.hasEdits { PhotoBadge(symbol: PhotoBadge.editedSymbol, compact: true) }
            }
        }.lineLimit(1).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// Controls float over the image. Native popovers anchor to their source button.
private struct PhotoViewerControls: View {
    let photos: [LibraryPhoto]
    let images: LibraryImages
    @Binding var selection: UUID
    let working: Bool
    let develop: () -> Void
    let export: () -> Void
    let revert: () -> Void
    let canRevert: Bool
    let delete: () -> Void
    @State private var confirmRevert = false
    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        HStack {
                            exportButton
                            Spacer(minLength: 0)
                        }.frame(width: 104)
                        developButton
                        trailingButtons.frame(width: 104)
                    }
                    VStack(spacing: 10) {
                        developButton
                        HStack {
                            exportButton
                            Spacer()
                            trailingButtons
                        }
                    }
                }.controlSize(.large)
                PhotoFilmstrip(photos: photos, images: images, selection: $selection)
            }
        }.disabled(working)
    }
    private var trailingButtons: some View {
        HStack(spacing: 8) {
            Button {
                confirmRevert = true
            } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 28, height: 28)
            }
            .accessibilityLabel("Revert").controlSize(.regular).buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!canRevert).accessibilityIdentifier("photo.revert")
            .confirmationDialog(
                "Revert to original?", isPresented: $confirmRevert, titleVisibility: .visible
            ) {
                Button("Revert to Original", role: .destructive, action: revert)
            }
            deleteButton
        }
    }
    private var developButton: some View {
        Button(action: develop) {
            Text("Develop").font(.headline).lineLimit(1).fixedSize(
                horizontal: true, vertical: false
            )
            .padding(.horizontal, 24)
        }.buttonStyle(.glassProminent).accessibilityIdentifier("photo.develop")
    }
    private var exportButton: some View {
        Button(action: export) {
            Image(systemName: "square.and.arrow.up").frame(width: 28, height: 28)
        }
        .accessibilityLabel("Export").controlSize(.regular).buttonStyle(.glass).buttonBorderShape(
            .circle
        ).accessibilityIdentifier(
            "photo.export")
    }
    private var deleteButton: some View { PhotoDeleteButton(action: delete) }
}

private struct PhotoDeleteButton: View {
    let action: () -> Void
    @State private var confirmDelete = false
    var body: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Image(systemName: "trash").frame(width: 28, height: 28)
        }
        .accessibilityLabel("Delete").controlSize(.regular).buttonStyle(.glass).buttonBorderShape(
            .circle
        ).accessibilityIdentifier(
            "photo.delete"
        )
        .confirmationDialog("Delete Photo?", isPresented: $confirmDelete, titleVisibility: .visible)
        {
            Button("Delete App Copy", role: .destructive, action: action)
        } message: {
            Text("This removes the app copy and its edits. Your source photo stays unchanged.")
        }
    }
}

/// Each page loads a cached preview; full originals stay outside the paging view.
struct AlbumPhotoPage: View {
    let photo: LibraryPhoto
    let images: LibraryImages
    @State private var image: UIImage?
    @State private var failure: String?
    @State private var retry = 0
    var body: some View {
        Group {
            if let image {
                PhotoViewport(image: image, topInset: 0, edited: photo.hasEdits, topAligned: false)
            } else if let failure {
                ContentUnavailableView {
                    Label("Couldn’t show photo", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Retry") { retry += 1 }
                }
            } else {
                ProgressView("Loading photo…")
            }
        }
        .task(id: "\(photo.renderKey)-\(retry)") {
            do {
                let frame = try await images.image(photo, thumbnail: false)
                try Task.checkCancellation()
                image = UIImage(cgImage: frame)
                failure = nil
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
    }
}
