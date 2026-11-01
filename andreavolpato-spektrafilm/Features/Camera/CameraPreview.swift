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
        view.previewLayer.session = session
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
    func makeUIView(context: Context) -> View {
        let view = View()
        source.connect(to: view)
        context.coordinator.source = source
        return view
    }
    func updateUIView(_ view: View, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleUIView(_ view: View, coordinator: Coordinator) {
        coordinator.source?.disconnect(from: view)
    }
    final class Coordinator { var source: CameraPreviewSource? }
    final class View: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// The preview remains borderless. Grid marks do not intercept touch or accessibility.
struct CameraViewfinder: SwiftUI.View {
    let model: CameraModel
    var body: some SwiftUI.View {
        Group {
            if let source = model.source {
                CameraPreview(source: source).id(ObjectIdentifier(source))
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
        }.accessibilityHidden(true)
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
        VStack(alignment: .trailing, spacing: 1) {
            Text(
                reading.seconds > 0
                    ? (reading.seconds < 1
                        ? "1/\(Int((1 / reading.seconds).rounded())) s"
                        : "\(reading.seconds.formatted(.number.precision(.fractionLength(1)))) s") : "— s")
            Text(
                reading.iso > 0
                    ? "ƒ\(reading.aperture.formatted(.number.precision(.fractionLength(1)))) · ISO \(Int(reading.iso.rounded()))"
                    : "ƒ— · ISO —")
        }
        .font(.system(.caption2, design: .monospaced).weight(.medium)).foregroundStyle(.secondary)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .combine)
    }
}
