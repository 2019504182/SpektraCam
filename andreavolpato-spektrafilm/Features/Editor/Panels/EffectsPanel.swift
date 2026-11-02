import SwiftUI

struct EffectsPanel: View {
    enum Section: String, CaseIterable {
        case grain, halation, diffusion
        var title: String { rawValue.capitalized }
    }
    let session: EditorSession
    var section: Section = .grain
    @State private var confirmStockGrain = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch section {
            case .grain:
                EffectSection(
                    title: "Grain", prefix: "film_render.grain",
                    prominent: ["particle_area_um2", "blur"], session: session, showsDetails: false)
                AdaptiveToggle("B&W Grain", isOn: session.binding(\.monochromeGrain, key: "grain.monochrome"))
                    .disabled(!session.recipe.flag("film_render.grain.active"))
                    .accessibilityIdentifier("grain.monochrome")
                Button("Use Stock Grain", systemImage: "arrow.counterclockwise") { confirmStockGrain = true }
                    .buttonStyle(.glass).controlSize(.small).accessibilityIdentifier("grain.stockDefaults")
                    .confirmationDialog(
                        "Use stock grain settings?", isPresented: $confirmStockGrain,
                        titleVisibility: .visible
                    ) {
                        Button("Use Stock Grain", action: session.resetGrain)
                    }
                EffectDetails(
                    prefix: "film_render.grain", prominent: ["particle_area_um2", "blur"], session: session)
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
                Text("Diffusion can require substantial memory during full-size export.").font(.caption)
                    .foregroundStyle(.secondary)
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
