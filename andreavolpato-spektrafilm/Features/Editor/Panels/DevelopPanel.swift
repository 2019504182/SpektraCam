import SwiftUI

/// Two native browsing columns keep stock names visible and selections one tap away.
struct DevelopPanel: View {
    let session: EditorSession
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var filmCategory: FilmStock.Category
    @State private var printCategory: FilmStock.Category

    init(session: EditorSession) {
        self.session = session
        _filmCategory = State(
            initialValue: FilmStock.films.first { $0.id == session.recipe.filmID }?.category ?? .photoNegative
        )
        _printCategory = State(
            initialValue: FilmStock.prints.first { $0.id == session.recipe.printID }?.category ?? .photoPaper)
    }

    var body: some View {
        VStack(spacing: 12) {
            if typeSize.isAccessibilitySize {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        categoryControl(
                            "Film", categories: FilmStock.Category.films, selection: $filmCategory)
                        stockRows(
                            FilmStock.films, category: filmCategory, selected: session.recipe.filmID,
                            film: true)
                        categoryControl(
                            "Print", categories: FilmStock.Category.prints, selection: $printCategory
                        )
                        .disabled(session.recipe.bypassesPrint)
                        stockRows(
                            FilmStock.prints, category: printCategory, selected: session.recipe.printID,
                            film: false
                        )
                        .disabled(session.recipe.bypassesPrint)
                        scanControls
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    column(
                        "Film", categories: FilmStock.Category.films, selection: $filmCategory,
                        stocks: FilmStock.films, selected: session.recipe.filmID, film: true)
                    column(
                        "Print", categories: FilmStock.Category.prints, selection: $printCategory,
                        stocks: FilmStock.prints, selected: session.recipe.printID, film: false
                    )
                    .disabled(session.recipe.bypassesPrint)
                }
            }
            if !typeSize.isAccessibilitySize { scanControls }
        }
        .onChange(of: session.recipe.filmID) { _, id in
            if let category = FilmStock.films.first(where: { $0.id == id })?.category {
                filmCategory = category
            }
        }
        .onChange(of: session.recipe.printID) { _, id in
            if let category = FilmStock.prints.first(where: { $0.id == id })?.category {
                printCategory = category
            }
        }
    }

    private var scanControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            NumericControl(
                title: "Mix",
                value: Binding(
                    get: { session.recipe.mix * 100 },
                    set: { value in session.update(key: "mix") { $0.mix = value / 100 } }),
                range: 0...100, step: 1, minimum: 0, maximum: 100, unit: "%", identifier: "develop.mix",
                defaultValue: 100,
                onEditingChanged: { session.setInteraction(key: "mix", active: $0) })
            Toggle("Scan film directly", isOn: session.binding(\.scanFilm, key: "route"))
                .accessibilityIdentifier("develop.scanFilm")
            if session.recipe.bypassesPrint {
                Text("Direct scan · print settings are bypassed")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func categoryControl(
        _ title: String, categories: [FilmStock.Category], selection: Binding<FilmStock.Category>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Picker(title + " category", selection: selection) {
                ForEach(categories) { category in
                    Text(category.shortTitle).tag(category).accessibilityLabel(category.title)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("develop." + title.lowercased() + ".category")
            Text(selection.wrappedValue.title)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func column(
        _ title: String, categories: [FilmStock.Category], selection: Binding<FilmStock.Category>,
        stocks: [FilmStock], selected: String, film: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            categoryControl(title, categories: categories, selection: selection)
            ScrollViewReader { proxy in
                ScrollView {
                    stockRows(stocks, category: selection.wrappedValue, selected: selected, film: film)
                }
                .clipped()
                .onAppear { proxy.scrollTo(selected, anchor: .center) }

            }
            .id(selection.wrappedValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stockButton(_ stock: FilmStock, selected: Bool, film: Bool) -> some View {
        let button = Button {
            if film {
                session.selectFilm(stock)
            } else {
                session.update(key: "print") { $0.printID = stock.id }
            }
        } label: {
            HStack(spacing: 6) {
                Text(stock.compactName).font(.footnote)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor).frame(width: 16).opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .font(.subheadline).contentShape(Rectangle())
        }
        return button.buttonStyle(.plain)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 6)
            .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 12))
    }

    private func stockRows(_ stocks: [FilmStock], category: FilmStock.Category, selected: String, film: Bool)
        -> some View
    {
        GlassEffectContainer(spacing: 8) {
            LazyVStack(spacing: 2) {
                ForEach(stocks.filter { $0.category == category }) { stock in
                    stockButton(stock, selected: stock.id == selected, film: film)
                        .accessibilityLabel(stock.name)
                        .accessibilityAddTraits(stock.id == selected ? .isSelected : [])
                        .accessibilityIdentifier("develop.stock." + stock.id)
                        .id(stock.id)
                }
            }
        }
    }
}
