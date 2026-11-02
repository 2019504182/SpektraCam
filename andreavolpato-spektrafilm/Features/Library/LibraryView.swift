import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    let library: PhotoLibrary
    @Binding var path: [UUID]
    @State private var filter = LibraryFilter.all
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var importSource: ImportSource?
    @State private var picked: [PhotosPickerItem] = []
    @State private var working = false
    @State private var progress = ""
    @State private var failure: String?
    @State private var confirmDelete = false
    @State private var confirmRevert = false
    @State private var showLUTs = false
    @State private var showInformation = false
    @State private var scrollRevision = 0
    private enum ImportSource { case photos, files }
    private var visible: [LibraryPhoto] { library.photos.filter { filter.includes($0) } }
    private var sections: [(day: Date, photos: [LibraryPhoto])] {
        Dictionary(grouping: visible, by: { Calendar.current.startOfDay(for: $0.date) })
            .map { (day: $0.key, photos: $0.value) }.sorted { $0.day < $1.day }
    }
    private func presented(_ source: ImportSource) -> Binding<Bool> {
        Binding(
            get: { importSource == source },
            set: {
                if $0 { importSource = source } else if importSource == source { importSource = nil }
            })
    }
    var body: some View {
        NavigationStack(path: $path) {
            gallery
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Text(
                        selecting
                            ? "\(selection.count) selected"
                            : "\(visible.count) \(visible.count == 1 ? "photo" : "photos")"
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.vertical, 6).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("library.count")
                }
                .sheet(isPresented: $showInformation) { AppInformationView() }
                .sheet(isPresented: $showLUTs) { LUTLibraryView(library: library) }
                .navigationTitle("Library").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        CameraButton()
                    }
                    ToolbarSpacer(.fixed, placement: .topBarLeading)
                    ToolbarItem(placement: .topBarLeading) {
                        Button("About and Settings", systemImage: "info") { showInformation = true }
                            .labelStyle(.iconOnly).buttonBorderShape(.circle)
                            .accessibilityIdentifier("library.info")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Show", selection: $filter) {
                                ForEach(LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
                            }
                        } label: {
                            Label(
                                "Filter",
                                systemImage: filter == .all
                                    ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        }
                        .accessibilityIdentifier("library.filter").disabled(working)
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            selecting.toggle()
                            selection.removeAll()
                        } label: {
                            if selecting { Image(systemName: "xmark") } else { Text("Select") }
                        }
                        .buttonBorderShape(selecting ? .circle : .capsule)
                        .accessibilityLabel(selecting ? "Cancel Selection" : "Select")
                        .accessibilityIdentifier("library.select").disabled(working || visible.isEmpty)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        if selecting {
                            Button("Revert", systemImage: "arrow.uturn.backward") { confirmRevert = true }
                                .accessibilityIdentifier("library.revert")
                                .disabled(
                                    working
                                        || !library.photos.contains {
                                            selection.contains($0.id) && $0.hasEdits
                                        }
                                )
                                .confirmationDialog(
                                    "Revert selected photos?", isPresented: $confirmRevert,
                                    titleVisibility: .visible
                                ) {
                                    Button("Revert to Original", role: .destructive) {
                                        let ids = selection
                                        working = true
                                        Task {
                                            do { try await library.revert(ids) } catch {
                                                failure = error.localizedDescription
                                            }
                                            working = false
                                        }
                                    }
                                } message: {
                                    Text("This removes all edits from the selected app copies.")
                                }
                        } else {
                            Menu {
                                Button("From Photos", systemImage: "photo.on.rectangle") {
                                    picked = library.importedAssetIdentifiers.map {
                                        PhotosPickerItem(itemIdentifier: $0)
                                    }
                                    importSource = .photos
                                }
                                Button("From Files", systemImage: "folder") { importSource = .files }
                            } label: {
                                Label("Import", systemImage: "plus")
                            }
                            .accessibilityIdentifier("library.import").disabled(working)
                        }
                    }
                    ToolbarItem(placement: .bottomBar) { Spacer() }
                    ToolbarItem(placement: .bottomBar) {
                        Button("LUT Manager") { showLUTs = true }
                            .accessibilityIdentifier("library.luts").disabled(working)
                    }
                    ToolbarItem(placement: .bottomBar) { Spacer() }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("library.delete")
                            .disabled(!selecting || selection.isEmpty || working)
                            .confirmationDialog(
                                "Delete \(selection.count) photos?", isPresented: $confirmDelete,
                                titleVisibility: .visible
                            ) {
                                Button("Delete App Copies", role: .destructive) {
                                    let ids = selection
                                    working = true
                                    Task {
                                        do {
                                            try await library.delete(ids)
                                            selection.removeAll()
                                            selecting = false
                                        } catch { failure = error.localizedDescription }
                                        working = false
                                    }
                                }
                            } message: {
                                Text(
                                    "This removes the app copies and their edits. Your source photos stay unchanged."
                                )
                            }
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    PhotoDetailView(library: library, id: id, filter: filter)
                }
                .photosPicker(
                    isPresented: presented(.photos), selection: $picked,
                    matching: .images, preferredItemEncoding: .current, photoLibrary: .shared()
                )
                .fileImporter(
                    isPresented: presented(.files), allowedContentTypes: [.image],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls): Task { await importFiles(urls) }
                    case .failure(let error): failure = error.localizedDescription
                    }
                }
                .onChange(of: picked) { _, photos in
                    guard !photos.isEmpty else { return }
                    Task { await importPhotos(photos) }
                }
                .onChange(of: filter) { _, _ in
                    selection.removeAll()
                    scrollRevision += 1
                }

                .alert(
                    "Library",
                    isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(failure ?? "")
                }
        }
    }
    private var gallery: some View {
        ZStack {
            if visible.isEmpty {
                ContentUnavailableView(
                    filter == .all ? "Your Library" : "No \(filter.rawValue) Photos",
                    systemImage: "photo.on.rectangle",
                    description: Text("Import photos from Photos or Files."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2
                        ) {
                            ForEach(sections, id: \.day) { section in
                                Section {
                                    ForEach(section.photos) { photo in
                                        Button {
                                            if selecting {
                                                if selection.contains(photo.id) {
                                                    selection.remove(photo.id)
                                                } else {
                                                    selection.insert(photo.id)
                                                }
                                            } else {
                                                path.append(photo.id)
                                            }
                                        } label: {
                                            LibraryThumbnail(
                                                photo: photo, images: library.images,
                                                selecting: selecting, selected: selection.contains(photo.id))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(
                                            "\(photo.filename), \(photo.isRAW ? "RAW" : photo.metadata.format), \(photo.date.formatted(date: .abbreviated, time: .shortened))"
                                        )
                                        .accessibilityValue(photo.hasEdits ? "Edited" : "Original")
                                        .accessibilityAddTraits(
                                            selection.contains(photo.id) ? .isSelected : []
                                        )
                                        .accessibilityIdentifier("library.photo.\(photo.id)")
                                    }
                                } header: {
                                    Text(dayTitle(section.day)).font(.headline).frame(
                                        maxWidth: .infinity, alignment: .leading
                                    )
                                    .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 10)
                                }
                            }
                        }
                        Color.clear.frame(height: 2).id("latest")
                    }
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .onChange(of: scrollRevision) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
                    .accessibilityIdentifier("library.grid")
                }
            }
            if working && !progress.isEmpty {
                ImportProgress(text: progress)
            }
        }
        .background(PhotoTheme.canvas)
    }
    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.wide).day().year())
    }
    private func importPhotos(_ incoming: [PhotosPickerItem]) async {
        let known = Set(library.importedAssetIdentifiers)
        let photos = incoming.filter { $0.itemIdentifier.map { !known.contains($0) } ?? true }
        guard !working, !photos.isEmpty else { return }
        working = true
        selecting = false
        selection.removeAll()
        var errors = 0
        for (index, photo) in photos.enumerated() {
            progress = "Importing \(index + 1) of \(photos.count)…"
            do {
                guard let file = try await photo.loadTransferable(type: LibraryImportFile.self) else {
                    throw LibraryFiles.Failure.image
                }
                try await library.importPhoto(file.url, assetIdentifier: photo.itemIdentifier)
            } catch { errors += 1 }
        }
        picked = []
        completeImport(errors)
    }
    private func importFiles(_ urls: [URL]) async {
        guard !working else { return }
        working = true
        selecting = false
        selection.removeAll()
        var errors = 0
        for (index, url) in urls.enumerated() {
            progress = "Importing \(index + 1) of \(urls.count)…"
            let scoped = url.startAccessingSecurityScopedResource()
            do { try await library.importPhoto(url) } catch { errors += 1 }
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        completeImport(errors)
    }
    private func completeImport(_ errors: Int) {
        working = false
        progress = ""
        filter = .all
        scrollRevision += 1
        if errors > 0 { failure = "Couldn’t import \(errors) photos. Check the files and try again." }
    }
}
