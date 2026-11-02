import SwiftUI

struct AppInformationView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("SpektraCam") {
                    Text("Free and open source. All editing features are free.")
                    LabeledContent(
                        "Version",
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                }
                Section("Authors") {
                    Link(
                        "Andrea Volpato · Spektrafilm",
                        destination: URL(string: "https://github.com/andreavolpato/spektrafilm")!)
                    Link("Runze · Website", destination: URL(string: "https://runzeni.github.io/")!)
                    Link(
                        "SpektraCam · Project",
                        destination: URL(string: "https://github.com/runzeni/SpektraCam")!)
                }
                Section("Settings") {
                    LabeledContent("Preview", value: "1080 px")
                    Text("Export uses the original. Preview quality does not reduce the stored photo.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("App icon", value: "SpektraCam")
                }
            }
            .navigationTitle("About").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
    }
}
