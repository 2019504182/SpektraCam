import SwiftUI
import UIKit

/// Neutral surround keeps the controls' accent out of the photograph.
enum EditorTheme {
    static let canvas = Color(
        uiColor: UIColor { traits in
            UIColor(white: traits.userInterfaceStyle == .dark ? 0.16 : 0.94, alpha: 1)
        })
}

struct EditorInfoBar: View {
    let session: EditorSession
    let showingOriginal: Bool
    let openDevelop: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var channels = false
    @State private var showDetails = false
    private var filmName: String { FilmStock.films.first { $0.id == session.recipe.filmID }?.name ?? "Film" }
    private var printName: String {
        session.recipe.bypassesPrint
            ? "Direct scan"
            : (FilmStock.prints.first { $0.id == session.recipe.printID }?.name ?? "Print")
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: openDevelop) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(filmName).font(.caption.weight(.medium))
                    Text(printName.replacingOccurrences(of: "Professional ", with: ""))
                        .font(.caption2).foregroundStyle(.secondary)
                }.multilineTextAlignment(.leading).lineLimit(2)
                    .frame(minHeight: 44, alignment: .topLeading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Current film and print. Open Develop")
                .accessibilityValue(filmName + ", " + printName)
            Spacer(minLength: 0)
            Group {
                if typeSize.isAccessibilitySize {
                    HStack(spacing: 4) {
                        histogramButton
                        Button {
                            showDetails = true
                        } label: {
                            Image(systemName: "info.circle").font(.system(size: 20))
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.accessibilityLabel("Photo details")
                            .accessibilityIdentifier("editor.photoDetails")
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        histogramButton
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(session.photo.metadata.sizeLine)
                            Text(session.photo.metadata.colorSpace)
                            if let camera = session.photo.metadata.camera {
                                Text(camera.trimmingCharacters(in: .whitespaces))
                            }
                            if let exposure = session.photo.metadata.exposure { Text(exposure) }
                        }.font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.frame(maxWidth: 155, alignment: .trailing)
        }.padding(.horizontal, 16).padding(.top, 6)
            .sheet(isPresented: $showDetails) {
                NavigationStack {
                    Form {
                        LabeledContent("Film", value: filmName)
                        LabeledContent("Print", value: printName)
                        LabeledContent("Format", value: session.photo.metadata.format)
                        LabeledContent(
                            "Dimensions", value: "\(session.photo.width) × \(session.photo.height)")
                        LabeledContent("Color", value: session.photo.metadata.colorSpace)
                        if let camera = session.photo.metadata.camera {
                            LabeledContent("Camera", value: camera)
                        }
                        if let exposure = session.photo.metadata.exposure {
                            LabeledContent("Exposure", value: exposure)
                        }
                    }.navigationTitle("Photo details").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showDetails = false }
                            }
                        }
                }
            }
    }
    private var histogramButton: some View {
        Button {
            channels.toggle()
        } label: {
            HistogramChart(
                histogram: showingOriginal ? session.originalHistogram : session.histogram, channels: channels
            )
            .frame(width: 104, height: 44)
            .overlay(alignment: .topTrailing) {
                Text(channels ? "RGB" : "Luma").font(.system(size: 8)).padding(3)
            }.background(.primary.opacity(0.04), in: .rect(cornerRadius: 6))
        }.buttonStyle(.plain).accessibilityLabel(channels ? "RGB histogram" : "Brightness histogram")
            .accessibilityHint("Switch brightness and merged RGB channels")
            .accessibilityIdentifier("editor.histogram")
    }
}

private struct HistogramChart: View {
    let histogram: PhotoHistogram
    let channels: Bool
    var body: some View {
        Canvas { context, size in
            let series: [([UInt], Color)] =
                channels
                ? [(histogram.red, .red), (histogram.green, .green), (histogram.blue, .blue)]
                : [(histogram.brightness, .primary)]
            let maximum = max(series.map { $0.0.max() ?? 0 }.max() ?? 0, 1)
            for (bins, color) in series {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for i in bins.indices {
                    path.addLine(
                        to: CGPoint(
                            x: CGFloat(i) / 255 * size.width,
                            y: size.height * (1 - CGFloat(bins[i]) / CGFloat(maximum))))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(color.opacity(channels ? 0.35 : 0.45)))
            }
        }.accessibilityHidden(true)
    }
}

/// UIScrollView supplies native pinch, pan and bounce; a standard double-tap toggles fit/zoom.
struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> PhotoScrollView {
        let view = PhotoScrollView()
        view.delegate = context.coordinator
        view.photoView.isAccessibilityElement = true
        view.photoView.accessibilityLabel = "Edited photo"
        view.photoView.accessibilityTraits = .image
        view.photoView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Zoom in") { [weak view] _ in
                guard let view else { return false }
                view.setZoomScale(min(view.zoomScale * 2, view.maximumZoomScale), animated: true)
                return true
            },
            UIAccessibilityCustomAction(name: "Fit photo") { [weak view] _ in
                guard let view else { return false }
                view.setZoomScale(view.minimumZoomScale, animated: true)
                return true
            },
        ]
        view.accessibilityIdentifier = "editor.photo"
        view.contentInsetAdjustmentBehavior = .never
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.bouncesZoom = true
        view.addSubview(view.photoView)
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ view: PhotoScrollView, context: Context) { view.setPhoto(image) }
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleUIView(_ view: PhotoScrollView, coordinator: Coordinator) {
        view.delegate = nil
        view.photoView.image = nil
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? PhotoScrollView)?.photoView
        }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { (scrollView as? PhotoScrollView)?.centerPhoto() }
        @objc func doubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? PhotoScrollView else { return }
            if view.zoomScale > view.minimumZoomScale * 1.05 {
                view.setZoomScale(view.minimumZoomScale, animated: true)
            } else {
                let scale = min(view.minimumZoomScale * 2.5, view.maximumZoomScale)
                let point = recognizer.location(in: view.photoView)
                let rect = CGRect(
                    x: point.x - view.bounds.width / scale / 2,
                    y: point.y - view.bounds.height / scale / 2,
                    width: view.bounds.width / scale, height: view.bounds.height / scale)
                view.zoom(to: rect, animated: true)
            }
        }
    }
}

final class PhotoScrollView: UIScrollView {
    let photoView = UIImageView()
    private var imageSize = CGSize.zero
    private var lastBounds = CGSize.zero
    func setPhoto(_ image: UIImage) {
        guard photoView.image !== image else { return }
        photoView.image = image
        if image.size != imageSize {
            imageSize = image.size
            zoomScale = 1
            photoView.frame = CGRect(origin: .zero, size: image.size)
            contentSize = image.size
            lastBounds = .zero
            setNeedsLayout()
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, imageSize.width > 0, imageSize.height > 0 else { return }
        if lastBounds != bounds.size {
            let relative = lastBounds == .zero ? 1 : zoomScale / max(minimumZoomScale, 1e-6)
            let fit = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
            lastBounds = bounds.size
            minimumZoomScale = fit
            maximumZoomScale = max(fit * 8, 1)
            setZoomScale(min(max(fit * relative, fit), maximumZoomScale), animated: false)
        }
        centerPhoto()
    }
    func centerPhoto() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != insets { contentInset = insets }
        photoView.accessibilityValue = String(
            format: "%.0f percent zoom", zoomScale / max(minimumZoomScale, 1e-6) * 100)
    }
}
