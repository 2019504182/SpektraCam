@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Only the actor configures the session. This bridge attaches it to a main-thread preview.
nonisolated final class CameraPreviewSource: @unchecked Sendable {
    private let session: AVCaptureSession
    private let device: AVCaptureDevice
    @MainActor private var rotation: AVCaptureDevice.RotationCoordinator?
    @MainActor private var observation: NSKeyValueObservation?
    init(session: AVCaptureSession, device: AVCaptureDevice) {
        self.session = session
        self.device = device
    }
    @MainActor var captureRotation: CGFloat { rotation?.videoRotationAngleForHorizonLevelCapture ?? 90 }
    @MainActor func connect(to view: CameraPreview.View) {
        if view.previewLayer.session !== session { view.previewLayer.session = session }
        view.previewLayer.videoGravity = .resizeAspect
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: view.previewLayer)
        rotation = coordinator
        observation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]
        ) { [weak view] coordinator, _ in
            // RotationCoordinator documents delivery on the main queue.
            MainActor.assumeIsolated {
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                if let connection = view?.previewLayer.connection,
                    connection.isVideoRotationAngleSupported(angle)
                {
                    connection.videoRotationAngle = angle
                }
            }
        }
    }
    @MainActor func disconnect(from view: CameraPreview.View) {
        observation = nil
        rotation = nil
        view.previewLayer.session = nil
    }
}

struct CameraPreview: UIViewRepresentable {
    let source: CameraPreviewSource
    var onFocus: ((CGPoint, CGPoint) -> Void)?
    func makeUIView(context: Context) -> View {
        let view = View()
        source.connect(to: view)
        context.coordinator.source = source
        context.coordinator.onFocus = onFocus
        view.addGestureRecognizer(
            UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.focus(_:))))
        return view
    }
    func updateUIView(_ view: View, context: Context) {
        context.coordinator.onFocus = onFocus
        if context.coordinator.source !== source {
            source.connect(to: view)
            context.coordinator.source = source
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleUIView(_ view: View, coordinator: Coordinator) {
        coordinator.source?.disconnect(from: view)
        coordinator.onFocus = nil
    }
    final class Coordinator: NSObject {
        var source: CameraPreviewSource?
        var onFocus: ((CGPoint, CGPoint) -> Void)?
        @objc func focus(_ tap: UITapGestureRecognizer) {
            guard let view = tap.view as? View else { return }
            let point = tap.location(in: view)
            onFocus?(
                view.convert(point, to: nil),
                view.previewLayer.captureDevicePointConverted(fromLayerPoint: point))
        }
    }
    final class View: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// The preview remains borderless. Grid marks do not intercept touch or accessibility.
struct CameraViewfinder: SwiftUI.View {
    let model: CameraModel
    @State private var focusPoint: CGPoint?
    @State private var focusRevision = UUID()
    @State private var adjustingExposure = false
    var body: some SwiftUI.View {
        Group {
            if let source = model.source {
                CameraPreview(source: source) { point, devicePoint in
                    guard model.state == .ready, !model.busy else { return }
                    focusPoint = point
                    focusRevision = UUID()
                    Task { await model.focus(at: devicePoint) }
                }.accessibilityHidden(true)
            } else {
                Color.black
            }
        }
        .aspectRatio(3.0 / 4, contentMode: .fit).frame(maxWidth: .infinity)
        .overlay {
            if model.source != nil {
                GeometryReader { proxy in
                    Path { path in
                        for fraction in [1.0 / 3, 2.0 / 3] {
                            let x = proxy.size.width * fraction
                            let y = proxy.size.height * fraction
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        }
                    }.stroke(.white.opacity(0.22), lineWidth: 0.5)
                }.allowsHitTesting(false)
            }
        }
        .overlay {
            if let point = focusPoint, model.state == .ready {
                GeometryReader { proxy in
                    let origin = proxy.frame(in: .global).origin
                    let x = min(max(point.x - origin.x, 26), proxy.size.width - 26)
                    let y = min(max(point.y - origin.y, 80), proxy.size.height - 80)
                    Rectangle().stroke(.yellow, lineWidth: 1)
                        .frame(width: 56, height: 56).position(x: x, y: y)
                        .allowsHitTesting(false).accessibilityHidden(true)
                    VStack(spacing: 4) {
                        Image(systemName: "sun.max").font(.system(size: 16))
                        Slider(
                            value: Binding(
                                get: { model.exposureBias },
                                set: {
                                    model.setExposureBias($0)
                                    focusRevision = UUID()
                                }
                            ), in: model.exposureRange,
                            onEditingChanged: { value in
                                adjustingExposure = value
                                focusRevision = UUID()
                            }
                        )
                        .labelsHidden().tint(.yellow)
                        .frame(width: 112).rotationEffect(.degrees(-90)).frame(width: 44, height: 112)
                        .accessibilityLabel("Camera exposure")
                        .accessibilityValue(String(format: "%+.1f EV", model.exposureBias))
                        .accessibilityIdentifier("camera.exposure")
                        Text(String(format: "%+.1f", model.exposureBias)).font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(.yellow)
                    .position(x: x < proxy.size.width - 76 ? x + 46 : x - 46, y: y)
                    .disabled(model.busy)
                }
            }
        }
        .onChange(of: model.selectedLens?.id) { _, _ in focusPoint = nil }
        .task(id: focusRevision) {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !adjustingExposure else { return }
            focusPoint = nil
        }
    }
}

struct CameraHistogram: SwiftUI.View {
    let model: CameraModel
    var body: some SwiftUI.View {
        let bins = model.readings.histogram
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for (index, value) in bins.enumerated() {
                path.addLine(
                    to: CGPoint(
                        x: CGFloat(index) / CGFloat(bins.count - 1) * size.width,
                        y: (1 - value) * size.height))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(.white.opacity(0.75)))
        }
        .accessibilityLabel("Preview brightness histogram")
        .accessibilityHint("Shows the processed camera preview, not RAW clipping.")
    }
}

struct CameraExposureReadout: SwiftUI.View {
    let model: CameraModel
    var body: some SwiftUI.View {
        let reading = model.readings
        VStack(alignment: .trailing, spacing: 0) {
            Text(
                reading.seconds > 0
                    ? (reading.seconds < 1
                        ? "1/\(Int((1 / reading.seconds).rounded())) s"
                        : "\(reading.seconds.formatted(.number.precision(.fractionLength(1)))) s") : "— s")
            Text(
                reading.iso > 0
                    ? "ƒ\(reading.aperture.formatted(.number.precision(.fractionLength(1)))) | ISO\(Int(reading.iso.rounded()))"
                    : "ƒ— | ISO—")
        }
        .font(.caption2.weight(.medium)).monospacedDigit().lineLimit(1).foregroundStyle(.secondary)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .combine)
    }
}
