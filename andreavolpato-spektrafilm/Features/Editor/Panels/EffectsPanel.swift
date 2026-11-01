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
                .disabled(session.recipe.look.mode == .lut)
            case .diffusion:
                EffectSection(
                    title: "Camera diffusion", prefix: "camera.diffusion_filter",
                    prominent: ["filter_family", "strength"], session: session)
                EffectSection(
                    title: "Enlarger diffusion", prefix: "enlarger.diffusion_filter",
                    prominent: ["filter_family", "strength"], session: session, printOnly: true)

            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
