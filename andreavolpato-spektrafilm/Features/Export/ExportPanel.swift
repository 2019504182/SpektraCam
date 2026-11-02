import SwiftUI

struct ExportPanel: View {
    private let session: EditorSession?
    @State private var original: OriginalPhotoExporter?
    init(session: EditorSession) {
        self.session = session
        _original = State(initialValue: nil)
    }
    init(originalURL: URL) {
        session = nil
        _original = State(initialValue: OriginalPhotoExporter(source: originalURL))
    }
    @Environment(\.dismiss) private var dismiss
    @State private var format = PhotoExporter.Format.jpeg
    @State private var size = PhotoExporter.Size.full
    @State private var quality = 1.0
    @State private var detent = PresentationDetent.fraction(0.68)
    @State private var sourceDimensions = ""
    @State private var retry = 0
    @State private var url: URL?
    @State private var dimensions = ""
    @State private var failure: String?
    @State private var canOvercommit = false
    @State private var confirmOvercommit = false
    @State private var overcommitKey: String?
    private var settingsKey: String { "\(size.rawValue)-\(format.rawValue)-\(quality)" }
    @State private var saving = false
    @State private var saved = false
    @State private var saveFailure: String?
    @State private var renderTask: Task<(URL, Int, Int), Error>?
    private struct Request: Hashable {
        let format: String, size: String, quality: Double, retry: Int, overcommit: Bool
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Size", selection: $size) {
                        ForEach(PhotoExporter.Size.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(
                        size.maximum.map { "Maximum long edge · \($0) px" }
                            ?? (sourceDimensions.isEmpty
                                ? "Original resolution, with crop applied"
                                : "Original: " + sourceDimensions + " px, with crop applied")
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Picker("Format", selection: $format) {
                        ForEach(PhotoExporter.Format.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if format == .jpeg {
                        Picker("JPEG quality", selection: $quality) {
                            Text("Maximum").tag(1.0)
                            Text("High").tag(0.95)
                            Text("Standard").tag(0.85)
                        }.pickerStyle(.segmented)
                    }
                    LabeledContent("Color space", value: "SDR · sRGB · 8-bit")
                    if url != nil {
                        LabeledContent("Dimensions", value: dimensions).accessibilityIdentifier(
                            "export.dimensions")
                        if let saveFailure {
                            Text(saveFailure).font(.footnote).foregroundStyle(.secondary)
                        }
                    } else if let failure {
                        Text(failure).foregroundStyle(.secondary)
                        Button("Retry") {
                            overcommitKey = nil
                            retry += 1
                        }
                        if canOvercommit {
                            Button("Try Export Anyway") { confirmOvercommit = true }
                                .accessibilityIdentifier("export.tryAnyway")
                                .confirmationDialog(
                                    "Try export anyway?", isPresented: $confirmOvercommit,
                                    titleVisibility: .visible
                                ) {
                                    Button("Try Export Anyway", role: .destructive) {
                                        overcommitKey = settingsKey
                                    }
                                } message: {
                                    Text(
                                        "This may take longer. If memory runs out, iOS may close SpektraCam. Original photos and saved edits remain stored."
                                    )
                                }
                        }
                    } else {
                        ProgressView("Preparing image…")
                    }
                }
            }
            .disabled(saving)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GlassEffectContainer(spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            shareButton
                            saveButton
                        }
                        VStack(spacing: 10) {
                            shareButton
                            saveButton
                        }
                    }.controlSize(.large).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .navigationTitle("Export").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(
                id: Request(
                    format: format.rawValue, size: size.rawValue, quality: quality, retry: retry,
                    overcommit: overcommitKey == settingsKey)
            ) {
                await prepareExport()
            }
            .task {
                if let session {
                    sourceDimensions = "\(session.photo.width) × \(session.photo.height)"
                } else if let original, let dimensions = try? await original.dimensions() {
                    sourceDimensions = "\(Int(dimensions.width)) × \(Int(dimensions.height))"
                }
            }
            .onDisappear {
                renderTask?.cancel()
                session?.discardExport()
                if let original { Task { await original.discard() } }
            }
        }
        .presentationDetents([.fraction(0.68), .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }
    private var saveButton: some View {
        Button(action: saveToPhotos) {
            HStack(spacing: 7) {
                Image(systemName: saved ? "checkmark" : "square.and.arrow.down").foregroundStyle(
                    .white)
                Text(saved ? "Saved to Photos" : saving ? "Saving…" : "Save to Photos")
            }.padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent).disabled(url == nil || saving || saved)
        .accessibilityIdentifier("export.save")
    }
    private var shareButton: some View {
        ShareLink(item: url ?? URL.temporaryDirectory.appendingPathComponent("PreparingPhoto")) {
            Label("Share", systemImage: "square.and.arrow.up").padding(.vertical, 4)
                .foregroundStyle(url == nil || saving ? Color.secondary : Color.primary)
        }
        .buttonStyle(.glass).disabled(url == nil || saving)
        .accessibilityIdentifier("export.share")
    }
    private func saveToPhotos() {
        guard let url, !saving, !saved else { return }
        saving = true
        saveFailure = nil
        Task {
            do {
                try await PhotoLibraryWriter.save(url)
                if self.url == url { saved = true }
            } catch { saveFailure = error.localizedDescription }
            saving = false
        }
    }
    private func prepareExport() async {
        url = nil
        failure = nil
        canOvercommit = false
        saved = false
        saveFailure = nil
        let previous = renderTask
        previous?.cancel()
        let requestedSize = size
        let requestedFormat = format
        let requestedQuality = quality
        let allowOvercommit = overcommitKey == settingsKey
        let job = Task {
            if let previous { _ = await previous.result }
            try Task.checkCancellation()
            if let session {
                return try await session.export(
                    size: requestedSize, format: requestedFormat, quality: requestedQuality,
                    allowOvercommit: allowOvercommit)
            }
            guard let original else { throw PhotoExporter.Failure.render }
            return try await original.export(
                size: requestedSize, format: requestedFormat, quality: requestedQuality)
        }
        renderTask = job
        do {
            let result = try await withTaskCancellationHandler {
                try await job.value
            } onCancel: {
                job.cancel()
            }
            guard !Task.isCancelled else { return }
            url = result.0
            dimensions = "\(result.1) × \(result.2)"
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
            canOvercommit = (error as? RenderMemoryBudget.Failure)?.estimated != nil
            detent = .large
        }
    }
}
