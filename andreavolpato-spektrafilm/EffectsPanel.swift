import SwiftUI

struct EffectsPanel: View {
    let session: EditorSession
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EffectSection(
                title: "Grain", prefix: "film_render.grain", prominent: ["particle_area_um2", "blur"],
                session: session)
            Button("Use Stock Grain", systemImage: "arrow.counterclockwise", action: session.resetGrain)
                .accessibilityIdentifier("grain.stockDefaults")
            EffectSection(
                title: "Halation & scatter", prefix: "film_render.halation",
                prominent: ["halation_amount", "scatter_amount"], session: session)
            EffectSection(
                title: "Camera diffusion", prefix: "camera.diffusion_filter",
                prominent: ["filter_family", "strength"], session: session)
            EffectSection(
                title: "Enlarger diffusion", prefix: "enlarger.diffusion_filter",
                prominent: ["filter_family", "strength"], session: session, printOnly: true)
            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 18) {
                    EffectSection(
                        title: "Dye couplers", prefix: "film_render.dir_couplers", prominent: ["amount"],
                        session: session)
                    EffectSection(
                        title: "Print glare", prefix: "print_render.glare", prominent: ["percent"],
                        session: session, printOnly: true)
                    DisclosureGroup("Optics & scan") {
                        VStack(alignment: .leading, spacing: 16) {
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
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
