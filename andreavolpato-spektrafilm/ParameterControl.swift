import SwiftUI

/// Native sliders offer a compact range; numeric entry preserves wider model limits.
struct ParameterControl: View {
    let definition: ParameterDefinition
    let session: EditorSession

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
                    get: { session.recipe.number(definition.id) },
                    set: { value in session.update(key: definition.id) { $0.numbers[definition.id] = value } }
                ),
                range: definition.sliderRange, step: definition.step,
                minimum: definition.minimum, maximum: definition.maximum,
                unit: definition.unit, identifier: definition.id,
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
            Slider(value: $value, in: effectiveRange, step: step, onEditingChanged: onEditingChanged)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
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
        }
        .accessibilityLabel("Enter \(title)")
        .accessibilityValue(value.formatted() + " " + unit)
        .accessibilityIdentifier(identifier + ".value")
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
                        .buttonStyle(.borderless)
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
