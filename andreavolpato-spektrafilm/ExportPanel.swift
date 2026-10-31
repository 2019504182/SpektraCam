import SwiftUI

struct ExportPanel: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var format = PhotoExporter.Format.jpeg
    @State private var size = PhotoExporter.Size.full
    @State private var quality = 0.95
    @State private var retry = 0
    @State private var url: URL?
    @State private var dimensions = ""
    @State private var failure: String?
    @State private var saving = false
    @State private var saved = false
    @State private var saveFailure: String?
    @State private var renderTask: Task<(URL, Int, Int), Error>?
    private struct Request: Hashable { let format: String, size: String, quality: Double, retry: Int }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Size", selection: $size) {
                        ForEach(PhotoExporter.Size.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(
                        size.maximum.map { "Maximum long edge · \($0) px" }
                            ?? "Original resolution, with crop applied"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Picker("Format", selection: $format) {
                        ForEach(PhotoExporter.Format.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if format == .jpeg {
                        Picker("JPEG quality", selection: $quality) {
                            Text("Standard").tag(0.85)
                            Text("High").tag(0.95)
                            Text("Maximum").tag(1.0)
                        }.pickerStyle(.segmented)
                    }
                    LabeledContent("Color", value: "SDR · sRGB · 8-bit")
                    if let url {
                        LabeledContent("Dimensions", value: dimensions)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                saveButton(url)
                                shareButton(url)
                            }
                            VStack(spacing: 12) {
                                saveButton(url)
                                shareButton(url)
                            }
                        }
                        if let saveFailure { Text(saveFailure).font(.footnote).foregroundStyle(.secondary) }
                    } else if let failure {
                        Text(failure).foregroundStyle(.secondary)
                        Button("Retry") { retry += 1 }
                    } else {
                        ProgressView("Rendering edited image…")
                    }
                }
            }
            .navigationTitle("Export").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: Request(format: format.rawValue, size: size.rawValue, quality: quality, retry: retry)) {
                await prepareExport()
            }
            .onDisappear {
                renderTask?.cancel()
                session.discardExport()
            }
        }
        .presentationDetents([.large])
    }
    private func saveButton(_ url: URL) -> some View {
        Button {
            saving = true
            saveFailure = nil
            Task {
                do {
                    try await PhotoLibraryWriter.save(url)
                    if self.url == url { saved = true }
                } catch { saveFailure = error.localizedDescription }
                saving = false
            }
        } label: {
            Label(
                saved ? "Saved to Photos" : saving ? "Saving…" : "Save to Photos",
                systemImage: saved ? "checkmark" : "square.and.arrow.down"
            )
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent).disabled(saving || saved)
        .accessibilityIdentifier("export.save")
    }
    private func shareButton(_ url: URL) -> some View {
        ShareLink(item: url) {
            Label("Share", systemImage: "square.and.arrow.up").padding(.vertical, 6)
        }
        .buttonStyle(.glass).accessibilityIdentifier("export.share")
    }
    private func prepareExport() async {
        url = nil
        failure = nil
        saved = false
        saveFailure = nil
        let previous = renderTask
        previous?.cancel()
        let requestedSize = size
        let requestedFormat = format
        let requestedQuality = quality
        let job = Task {
            if let previous { _ = await previous.result }
            try Task.checkCancellation()
            return try await session.export(
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
        }
    }
}
