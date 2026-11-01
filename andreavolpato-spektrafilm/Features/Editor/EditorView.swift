import SwiftUI
import UIKit

/// The photograph stays visible while contextual controls edit one shared recipe.
struct EditorView: View {
    let session: EditorSession
    var locationName: String? = nil
    let onFinish: () async throws -> Void
    @State private var closing = false
    @State private var closeFailure: String?
    @Environment(\.dismiss) private var dismiss
    @State private var activeTool: EditorTool? = .develop
    @State private var panelExpanded = true
    @State private var inspectorFrame = CGRect.zero
    @State private var adjustSection = AdjustPanel.Section.exposure
    @State private var effectsSection = EffectsPanel.Section.grain
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showExport = false
    @State private var showOriginal = false
    @State private var showResetConfirmation = false
    @State private var showRenderProgress = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { workspace in
                canvas.overlay(alignment: .bottom) {
                    if activeTool != nil && activeTool != .crop {
                        let maximum = maximumPanelHeight(in: workspace.size.height)
                        inspector(
                            height: panelExpanded ? maximum : min(maximum, collapsedPanelHeight)
                        )
                        .padding(.horizontal, 12).padding(.bottom, 8)
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .global)
                        } action: {
                            inspectorFrame = $0
                        }
                    }
                }
            }
            if activeTool == .crop { toolPanel }
            EditorToolbar(activeTool: $activeTool) {
                setExpanded(false)
                showExport = true
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(EditorNavigationGuard().allowsHitTesting(false))
        .navigationTitle(activeTool?.title ?? "Editor")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close Editor", systemImage: "xmark", action: finish)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("editor.back")
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
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            if activeTool != .crop {
                ToolbarItem(placement: .topBarTrailing) { CameraButton() }
            }
            if activeTool == .crop {
                ToolbarItem(placement: .topBarTrailing) {
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
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", systemImage: "checkmark") { activeTool = nil }
                        .labelStyle(.iconOnly).accessibilityIdentifier("crop.done")
                }
            }
        }
        .task(id: session.isBusy) {
            showRenderProgress = false
            guard session.isBusy else { return }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            if !Task.isCancelled { showRenderProgress = true }
        }
        .disabled(closing)
        .overlay { if closing { ProgressView("Saving edits…") } }
        .alert(
            "Couldn’t save edits",
            isPresented: Binding(get: { closeFailure != nil }, set: { if !$0 { closeFailure = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(closeFailure ?? "")
        }
        .onAppear {
            session.recipeDidChange?(session.recipe, true)
            session.resumeRendering()
        }
        .onDisappear { session.cancelRendering() }
        .onChange(of: activeTool) { _, _ in
            showOriginal = false
            panelExpanded = activeTool == .develop
        }
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
    private func finish() {
        guard !closing else { return }
        closing = true
        Task {
            do {
                try await onFinish()
                dismiss()
            } catch { closeFailure = error.localizedDescription }
            closing = false
        }
    }
    private var canvas: some View {
        ZStack {
            if activeTool == .crop {
                CropCanvas(image: session.geometryImage, selection: session.binding(\.crop, key: "crop"))
                    .allowsHitTesting(!session.isRendering)
            } else {
                PhotoViewport(
                    image: showOriginal ? UIImage(cgImage: session.photo.preview) : session.displayImage,
                    onTap: { point in
                        if panelExpanded && !inspectorFrame.contains(point) { setExpanded(false) }
                    }
                )
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        EditorInfoBar(
                            session: session, showingOriginal: showOriginal, location: locationName,
                            onInteraction: { if panelExpanded { setExpanded(false) } })
                        HStack {
                            Spacer()
                            Button(
                                showOriginal ? "Show Edited" : "Show Original",
                                systemImage: "square.on.square"
                            ) {
                                showOriginal.toggle()
                                if panelExpanded { setExpanded(false) }
                            }
                            .labelStyle(.iconOnly)
                            .tint(showOriginal ? Color.accentColor : Color.primary)
                            .accessibilityAddTraits(showOriginal ? .isSelected : [])
                            .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                            .accessibilityIdentifier("editor.compare")
                        }
                    }.padding(.horizontal, 12).padding(.top, 4)
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
        .background(PhotoTheme.canvas)
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

        } else if let activeTool {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch activeTool {
                    case .develop: EmptyView()
                    case .adjust: AdjustPanel(session: session, section: adjustSection)
                    case .effects: EffectsPanel(session: session, section: effectsSection)
                    case .crop: EmptyView()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .id(activeTool == .adjust ? adjustSection.rawValue : effectsSection.rawValue)
            .accessibilityIdentifier("editor.controls")
        }
    }

    private func maximumPanelHeight(in height: CGFloat) -> CGFloat {
        max(120, height - PhotoInfoPanel.collapsedHeight - 12 - 56 - 52 - 8)
    }

    private var collapsedPanelHeight: CGFloat {
        if activeTool == .develop { return 270 }
        if activeTool == .adjust {
            switch adjustSection {
            case .exposure: return 260
            case .liftGain: return 160
            case .color: return 280
            }
        }
        return 280
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { panelExpanded = expanded }
    }
    private func inspector(height: CGFloat) -> some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if activeTool == .adjust {
                        PanelTabs(
                            options: AdjustPanel.Section.allCases.map { ($0, $0.title) },
                            selection: $adjustSection, prefix: "adjust.section.")
                    } else if activeTool == .effects {
                        PanelTabs(
                            options: EffectsPanel.Section.allCases.map { ($0, $0.title) },
                            selection: $effectsSection, prefix: "effects.section.")
                    } else {
                        Spacer()
                    }
                    Button(
                        panelExpanded ? "Collapse Panel" : "Expand Panel",
                        systemImage: panelExpanded ? "chevron.down" : "chevron.up"
                    ) {
                        setExpanded(!panelExpanded)
                    }
                    .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("editor.expand")
                    .accessibilityValue(panelExpanded ? "Expanded" : "Collapsed")
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                toolPanel.frame(height: height).glassEffect(in: .rect(cornerRadius: 24))
            }
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

/// System glass buttons retain their native pressed state; the horizontal row can scroll.
private struct PanelTabs<Selection: Hashable & RawRepresentable>: View where Selection.RawValue == String {
    let options: [(Selection, String)]
    @Binding var selection: Selection
    let prefix: String
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(options, id: \.0) { option in
                    Group {
                        if selection == option.0 {
                            tab(option).buttonStyle(.glassProminent)
                        } else {
                            tab(option).buttonStyle(.glass)
                        }
                    }
                    .accessibilityIdentifier(prefix + option.0.rawValue)
                    .accessibilityAddTraits(selection == option.0 ? .isSelected : [])
                }
            }.padding(.vertical, 4)
        }.scrollIndicators(.hidden).frame(height: 44).clipped()
    }
    private func tab(_ option: (Selection, String)) -> some View {
        Button(option.1) { selection = option.0 }
            .font(.caption.weight(.semibold)).lineLimit(1).fixedSize()
            .frame(minHeight: 36)
            .accessibilityShowsLargeContentViewer { Text(option.1) }
    }
}
