import SwiftUI

struct EditorInfoBar: View {
    let session: EditorSession
    let showingOriginal: Bool
    var location: String? = nil
    var onInteraction: (() -> Void)? = nil
    private var filmName: String { FilmStock.films.first { $0.id == session.recipe.filmID }?.name ?? "Film" }
    private var printName: String {
        session.recipe.bypassesPrint
            ? "Direct scan"
            : FilmStock.prints.first { $0.id == session.recipe.printID }?.name ?? "Print"
    }
    var body: some View {
        PhotoInfoPanel(
            title: filmName, subtitle: printName, metadata: session.photo.metadata,
            location: location, histogram: showingOriginal ? session.originalHistogram : session.histogram,
            identifier: "editor", onInteraction: onInteraction)
    }
}
