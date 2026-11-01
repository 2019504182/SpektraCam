import SwiftUI
import UIKit

/// Native sliders offer a compact range; numeric entry preserves wider model limits.
struct ParameterControl: View {
    let definition: ParameterDefinition
    let session: EditorSession
    private var boundedScatter: Bool {
        session.recipe.look.mode == .lut && definition.id == "film_render.halation.scatter_amount"
    }

    var body: some View {
        if definition.defaultFlag != nil {
            Toggle(
                isOn: Binding(
                    get: { session.recipe.flag(definition.id) },
                    set: { value in session.update(key: definition.id) { $0.flags[definition.id] = value } })
            ) { Text(definition.title).fixedSize(horizontal: false, vertical: true) }
            .toggleStyle(.switch)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(definition.id)
        } else if definition.defaultChoice != nil {
            Picker(
                definition.title,
                selection: Binding(
                    get: { session.recipe.choice(definition.id) },
                    set: { value in session.update(key: definition.id) { $0.choices[definition.id] = value } }
                )
            ) {
                ForEach(definition.options, id: \.self) {
                    Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(definition.id)
        } else {
            NumericControl(
                title: definition.title,
                value: Binding(
                    get: {
                        let value = session.recipe.number(definition.id)
                        return boundedScatter ? min(max(value, 0), 1) : value
                    },
                    set: { value in session.update(key: definition.id) { $0.numbers[definition.id] = value } }
                ),
                range: boundedScatter ? 0...1 : definition.sliderRange, step: definition.step,
                minimum: definition.minimum, maximum: boundedScatter ? 1 : definition.maximum,
                unit: definition.unit, identifier: definition.id,
                defaultValue: session.recipe.defaultNumber(definition.id),
                onEditingChanged: { session.setInteraction(key: definition.id, active: $0) })
        }
    }
}

struct NumericControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step = 0.01
    var minimum: Double?
    var maximum: Double?
    var unit = ""
    var identifier = ""
    var defaultValue = 0.0
    var fillOrigin: Double? = nil
    var snapsToDefault = true
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var showEntry = false

    private var effectiveRange: ClosedRange<Double> {
        min(value, range.lowerBound)...max(value, range.upperBound)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(title)
                    Spacer(minLength: 8)
                    valueButton
                }
                VStack(alignment: .leading) {
                    Text(title)
                    valueButton
                }
            }
            DefaultSlider(
                value: $value, range: effectiveRange, step: step, defaultValue: defaultValue,
                title: title, identifier: identifier, fillOrigin: fillOrigin, snapsToDefault: snapsToDefault,
                onEditingChanged: onEditingChanged)
        }
        .sheet(isPresented: $showEntry) {
            NumericEntry(
                title: title, value: $value, minimum: minimum, maximum: maximum,
                integer: step == 1, unit: unit)
        }
    }
    private var valueButton: some View {
        Button {
            showEntry = true
        } label: {
            Text(
                value.formatted(.number.precision(.fractionLength(0...(unit == "K" ? 0 : 3))))
                    + (unit.isEmpty ? "" : " " + unit)
            )
            .monospacedDigit()
            .fixedSize()
            .foregroundStyle(Color.primary)
        }
        .accessibilityLabel("Enter \(title)")
        .accessibilityValue(value.formatted() + " " + unit)
        .accessibilityIdentifier(identifier + ".value")
    }
}

