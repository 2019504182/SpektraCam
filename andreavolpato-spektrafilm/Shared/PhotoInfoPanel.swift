import SwiftUI

/// One fixed summary height. Expanded details overlay the photo without moving it.
struct PhotoInfoPanel: View {
    static let collapsedHeight: CGFloat = 64
    let title: String
    let subtitle: String
    let metadata: PhotoMetadata
    let location: String?
    let histogram: PhotoHistogram
    let identifier: String
    var onInteraction: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var channels = false
    @State private var detailsHeight: CGFloat = 180
    @Namespace private var glass

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                Button(action: toggleDetails) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.caption.weight(.semibold))
                            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                        }.lineLimit(1).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        Spacer(minLength: 0)
                        Color.clear.frame(width: 112, height: 36)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: Self.collapsedHeight).contentShape(.rect)
                    .overlay(alignment: .bottom) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.bottom, 3).accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain).accessibilityIdentifier(identifier + ".info")
                .accessibilityLabel("Photo information. " + title + ", " + subtitle)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                Button {
                    channels.toggle()
                    onInteraction?()
                } label: {
                    VStack(spacing: 3) {
                        HistogramChart(histogram: histogram, channels: channels).frame(width: 112, height: 32)
                            .overlay { Rectangle().strokeBorder(.secondary, lineWidth: 0.5) }
                        Text(channels ? "RGB" : "Luma").font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                    }.frame(width: 112, height: 44).contentShape(.rect)
                }
                .buttonStyle(.plain).padding(.trailing, 12)
                .accessibilityLabel(channels ? "RGB histogram" : "Brightness histogram")
                .accessibilityHint("Switch brightness and RGB channels")
                .accessibilityIdentifier(identifier + ".histogram")
            }
            if expanded {
                ScrollView {
                    VStack(spacing: 8) {
                        Divider()
                        LabeledContent("Location", value: location ?? "Not available")
                        if let date = metadata.capturedAt {
                            LabeledContent(
                                "Taken", value: date.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let camera = metadata.camera {
                            LabeledContent("Camera", value: camera.trimmingCharacters(in: .whitespaces))
                        }
                        if let lens = metadata.lens { LabeledContent("Lens", value: lens) }
                        if let exposure = metadata.exposure { LabeledContent("Exposure", value: exposure) }
                        LabeledContent("Format", value: metadata.sizeLine)
                        LabeledContent("Color space", value: metadata.colorSpace)
                    }.font(.subheadline).padding(.horizontal, 12).padding(.bottom, 12)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            detailsHeight = $0
                        }
                }
                .frame(height: min(detailsHeight, 180))
                .contentShape(.rect).onTapGesture(perform: toggleDetails)
                .accessibilityIdentifier(identifier + ".details")
                .transition(.opacity)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .glassEffectID("information", in: glass)
    }
    private func toggleDetails() {
        onInteraction?()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { expanded.toggle() }
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
                context.fill(path, with: .color(color.opacity(channels ? 0.4 : 0.55)))
            }
        }.accessibilityHidden(true)
    }
}
