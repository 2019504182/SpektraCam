import SwiftUI
import UIKit

/// The photograph stays visible while contextual controls edit one shared recipe.
struct EditorView: View {
    let session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var activeTool: EditorTool? = .develop
    @State private var showExitConfirmation = false
    @State private var showExport = false
    @State private var showOriginal = false
    @State private var showResetConfirmation = false
    @State private var showRenderProgress = false

    var body: some View {
        canvas.safeAreaInset(edge: .bottom, spacing: 0) { toolPanel }
            .background(EditorNavigationGuard().allowsHitTesting(false))
            .navigationTitle(activeTool?.title ?? "Editor")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close Editor", systemImage: "xmark") { showExitConfirmation = true }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("editor.back")
                        .confirmationDialog(
                            "Return to Photos?", isPresented: $showExitConfirmation, titleVisibility: .visible
                        ) {
                            Button("Return to Photos", role: session.hasEdits ? .destructive : nil) {
                                dismiss()
                            }
                            Button("Keep Editing", role: .cancel) {}
                        } message: {
                            Text(
                                session.hasEdits
                                    ? "Your edits to this photo will be discarded."
                                    : "Leave this photo and return to the gallery?")
                        }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("History", systemImage: "arrow.uturn.backward") {
                        Button("Undo", systemImage: "arrow.uturn.backward", action: session.undo).disabled(
                            !session.canUndo)
                        Button("Redo", systemImage: "arrow.uturn.forward", action: session.redo).disabled(
                            !session.canRedo)
                        Divider()
                        Button("Reset All Edits", role: .destructive) { showResetConfirmation = true }
                            .disabled(!session.hasEdits)
                    }
                    .accessibilityIdentifier("editor.history")
                }
                if activeTool != .crop {
                    ToolbarItem(placement: .topBarTrailing) {
                        Toggle("Show Original", systemImage: "square.on.square", isOn: $showOriginal)
                            .toggleStyle(.button).labelStyle(.iconOnly)
                            .accessibilityIdentifier("editor.compare")
                    }
                }
                if activeTool == .crop {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Reset") {
                            session.update(key: "crop.reset") {
                                $0.crop = CropSelection()
                                $0.geometry = ImageGeometry()
                            }
                        }
                        .disabled(
                            session.recipe.crop == CropSelection() && session.recipe.geometry.isIdentity
                        )
                        .accessibilityLabel("Reset Crop").accessibilityIdentifier("crop.reset")
                        Button("Done", systemImage: "checkmark") { activeTool = nil }
                            .labelStyle(.iconOnly).accessibilityIdentifier("crop.done")
                    }
                }
                EditorToolbar(activeTool: $activeTool) { showExport = true }
            }
            .task(id: session.isBusy) {
                showRenderProgress = false
                guard session.isBusy else { return }
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                if !Task.isCancelled { showRenderProgress = true }
            }
            .onAppear { session.resumeRendering() }
            .onDisappear { session.cancelRendering() }
            .onChange(of: activeTool) { _, _ in showOriginal = false }
            .alert("Reset all edits?", isPresented: $showResetConfirmation) {
                Button("Reset All Edits", role: .destructive) {
                    session.update(key: "reset") { recipe in
                        recipe = EditRecipe()
                        recipe.temperature = session.photo.rawTemperature
                    }
                }
            }
            .sheet(isPresented: $showExport) { ExportPanel(session: session) }
            .alert(
                "Couldn’t render preview",
                isPresented: Binding(get: { session.renderFailed }, set: { session.renderFailed = $0 })
            ) {
                Button("Retry", action: session.renderGeometry)
                Button("Reset Rotation", role: .cancel) {
                    session.update(key: "geometry.reset") { $0.geometry = ImageGeometry() }
                }
            }
    }
    private var canvas: some View {
        ZStack {
            VStack(spacing: 6) {
                EditorInfoBar(session: session, showingOriginal: showOriginal) { activeTool = .develop }
                if activeTool == .crop {
                    CropCanvas(image: session.geometryImage, selection: session.binding(\.crop, key: "crop"))
                        .allowsHitTesting(!session.isRendering)
                } else {
                    ZoomablePhoto(
                        image: showOriginal ? UIImage(cgImage: session.photo.preview) : session.displayImage
                    )
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
            if showRenderProgress { ProgressView().accessibilityLabel("Rendering preview") }
            if session.filmRenderFailed {
                VStack {
                    Spacer()
                    HStack {
                        Label("Couldn’t update preview", systemImage: "exclamationmark.triangle")
                        Button("Retry", action: session.renderFilm)
                    }
                    .font(.footnote).padding(12)
                    .background(.regularMaterial, in: .capsule)
                }.padding()
            }
        }
        .background(EditorTheme.canvas)
    }

    @ViewBuilder private var toolPanel: some View {

        if activeTool == .crop {
            CropControls(
                crop: session.binding(\.crop, key: "crop"),
                geometry: session.binding(\.geometry, key: "straighten"),
                imageAspect: imageAspect,
                rotateLeft: {
                    let aspect = imageAspect
                    session.update(key: "rotate") {
                        $0.crop.rotateLeft(imageAspect: aspect)
                        $0.geometry.rotateLeft()
                    }
                },
                flipHorizontal: {
                    session.update(key: "flip") {
                        $0.crop.flipHorizontal()
                        $0.geometry.flipHorizontal()
                    }
                },
                flipVertical: {
                    session.update(key: "flip") {
                        $0.crop.flipVertical()
                        $0.geometry.flipVertical()
                    }
                }, onStraightenEditingChanged: { session.setInteraction(key: "straighten", active: $0) })
        } else if activeTool == .develop {
            DevelopPanel(session: session)
                .padding(.horizontal).padding(.vertical, 12)
                .frame(height: 310)
                .background(.background)
        } else if let activeTool {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch activeTool {
                    case .develop: EmptyView()
                    case .adjust: AdjustPanel(session: session)
                    case .effects: EffectsPanel(session: session)
                    case .crop: EmptyView()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .frame(maxHeight: 310)
            .background(.background)
            .accessibilityIdentifier("editor.controls")
        }
    }

    private var imageAspect: CGFloat {
        let source = session.photo.preview
        let aspect = CGFloat(source.width) / CGFloat(source.height)
        return session.recipe.geometry.quarterTurns % 2 == 0 ? aspect : 1 / aspect
    }

}

/// Scope UIKit's two public pop recognizers to this editor; restore on exit.
private struct EditorNavigationGuard: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.lock() }

    final class Controller: UIViewController {
        private var saved: [(UIGestureRecognizer, Bool)] = []

        override func loadView() {
            let view = UIView()
            view.isUserInteractionEnabled = false
            self.view = view
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            lock()
        }

        override func viewWillDisappear(_ animated: Bool) {
            saved.forEach { $0.0.isEnabled = $0.1 }
            saved.removeAll()
            super.viewWillDisappear(animated)
        }

        func lock() {
            guard let navigationController else { return }
            let recognizers = [
                navigationController.interactivePopGestureRecognizer,
                navigationController.interactiveContentPopGestureRecognizer,
            ].compactMap { $0 }
            for recognizer in recognizers {
                if !saved.contains(where: { $0.0 === recognizer }) {
                    saved.append((recognizer, recognizer.isEnabled))
                }
                if recognizer.isEnabled { recognizer.isEnabled = false }
            }
        }
    }
}
