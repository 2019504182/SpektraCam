import SwiftUI
import UIKit

struct AppInformationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private var languageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: code).localizedString(forIdentifier: code) ?? code
    }
    var body: some View {
        NavigationStack {
            List {
                Section("SpektraCam") {
                    Text(
                        String(
                            localized: "about.free_and_open_source_all_editing_features",
                            defaultValue: "Free and open source. All editing features are free."))
                    LabeledContent(
                        String(localized: "about.version", defaultValue: "Version"),
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                            ?? "")
                }
                Section(String(localized: "about.authors", defaultValue: "Authors")) {
                    Link(
                        String(
                            localized: "about.andrea_volpato_spektrafilm",
                            defaultValue: "Andrea Volpato · Spektrafilm"),
                        destination: URL(string: "https://github.com/andreavolpato/spektrafilm")!)
                    Link(
                        String(localized: "about.runze_website", defaultValue: "Runze · Website"),
                        destination: URL(string: "https://runzeni.github.io/")!)
                    Link(
                        String(
                            localized: "about.spektracam_project",
                            defaultValue: "SpektraCam · Project"),
                        destination: URL(string: "https://github.com/runzeni/SpektraCam")!)
                }
                Section(String(localized: "about.settings", defaultValue: "Settings")) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        LabeledContent(
                            String(localized: "about.language", defaultValue: "Language"),
                            value: languageName)
                    }
                    .accessibilityIdentifier("about.language")
                    .accessibilityHint(
                        String(
                            localized: "about.language_settings_hint",
                            defaultValue: "Change the app language in iPhone Settings."))
                    LabeledContent(
                        String(localized: "about.preview", defaultValue: "Preview"),
                        value: "1080 px")
                    Text(
                        String(
                            localized: "about.export_uses_the_original_preview_quality_does",
                            defaultValue:
                                "Export uses the original. Preview quality does not reduce the stored photo."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    LabeledContent(
                        String(localized: "about.app_icon", defaultValue: "App icon"),
                        value: "SpektraCam")
                }
            }
            .navigationTitle(String(localized: "about.about", defaultValue: "About"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        String(localized: "common.done", defaultValue: "Done"), systemImage: "xmark"
                    ) { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
    }
}
