//
//  ContentView.swift
//  andreavolpato-spektrafilm
//
//  Created by Runze Ni on 10/30/26.
//

import ImageIO
import OSLog
import PhotosUI
import SwiftUI
import UIKit

/// Hosts the photo library and opens the selected photograph. ED-01.
struct ContentView: View {
    private static let logger = Logger(
        subsystem: "io.github.runzeni.andreavolpato-spektrafilm", category: "PhotoLoading")
    @State private var pickerSessionID = UUID()
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var confirmedPhoto: PhotosPickerItem?
    @State private var editorSession: EditorSession?
    @State private var isLoading = false
    @State private var showLoadError = false
    @State private var loadAttempt = 0

    var body: some View {
        NavigationStack {
            PhotosPicker(
                "Photos",
                selection: $selectedPhotos,
                maxSelectionCount: 1,
                selectionBehavior: .continuous,
                matching: .images,
                preferredItemEncoding: .current
            )
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities(.selectionActions)
            .photosPickerAccessoryVisibility(.hidden, edges: .bottom)
            .id(pickerSessionID)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open", systemImage: "checkmark", action: confirmSelection)
                        .labelStyle(.iconOnly)
                        .disabled(selectedPhotos.isEmpty || isLoading)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isLoading {
                    ProgressView("Loading photo…")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.background)
                }
            }
            .navigationDestination(item: $editorSession) { session in
                EditorView(session: session)
                    .toolbar(.visible, for: .navigationBar)
            }
        }
        .onChange(of: selectedPhotos) { _, _ in
            // A changed selection cancels loading and waits for confirmation.
            confirmedPhoto = nil
            loadAttempt += 1
        }
        .onChange(of: editorSession) { _, session in
            if session == nil {
                selectedPhotos = []
                confirmedPhoto = nil
                // A fresh picker avoids stale transfer providers after Back.
                pickerSessionID = UUID()
            }
        }
        .task(id: loadAttempt) {
            await loadSelectedPhoto()
        }
        .alert("Couldn’t open photo", isPresented: $showLoadError) {
            Button("Retry", action: confirmSelection)
            Button("Choose Another", role: .cancel) { selectedPhotos = [] }
        } message: {
            Text("Try again, or choose a different photo.")
        }
    }

    private func confirmSelection() {
        guard let photo = selectedPhotos.first else { return }
        confirmedPhoto = photo
        loadAttempt += 1
    }

    /// Loads only a confirmed selection; cancellation discards older results.
    private func loadSelectedPhoto() async {
        isLoading = false
        guard let photo = confirmedPhoto else { return }
        isLoading = true
        defer {
            if !Task.isCancelled { isLoading = false }
        }

        do {
            let imported = try await photo.loadTransferable(type: PhotoImport.self)
            try Task.checkCancellation()
            guard let imported else {
                let types = photo.supportedContentTypes.map(\.identifier).joined(separator: ", ")
                Self.logger.error("Photo selection supplied no image data. Types: \(types, privacy: .public)")
                showLoadError = true
                return
            }

            let data = imported.data
            let preview = await Task.detached(priority: .userInitiated) {
                ImportedPhoto.decode(data)
            }.value
            try Task.checkCancellation()
            guard let preview else {
                Self.logger.error("ImageIO could not decode the selected photo.")
                showLoadError = true
                return
            }

            editorSession = EditorSession(photo: preview)
        } catch {
            if !Task.isCancelled {
                let failure = error as NSError
                Self.logger.error(
                    "Photo transfer failed: \(failure.domain, privacy: .public), code \(failure.code)")
                showLoadError = true
            }
        }
    }

}

#Preview {
    ContentView()
}
