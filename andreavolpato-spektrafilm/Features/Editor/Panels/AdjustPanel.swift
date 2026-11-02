import SwiftUI

/// RAW adjustments precede Develop. Whole-photo monochrome follows the selected look.
struct AdjustPanel: View {
    enum Section: String, CaseIterable {
        case exposure, liftGain, color
        var title: String {
            switch self {
            case .exposure: "Exposure & Contrast"
            case .liftGain: "Lift/Gain"
            case .color: "Color"
            }
        }
    }
    let session: EditorSession
    var section: Section = .exposure
    @State private var extendedBalance = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch section {
            case .exposure:
                NumericControl(
                    title: "Exposure",
                    value: Binding(
                        get: { session.recipe.tone.exposureEV },
                        set: { value in
                            session.update(key: "tone.exposure") { $0.tone.exposureEV = value }
                        }),
                    range: -5...5, step: 0.05, minimum: -10, maximum: 10, unit: "EV",
                    identifier: "tone.exposure",
                    onEditingChanged: { session.setInteraction(key: "tone.exposure", active: $0) })
                field("camera.exposure_compensation_ev").disabled(session.recipe.look.mode == .lut)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 16) {
                        field("camera.auto_exposure")
                        if session.recipe.flag("camera.auto_exposure") {
                            field("camera.auto_exposure_method")
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            NumericControl(
                                title: "Print exposure",
                                value: session.binding(
                                    \.printExposureEV, key: "enlarger.print_exposure"),
                                range: -3...3, step: 0.05, minimum: -10, maximum: 10, unit: "EV",
                                identifier: "enlarger.print_exposure",
                                onEditingChanged: {
                                    session.setInteraction(
                                        key: "enlarger.print_exposure", active: $0)
                                })
                            DisclosureGroup("Calibration") {
                                NumericControl(
                                    title: "Input exposure",
                                    value: sourceBinding(\.exposureEV, key: "source.exposure"),
                                    range: -5...5,
                                    step: 0.05, minimum: -10, maximum: 10, unit: "EV",
                                    identifier: "source.exposure")
                                field("enlarger.normalize_print_exposure").padding(.top, 8)
                            }
                        }.disabled(session.recipe.bypassesPrint || session.recipe.look.mode == .lut)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                } label: {
                    Text("Print exposure & metering").foregroundStyle(Color.accentColor)
                        .accessibilityIdentifier(
                            "adjust.exposureStages")
                }
                .disabled(session.recipe.look.mode == .lut)
                Divider()
                toneControl(
                    "S-curve", path: \.contrast, range: -0.35...0.35, defaultValue: 0,
                    id: "contrast")
                toneControl("Pivot", path: \.pivot, range: 0...1, defaultValue: 0.35, id: "pivot")
            case .liftGain:
                toneControl(
                    "Highlights", path: \.highlights, range: -2...2, defaultValue: 0,
                    id: "highlights")
                toneControl(
                    "Shadows", path: \.shadows, range: -2...2, defaultValue: 0, id: "shadows")
            case .color:
                if let temperature = session.recipe.temperature {
                    NumericControl(
                        title: "Temperature",
                        value: Binding(
                            get: { session.recipe.temperature ?? temperature },
                            set: { value in
                                session.update(key: "temperature") { $0.temperature = value }
                            }),
                        range: 2500...8000, step: 25, minimum: 1000, maximum: 50000, unit: "K",
                        identifier: "source.temperature",
                        defaultValue: session.photo.rawTemperature ?? temperature,
                        onEditingChanged: { session.setInteraction(key: "temperature", active: $0) }
                    )
                } else {
                    NumericControl(
                        title: "Warmth", value: sourceBinding(\.warmth, key: "source.warmth"),
                        range: -50...50, step: 1, minimum: -100, maximum: 100,
                        identifier: "source.warmth",
                        onEditingChanged: {
                            session.setInteraction(key: "source.warmth", active: $0)
                        })
                }
                NumericControl(
                    title: "Tint", value: sourceBinding(\.tint, key: "source.tint"),
                    range: -50...50, step: 1, minimum: -100, maximum: 100,
                    identifier: "source.tint",
                    onEditingChanged: { session.setInteraction(key: "source.tint", active: $0) })
                NumericControl(
                    title: "Saturation",
                    value: Binding(
                        get: { session.recipe.source.saturation * 100 },
                        set: { value in
                            session.update(key: "source.saturation") {
                                $0.source.saturation = value / 100
                            }
                        }),
                    range: 0...200, step: 1, minimum: 0, maximum: 200, unit: "%",
                    identifier: "source.saturation", defaultValue: 100,
                    onEditingChanged: {
                        session.setInteraction(key: "source.saturation", active: $0)
                    })
                AdaptiveToggle(
                    "Black & White",
                    isOn: Binding(
                        get: { session.recipe.tone.monochrome },
                        set: { value in
                            session.update(key: "tone.monochrome") { $0.tone.monochrome = value }
                        })
                )
                .accessibilityIdentifier("tone.monochrome")
                DisclosureGroup("Dye couplers") {
                    EffectSection(
                        title: "Dye couplers", prefix: "film_render.dir_couplers",
                        prominent: ["amount"],
                        session: session
                    ).padding(.top, 8)
                }.disabled(session.recipe.look.mode == .lut)
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 12) {
                        ParameterFields(session: session, prefix: "scanner")
                        ParameterFields(
                            session: session, prefix: "enlarger",
                            names: [
                                "preflash_exposure", "preflash_y_filter_shift",
                                "preflash_m_filter_shift",
                            ]
                        ).disabled(session.recipe.bypassesPrint)
                        ParameterFields(
                            session: session, prefix: "film_render", names: ["density_curve_gamma"])
                        ParameterFields(
                            session: session, prefix: "camera",
                            names: ["lens_blur_um", "film_format_mm", "filter_uv", "filter_ir"])
                    }.padding(.top, 8)
                }
                .disabled(session.recipe.look.mode == .lut)
                DisclosureGroup("Print balance") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Color balance").font(.subheadline.weight(.semibold))
                            Spacer()
                            Button(extendedBalance ? "±100 CC" : "±35 CC") {
                                extendedBalance.toggle()
                            }
                            .font(.caption).accessibilityLabel("Change color balance range")
                            .accessibilityIdentifier("adjust.balanceRange")
                        }
                        balance("enlarger.y_filter_shift", title: "Yellow balance")
                        balance("enlarger.m_filter_shift", title: "Magenta balance")
                        DisclosureGroup("Print contrast") {
                            EffectSection(
                                title: "Print chemistry",
                                prefix: "print_render.density_curves_morph",
                                prominent: ["gamma_factor"], session: session, printOnly: true
                            ).padding(.top, 12)
                        }
                    }.disabled(session.recipe.bypassesPrint || session.recipe.look.mode == .lut)
                    if session.recipe.bypassesPrint {
                        Text("Direct scan skips print controls.").font(.caption).foregroundStyle(
                            .secondary)
                    }
                }.disabled(session.recipe.bypassesPrint || session.recipe.look.mode == .lut)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func toneControl(
        _ title: String, path: WritableKeyPath<EditRecipe.Tone, Double>, range: ClosedRange<Double>,
        defaultValue: Double, id: String
    ) -> some View {
        NumericControl(
            title: title,
            value: Binding(
                get: { session.recipe.tone[keyPath: path] - (id == "contrast" ? 1 : 0) },
                set: { value in
                    session.update(key: "tone." + id) {
                        $0.tone.algorithm = 5
                        $0.tone[keyPath: path] =
                            id == "contrast" ? min(max(value, -0.35), 0.35) + 1 : value
                    }
                }),
            range: range, step: 0.01, minimum: range.lowerBound, maximum: range.upperBound,
            identifier: "tone." + id, defaultValue: defaultValue,
            onEditingChanged: { session.setInteraction(key: "tone." + id, active: $0) })
    }
    private func sourceBinding(_ path: WritableKeyPath<EditRecipe.Source, Double>, key: String)
        -> Binding<
            Double
        >
    {
        Binding(
            get: { session.recipe.source[keyPath: path] },
            set: { value in session.update(key: key) { $0.source[keyPath: path] = value } })
    }
    private func balance(_ path: String, title: String) -> some View {
        NumericControl(
            title: title,
            value: Binding(
                get: { session.recipe.number(path) },
                set: { value in
                    session.update(key: path) { $0.numbers[path] = value }
                    if abs(value) > 35 { extendedBalance = true }
                }),
            range: extendedBalance ? -100...100 : -35...35, step: 0.25, minimum: -200, maximum: 200,
            unit: "CC", identifier: path,
            onEditingChanged: { session.setInteraction(key: path, active: $0) })
    }
    @ViewBuilder private func field(_ path: String) -> some View {
        if let definition = ParameterDefinition.byPath[path] {
            ParameterControl(definition: definition, session: session)
        }
    }
}
