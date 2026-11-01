import SwiftUI

/// Two native browsing columns keep stock names visible and selections one tap away.
struct DevelopPanel: View {
    // Stock list spacing, in points. Change these values to test the layout.
    private let stockRowHeight: CGFloat = 36
    private let stockRowSpacing: CGFloat = 0
    private let stockSelectionHeight: CGFloat = 30

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
                        directScan
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
                }
            }
            mixControl
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

    private var mixControl: some View {
        NumericControl(
            title: "Mix",
            value: Binding(
                get: { session.recipe.mix * 100 },
                set: { value in session.update(key: "mix") { $0.mix = value / 100 } }),
            range: 0...100, step: 1, minimum: 0, maximum: 100, unit: "%", identifier: "develop.mix",
            defaultValue: 100, fillOrigin: 0,
            onEditingChanged: { session.setInteraction(key: "mix", active: $0) })
    }
    private var directScan: some View {
        DisclosureGroup("Scan") {
            Toggle("Scan film directly", isOn: session.binding(\.scanFilm, key: "route"))
                .accessibilityIdentifier("develop.scanFilm")
            if session.recipe.bypassesPrint {
                Text("Print settings are bypassed.").font(.caption2).foregroundStyle(.secondary)
            }
        }.font(.caption).padding(.top, 8)
    }

    private func categoryControl(
        _ title: String, categories: [FilmStock.Category], selection: Binding<FilmStock.Category>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold))
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
                .disabled(!film && session.recipe.bypassesPrint)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        stockRows(stocks, category: selection.wrappedValue, selected: selected, film: film)
                            .disabled(!film && session.recipe.bypassesPrint)
                        if !film { directScan }
                    }
                }
                .clipped()
                .onAppear { proxy.scrollTo(selected, anchor: .center) }

            }
            .id(selection.wrappedValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stockButton(_ stock: FilmStock, selected: Bool, film: Bool) -> some View {
        Button {
            if film {
                session.selectFilm(stock)
            } else {
                session.update(key: "print") { $0.printID = stock.id }
            }
        } label: {
            VStack(spacing: 0) {
                Group {
                    if selected {
                        stockLabel(stock, selected: true).glassEffect(
                            .regular.tint(.accentColor).interactive(), in: .rect(cornerRadius: 10))
                    } else {
                        stockLabel(stock, selected: false)
                    }
                }
            }.frame(minHeight: typeSize.isAccessibilitySize ? 44 : stockRowHeight).contentShape(.rect)
        }.buttonStyle(.plain)
    }
    private func stockLabel(_ stock: FilmStock, selected: Bool) -> some View {
        HStack(spacing: 4) {
            Text(stock.compactName).font(.caption)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
            Image(systemName: "checkmark").font(.caption.weight(.semibold))
                .frame(width: 12).opacity(selected ? 1 : 0).accessibilityHidden(true)
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: stockSelectionHeight)
    }
    private func stockRows(_ stocks: [FilmStock], category: FilmStock.Category, selected: String, film: Bool)
        -> some View
    {
        let matches = stocks.filter { $0.category == category }
        return GlassEffectContainer(spacing: 2) {
            LazyVStack(spacing: stockRowSpacing) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, stock in
                    if index > 0 && manufacturer(matches[index - 1]) != manufacturer(stock) {
                        Divider().padding(.vertical, 5)
                    }
                    stockButton(stock, selected: stock.id == selected, film: film)
                        .accessibilityLabel(stock.name)
                        .accessibilityAddTraits(stock.id == selected ? .isSelected : [])
                        .accessibilityIdentifier("develop.stock." + stock.id).id(stock.id)
                }
            }
        }
    }
    private func manufacturer(_ stock: FilmStock) -> String {
        stock.id.components(separatedBy: "_").first ?? stock.id
    }
}
