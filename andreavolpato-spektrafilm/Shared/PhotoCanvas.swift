import SwiftUI
import UIKit

/// Neutral surround keeps the controls' accent out of the photograph.
enum PhotoTheme {
    static let canvas = Color(
        uiColor: UIColor { traits in
            UIColor(white: traits.userInterfaceStyle == .dark ? 0.16 : 0.94, alpha: 1)
        })
}

/// UIScrollView supplies native pinch, pan and bounce; a standard double-tap toggles fit/zoom.
struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    var topAligned = false
    var label = "Edited photo"
    var onTap: ((CGPoint) -> Void)?
    func makeUIView(context: Context) -> PhotoScrollView {
        let view = PhotoScrollView()
        view.delegate = context.coordinator
        context.coordinator.onTap = onTap
        view.photoView.isAccessibilityElement = true
        view.photoView.accessibilityLabel = label
        view.topAligned = topAligned
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
        let single = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.singleTap))
        single.require(toFail: tap)
        view.addGestureRecognizer(single)
        return view
    }
    func updateUIView(_ view: PhotoScrollView, context: Context) {
        context.coordinator.onTap = onTap
        view.topAligned = topAligned
        view.photoView.accessibilityLabel = label
        view.setPhoto(image)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleUIView(_ view: PhotoScrollView, coordinator: Coordinator) {
        view.delegate = nil
        coordinator.onTap = nil
        view.photoView.image = nil
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onTap: ((CGPoint) -> Void)?
        @objc func singleTap(_ recognizer: UITapGestureRecognizer) {
            onTap?(recognizer.location(in: recognizer.view?.window))
        }
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
    var topAligned = false
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
        let vertical = topAligned ? 0 : max(0, (bounds.height - contentSize.height) / 2)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != insets { contentInset = insets }
        photoView.accessibilityValue = String(
            format: "%.0f percent zoom", zoomScale / max(minimumZoomScale, 1e-6) * 100)
    }
}

/// The summary's collapsed edge is the same for every photo, even while details expand.
struct PhotoViewport: View {
    let image: UIImage
    var topInset: CGFloat = PhotoInfoPanel.collapsedHeight + 12
    var edited = true
    var topAligned = true
    var onTap: ((CGPoint) -> Void)?
    var body: some View {
        GeometryReader { proxy in
            ZoomablePhoto(
                image: image, topAligned: topAligned, label: edited ? "Edited photo" : "Photo", onTap: onTap
            )
            .frame(width: proxy.size.width, height: max(1, proxy.size.height - topInset)).offset(y: topInset)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading).clipped()
        }
    }
}
