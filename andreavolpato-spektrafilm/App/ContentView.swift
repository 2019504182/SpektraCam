import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Open the app-owned library. A failed database open never resets the user's data.
struct ContentView: View {
    @State private var library: PhotoLibrary?
    @State private var failure: String?
    @State private var showCamera = false
    @State private var captureImportFailure: String?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let library {
                LibraryView(library: library)
                    .environment(\.openCamera, { showCamera = true })
                    .fullScreenCover(isPresented: $showCamera) { CameraView(library: library) }
                    .task { await recoverCaptures(library); try? await library.luts.load() }
            } else if let failure {
                ContentUnavailableView {
                    Label("Couldn’t open library", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Retry", action: openLibrary)
                }
            } else {
                ProgressView("Opening library…")
            }
        }
        .task { if library == nil { openLibrary() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                do { try library?.flushPending() } catch { library?.saveFailure = error.localizedDescription }
            }
        }
        .alert(
            "Couldn’t import capture",
            isPresented: Binding(
                get: { captureImportFailure != nil },
                set: { if !$0 { captureImportFailure = nil } }
            )
        ) {
            Button("Retry") { if let library { Task { await recoverCaptures(library) } } }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The capture is kept on this iPhone. " + (captureImportFailure ?? ""))
        }
        .alert(
            "Couldn’t save edits",
            isPresented: Binding(
                get: { library?.saveFailure != nil },
                set: {
                    if !$0 { library?.saveFailure = nil }
                })
        ) {
            Button("Retry") {
                do { try library?.flushPending() } catch { library?.saveFailure = error.localizedDescription }
            }
        } message: {
            Text(library?.saveFailure ?? "")
        }
    }
    private func recoverCaptures(_ library: PhotoLibrary) async {
        do {
            try await library.recoverCaptures()
            captureImportFailure = nil
        } catch { captureImportFailure = error.localizedDescription }
    }
    private func openLibrary() {
        do {
            #if DEBUG && targetEnvironment(simulator)
                // UI checks use their own store. They cannot reset the user's app library.
                if ProcessInfo.processInfo.arguments.contains("--ui-test-library") {
                    let base = URL.applicationSupportDirectory.appendingPathComponent("SpektraCamUITests")
                    if ProcessInfo.processInfo.arguments.contains("--reset-test-library") {
                        try? FileManager.default.removeItem(at: base)
                    }
                    library = try PhotoLibrary(root: base, cache: base.appendingPathComponent("Cache"))
                } else {
                    library = try PhotoLibrary()
                }
            #else
                library = try PhotoLibrary()
            #endif
            failure = nil
        } catch { failure = error.localizedDescription }
    }
}

#Preview { ContentView() }
