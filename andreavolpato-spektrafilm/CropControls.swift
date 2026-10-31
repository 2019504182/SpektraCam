import SwiftUI

/// Contextual crop controls sit above the persistent system toolbar.
struct CropControls: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var crop: CropSelection
    @Binding var geometry: ImageGeometry
    let imageAspect: CGFloat
    let rotateLeft: () -> Void
    let flipHorizontal: () -> Void
    let flipVertical: () -> Void
    var onStraightenEditingChanged: (Bool) -> Void = { _ in }

    private let common: [CropAspect] = [
        .original, .square, .fourThree, .threeTwo, .sixteenNine, .cinemaFlat, .cinemaScope,
    ]

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                ScrollView { controls }
                    .frame(height: 280)
                    .clipped()
            } else {
                controls
            }
        }.background(.background)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(common) { aspect in
                            Button(aspect.title) { crop.setAspect(aspect, imageAspect: imageAspect) }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .tint(crop.aspect == aspect ? Color.accentColor : .secondary)
                                .accessibilityAddTraits(crop.aspect == aspect ? .isSelected : [])
                                .accessibilityIdentifier("crop.ratio.\(aspect.id)")
                        }
                    }
                }.scrollIndicators(.hidden)
                Menu("More", systemImage: "ellipsis") {
                    ForEach(CropAspect.allCases.filter { !common.contains($0) }) { aspect in
                        Button(aspect.title) { crop.setAspect(aspect, imageAspect: imageAspect) }
                    }
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("More Aspect Ratios")
                .accessibilityIdentifier("crop.moreRatios")
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    transformButtons
                    Spacer()
                    orientationButtons
                }
                VStack(spacing: 8) {
                    HStack { transformButtons }
                    HStack { orientationButtons }
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            VStack(spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("Straighten")
                        Spacer()
                        straightenValue
                    }
                    VStack(alignment: .leading) {
                        Text("Straighten")
                        straightenValue
                    }
                }.font(.subheadline)
                Slider(
                    value: $geometry.straightenDegrees, in: -45...45, step: 0.1,
                    onEditingChanged: onStraightenEditingChanged
                )
                .accessibilityLabel("Straighten")
                .accessibilityValue(
                    geometry.straightenDegrees.formatted(.number.precision(.fractionLength(1)))
                        + " degrees"
                )
                .accessibilityIdentifier("crop.straighten")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var transformButtons: some View {
        Group {
            transform("Rotate Left", symbol: "rotate.left", action: rotateLeft)
            transform(
                "Flip Horizontal", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                action: flipHorizontal)
            transform(
                "Flip Vertical", symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                action: flipVertical)
        }
    }
    private func transform(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 32, height: 32) }
            .accessibilityLabel(title).buttonBorderShape(.circle)
    }

    private var orientationButtons: some View {
        Group {
            Button("Portrait", systemImage: "rectangle.portrait") {
                crop.setOrientation(.portrait, imageAspect: imageAspect)
            }
            .tint(crop.orientation == .portrait ? Color.accentColor : .secondary)
            .accessibilityAddTraits(crop.orientation == .portrait ? .isSelected : [])
            .accessibilityIdentifier("crop.portrait")
            Button("Landscape", systemImage: "rectangle") {
                crop.setOrientation(.landscape, imageAspect: imageAspect)
            }
            .tint(crop.orientation == .landscape ? Color.accentColor : .secondary)
            .accessibilityAddTraits(crop.orientation == .landscape ? .isSelected : [])
            .accessibilityIdentifier("crop.landscape")
        }.labelStyle(.titleAndIcon)
    }

    private var straightenValue: some View {
        Button(geometry.straightenDegrees.formatted(.number.precision(.fractionLength(1))) + "°") {
            geometry.straightenDegrees = 0
        }
        .monospacedDigit()
        .accessibilityLabel("Reset Straightening")
    }
}
