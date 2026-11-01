import SwiftUI

struct CameraView: View {
    @State private var model: CameraModel
    @State private var showLibrary = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    init(library: PhotoLibrary) { _model = State(initialValue: CameraModel(library: library)) }
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                CameraViewfinder(model: model)
                if model.state == .ready {
                    VStack {
                        Spacer()
                        lensControls.padding(.horizontal).padding(.bottom, 12)
                    }
                }
                if model.state != .ready { status }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close Camera", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).buttonBorderShape(.circle)
                        .disabled(model.busy).accessibilityIdentifier("camera.close")
                }
                ToolbarItem(placement: .topBarLeading) { formatControl }
                ToolbarItem(placement: .principal) {
                    CameraHistogram(model: model).frame(width: 100, height: 32)
                }
                ToolbarItem(placement: .topBarTrailing) { CameraExposureReadout(model: model) }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if let failure = model.saveFailure {
                        VStack(spacing: 8) {
                            Text(failure).font(.footnote)
                            if model.pendingCount > 0 {
                                Text("The capture is kept on this iPhone.").font(.footnote)
                                Button("Retry Import") { Task { await model.retryImport() } }
                                    .buttonStyle(.glass).disabled(model.busy)
                                    .accessibilityIdentifier("camera.retryImport")
                            }
                        }.padding().glassEffect(in: .rect(cornerRadius: 20))
                    }
                    HStack {
                        Button {
                            showLibrary = true
                        } label: {
                            if let photo = model.library.photos.last {
                                PhotoThumbnail(photo: photo, images: model.library.images, showsBadges: false)
                                    .frame(width: 44, height: 44).clipShape(.circle)
                            } else {
                                Image(systemName: "photo.on.rectangle").frame(width: 44, height: 44)
                            }
                        }
                        .buttonStyle(.glass).buttonBorderShape(.circle).disabled(model.busy)
                        .accessibilityLabel("Open Library").accessibilityIdentifier("camera.library")
                        Spacer()
                        Button {
                            Task { await model.takePhoto() }
                        } label: {
                            Image(systemName: "circle.inset.filled")
                                .font(.system(size: 58, weight: .regular)).frame(width: 76, height: 76)
                        }
                        .buttonStyle(.glass).buttonBorderShape(.circle).tint(.white)
                        .disabled(!model.canCapture)
                        .accessibilityLabel("Take RAW Photo").accessibilityIdentifier("camera.shutter")
                        .overlay { if model.busy { ProgressView().allowsHitTesting(false) } }
                        Spacer()
                        Button("Front Camera", systemImage: "arrow.triangle.2.circlepath.camera") {
                            Task { await model.flip() }
                        }
                        .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                        .frame(width: 60, height: 60)
                        .disabled(model.busy || !model.lenses.contains(where: \.front))
                        .accessibilityIdentifier("camera.flip")
                    }
                    Text(
                        model.savedCount > 0
                            ? "Saved to Library: \(model.savedCount)" : "RAW photos save to the app library."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("camera.saved")
                }.padding(.horizontal).padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView(library: model.library, onClose: { showLibrary = false })
                .environment(\.openCamera, { showLibrary = false })
                .presentationDetents([.large])
        }
        .onChange(of: showLibrary) { _, shown in
            Task { await model.setActive(!shown && scenePhase == .active) }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(model.busy)
        .task {
            await model.retryImport()
            await model.setActive(scenePhase == .active && !showLibrary)
            await model.monitor()
        }
        .onChange(of: scenePhase) { _, phase in
            Task { await model.setActive(phase == .active && !showLibrary) }
        }
        .onDisappear { Task { await model.close() } }
    }
    @ViewBuilder private var formatControl: some View {
        if model.formats.count > 1 {
            Menu {
                Picker("RAW Format", selection: $model.format) {
                    ForEach(model.formats) { Text($0.title).tag($0) }
                }
            } label: {
                Text("DNG").font(.caption.weight(.semibold))
            }
            .disabled(model.busy).accessibilityIdentifier("camera.format")
            .accessibilityLabel("DNG, " + model.format.title)
        } else {
            Text("DNG").font(.caption.weight(.semibold)).accessibilityLabel("DNG RAW")
        }
    }
    private var lensControls: some View {
        GlassEffectContainer(spacing: 8) {
            HStack {
                if model.selectedLens?.front != true && model.lenses.contains(where: \.macro) {
                    Button("Macro", systemImage: "camera.macro") { Task { await model.toggleMacro() } }
                        .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                        .tint(model.macro ? Color.accentColor : .primary)
                        .accessibilityAddTraits(model.macro ? .isSelected : [])
                        .accessibilityIdentifier("camera.macro")
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(model.lenses.filter { $0.front == (model.selectedLens?.front == true) }) { lens in
                        Button(lens.title) { Task { await model.selectLens(lens) } }
                            .font(.caption.weight(.semibold)).monospacedDigit()
                            .frame(minWidth: 44, minHeight: 44)
                            .buttonStyle(.glass).buttonBorderShape(.circle)
                            .tint(lens.id == model.selectedLens?.id ? Color.accentColor : .primary)
                            .accessibilityAddTraits(lens.id == model.selectedLens?.id ? .isSelected : [])
                            .accessibilityLabel(
                                lens.front ? "Front camera" : "\(lens.millimeters) millimeter lens")
                    }
                }
                Spacer(minLength: 8)
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }.disabled(model.busy).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
    @ViewBuilder private var status: some View {
        switch model.state {
        case .ready: EmptyView()
        case .starting: ProgressView("Starting camera…")
        case .unavailable:
            ContentUnavailableView(
                "Camera Unavailable", systemImage: "camera",
                description: Text("RAW capture needs a physical iPhone.")
            )
            .accessibilityIdentifier("camera.unavailable")
        case .denied:
            ContentUnavailableView {
                Label("Camera Access", systemImage: "camera")
            } description: {
                Text("Allow camera access in Settings to take photos.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.buttonStyle(.glass)
            }
        case .paused:
            ContentUnavailableView(
                "Camera Paused", systemImage: "camera",
                description: Text("The camera will resume when it is available."))
        case .failed(let message):
            ContentUnavailableView {
                Label("Camera Stopped", systemImage: "camera")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await model.setActive(true) } }.buttonStyle(.glass)
            }
        }
    }
}

private struct CameraActionKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues {
    var openCamera: (() -> Void)? {
        get { self[CameraActionKey.self] }
        set { self[CameraActionKey.self] = newValue }
    }
}
