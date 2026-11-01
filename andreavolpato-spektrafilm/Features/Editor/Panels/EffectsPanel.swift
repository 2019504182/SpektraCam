import SwiftUI

struct EffectsPanel: View {
    enum Section: String, CaseIterable {
        case grain, halation, diffusion
        var title: String { rawValue.capitalized }
    }
    let session: EditorSession
    var section: Section = .grain
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch section {
            case .grain:
                EffectSection(
                    title: "Grain", prefix: "film_render.grain",
                    prominent: ["particle_area_um2", "blur"], session: session)
                Toggle("B&W Grain", isOn: session.binding(\.monochromeGrain, key: "grain.monochrome"))
                    .disabled(!session.recipe.flag("film_render.grain.active"))
                    .accessibilityIdentifier("grain.monochrome")
                Button("Use Stock Grain", systemImage: "arrow.counterclockwise", action: session.resetGrain)
                    .foregroundStyle(.primary).accessibilityIdentifier("grain.stockDefaults")
                DisclosureGroup("Dye couplers") {
                    EffectSection(
                        title: "Dye couplers", prefix: "film_render.dir_couplers",
                        prominent: ["amount"], session: session
                    ).padding(.top, 8)
                }
            case .halation:
                EffectSection(
                    title: "Halation & scatter", prefix: "film_render.halation",
                    prominent: ["halation_amount", "scatter_amount"], session: session)
                DisclosureGroup("Print glare") {
                    EffectSection(
                        title: "Print glare", prefix: "print_render.glare",
                        prominent: ["percent"], session: session, printOnly: true
                    ).padding(.top, 8)
                }
            case .diffusion:
                EffectSection(
                    title: "Camera diffusion", prefix: "camera.diffusion_filter",
                    prominent: ["filter_family", "strength"], session: session)
                EffectSection(
                    title: "Enlarger diffusion", prefix: "enlarger.diffusion_filter",
                    prominent: ["filter_family", "strength"], session: session, printOnly: true)
                DisclosureGroup("Optics & scan") {
                    VStack(alignment: .leading, spacing: 12) {
                        ParameterFields(
                            session: session, prefix: "camera",
                            names: ["lens_blur_um", "film_format_mm", "filter_uv", "filter_ir"])
                        ParameterFields(session: session, prefix: "scanner")
                        ParameterFields(
                            session: session, prefix: "enlarger",
                            names: [
                                "preflash_exposure", "preflash_y_filter_shift", "preflash_m_filter_shift",
                            ]
                        )
                        .disabled(session.recipe.bypassesPrint)
                        ParameterFields(
                            session: session, prefix: "film_render", names: ["density_curve_gamma"])
                    }.padding(.top, 8)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