/// Native continuous track with one default tick. Reset also has a VoiceOver action.
struct DefaultSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step = 0.01
    var defaultValue = 0.0
    let title: String
    let identifier: String
    var fillOrigin: Double? = nil
    var snapsToDefault = true
    var onEditingChanged: (Bool) -> Void = { _ in }
    private var bounds: ClosedRange<Double> {
        min(range.lowerBound, defaultValue)...max(range.upperBound, defaultValue)
    }
    private func position(_ number: Double) -> Float {
        Float((number - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound))
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UISlider {
        let slider = PrecisionSlider()
        context.coordinator.slider = slider
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.began), for: .touchDown)
        slider.addTarget(
            context.coordinator, action: #selector(Coordinator.ended),
            for: [.touchUpInside, .touchUpOutside, .touchCancel])
        let reset = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.reset))
        reset.numberOfTapsRequired = 2
        reset.cancelsTouchesInView = false
        reset.delaysTouchesEnded = false
        reset.delegate = context.coordinator
        slider.addGestureRecognizer(reset)
        slider.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "Reset to Default", target: context.coordinator,
                selector: #selector(Coordinator.accessibleReset))
        ]
        return slider
    }
    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.parent = self
        slider.isEnabled = context.environment.isEnabled
        slider.isUserInteractionEnabled = context.environment.isEnabled
        slider.accessibilityLabel = title
        slider.accessibilityIdentifier = identifier
        slider.tintColor = UIColor(Color.accentColor)
        // Keep UIKit and its tick configuration in the same normalized range.
        let configuration = [
            bounds.lowerBound, bounds.upperBound, defaultValue, fillOrigin ?? defaultValue,
            snapsToDefault ? 1 : 0,
        ]
        if context.coordinator.configuration != configuration {
            slider.trackConfiguration =
                snapsToDefault
                ? .init(
                    allowsTickValuesOnly: false, neutralValue: position(fillOrigin ?? defaultValue),
                    ticks: [.init(position: position(defaultValue))]) : nil
            if let precise = slider as? PrecisionSlider {
                precise.defaultTick = snapsToDefault ? nil : position(defaultValue)
            }
            context.coordinator.configuration = configuration
        }
        if !slider.isTracking { slider.setValue(position(value), animated: false) }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISlider, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 100, height: 32)
    }
    /// UIKit couples configured ticks to magnetic stops. A marker view keeps fine straightening continuous.
    final class PrecisionSlider: UISlider {
        var defaultTick: Float? { didSet { setNeedsLayout() } }
        private let marker = UIView()
        override init(frame: CGRect) {
            super.init(frame: frame)
            marker.backgroundColor = .tertiaryLabel
            marker.isUserInteractionEnabled = false
            marker.isAccessibilityElement = false
            addSubview(marker)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            marker.isHidden = defaultTick == nil
            if let value = defaultTick {
                let track = trackRect(forBounds: bounds)
                let thumb = thumbRect(forBounds: bounds, trackRect: track, value: value)
                marker.frame = CGRect(x: thumb.midX - 0.5, y: track.midY - 3, width: 1, height: 6)
            }
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: DefaultSlider
        var configuration: [Double] = []
        weak var slider: UISlider?
        private let feedback = UISelectionFeedbackGenerator()
        private var interacting = false
        init(_ parent: DefaultSlider) { self.parent = parent }
        @objc func began() {
            interacting = true
            parent.onEditingChanged(true)
        }
        @objc func ended() {
            interacting = false
            parent.onEditingChanged(false)
        }
        @objc func changed(_ slider: UISlider) {
            let accessibilityChange = !interacting && !slider.isTracking
            if accessibilityChange { began() }
            let raw =
                parent.bounds.lowerBound + Double(slider.value)
                * (parent.bounds.upperBound - parent.bounds.lowerBound)
            parent.value = min(
                max((raw / parent.step).rounded() * parent.step, parent.bounds.lowerBound),
                parent.bounds.upperBound)
            if accessibilityChange { ended() }
        }
        @objc func reset() {
            guard slider?.isEnabled == true else { return }
            began()
            parent.value = parent.defaultValue
            slider?.setValue(parent.position(parent.defaultValue), animated: false)
            ended()
            feedback.selectionChanged()
        }
        @objc func accessibleReset() -> Bool {
            reset()
            return true
        }
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
    }
}

private struct NumericEntry: View {
    let title: String
    @Binding var value: Double
    var minimum: Double?
    var maximum: Double?
    let integer: Bool
    let unit: String
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var parsed: Double? {
        let separator = Locale.current.decimalSeparator ?? "."
        guard let number = Double(text.replacingOccurrences(of: separator, with: ".")), number.isFinite,
            minimum.map({ number >= $0 }) ?? true,
            maximum.map({ number <= $0 }) ?? true,
            !integer || number.rounded() == number
        else { return nil }
        return number
    }
    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    if (minimum ?? -1) < 0 {
                        Button("Change Sign", systemImage: "plusminus") {
                            text = text.hasPrefix("-") ? String(text.dropFirst()) : "-" + text
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                    }
                    TextField(title, text: $text)
                        .keyboardType(integer ? .numberPad : .decimalPad)
                        .focused($isFocused)
                        .accessibilityLabel(title)
                        .accessibilityIdentifier("numeric.input")
                    Text(unit).foregroundStyle(.secondary)
                }
                if parsed == nil {
                    Text(
                        "Enter a valid \(integer ? "whole " : "")number\(minimum.map { " from " + $0.formatted() } ?? "")\(maximum.map { " to " + $0.formatted() } ?? "")."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let parsed {
                            value = parsed
                            dismiss()
                        }
                    }.disabled(parsed == nil)
                }
            }
            .onAppear {
                text = value.formatted(.number.grouping(.never))
                isFocused = true
            }
        }
        .presentationDetents([.medium])
    }
}

/// Native field layout shared by Adjust and Effects; labels wrap within the proposed width.
struct ParameterFields: View {
    let session: EditorSession
    let prefix: String
    var names: [String]?
    var excluding: [String] = []
    var body: some View {
        ForEach(
            (ParameterDefinition.byGroup[prefix] ?? []).filter {
                (names == nil || names!.contains($0.fieldName)) && !excluding.contains($0.fieldName)
            }
        ) { definition in ParameterControl(definition: definition, session: session) }
    }
}

struct EffectSection: View {
    let title: String
    let prefix: String
    let prominent: [String]
    let session: EditorSession
    var printOnly = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                isOn: Binding(
                    get: { session.recipe.flag(prefix + ".active") },
                    set: { value in session.update(key: prefix) { $0.flags[prefix + ".active"] = value } })
            ) {
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.switch).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(prefix + ".active")
            VStack(alignment: .leading, spacing: 12) {
                ParameterFields(session: session, prefix: prefix, names: prominent)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 16) {
                        ParameterFields(session: session, prefix: prefix, excluding: ["active"] + prominent)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                } label: {
                    Text("Details").accessibilityIdentifier(prefix + ".details")
                }
            }.disabled(!session.recipe.flag(prefix + ".active"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(printOnly && session.recipe.bypassesPrint)
    }
}
