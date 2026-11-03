// Profile names and identifiers from spektrafilm 3bb2c2d. Andrea Volpato.
// Profile data: CC BY-SA 4.0; see SPEKTRAFILM_LICENSE.txt.
import Foundation

nonisolated struct FilmStock: Identifiable, Sendable {
    let id: String
    let name: String
    let kind: String
    let support: String
    let stage: String
    let targetPrint: String?
    var defaults: [String: Double] { StockDefaults.numbers[id] ?? [:] }
    var isPositive: Bool { kind == "positive" }
    /// Display abbreviations only. Stable IDs and full accessibility names do not change.
    var compactName: String {
        name.replacingOccurrences(of: "Fujifilm ", with: "Fuji ")
            .replacingOccurrences(of: "Kodak Professional ", with: "Kodak ")
            .replacingOccurrences(of: " (Push 1)", with: " +1")
            .replacingOccurrences(of: " (Push 2)", with: " +2")
    }
    static let all: [FilmStock] = [
        .init(
            id: "fujifilm_c200", name: "Fujifilm C200", kind: "negative", support: "film",
            stage: "filming", targetPrint: "fujifilm_crystal_archive_typeii"),
        .init(
            id: "fujifilm_crystal_archive_typeii", name: "Fujifilm Crystal Archive Type II",
            kind: "negative", support: "paper", stage: "printing", targetPrint: nil),
        .init(
            id: "fujifilm_pro_400h", name: "Fujifilm Pro 400H", kind: "negative", support: "film",
            stage: "filming", targetPrint: "fujifilm_crystal_archive_typeii"),
        .init(
            id: "fujifilm_provia_100f", name: "Fujifilm Provia 100F", kind: "positive",
            support: "film", stage: "filming", targetPrint: nil),
        .init(
            id: "fujifilm_velvia_100", name: "Fujifilm Velvia 100", kind: "positive",
            support: "film", stage: "filming", targetPrint: nil),
        .init(
            id: "fujifilm_xtra_400", name: "Fujifilm X-Tra 400", kind: "negative", support: "film",
            stage: "filming", targetPrint: "fujifilm_crystal_archive_typeii"),
        .init(
            id: "kodak_2383", name: "Kodak Vision 2383", kind: "negative", support: "film",
            stage: "printing", targetPrint: nil),
        .init(
            id: "kodak_2393", name: "Kodak Vision Premier 2393", kind: "negative", support: "film",
            stage: "printing", targetPrint: nil),
        .init(
            id: "kodak_ektachrome_100", name: "Kodak Ektachrome 100", kind: "positive",
            support: "film", stage: "filming", targetPrint: nil),
        .init(
            id: "kodak_ektacolor_edge", name: "Kodak Ektacolor Edge", kind: "negative",
            support: "paper", stage: "printing", targetPrint: nil),
        .init(
            id: "kodak_ektar_100", name: "Kodak Ektar 100", kind: "negative", support: "film",
            stage: "filming", targetPrint: "kodak_portra_endura"),
        .init(
            id: "kodak_endura_premier", name: "Kodak Professional Endura Premier", kind: "negative",
            support: "paper", stage: "printing", targetPrint: nil),
        .init(
            id: "kodak_gold_200", name: "Kodak Gold 200", kind: "negative", support: "film",
            stage: "filming", targetPrint: "kodak_portra_endura"),
        .init(
            id: "kodak_kodachrome_64", name: "Kodak Kodachrome 64", kind: "positive",
            support: "film", stage: "filming", targetPrint: nil),
        .init(
            id: "kodak_portra_160", name: "Kodak Portra 160", kind: "negative", support: "film",
            stage: "filming", targetPrint: "kodak_portra_endura"),
        .init(
            id: "kodak_portra_400", name: "Kodak Portra 400", kind: "negative", support: "film",
            stage: "filming", targetPrint: "kodak_portra_endura"),
        .init(
            id: "kodak_portra_800", name: "Kodak Portra 800", kind: "negative", support: "film",
            stage: "filming", targetPrint: "kodak_portra_endura"),
        .init(
            id: "kodak_portra_800_push1", name: "Kodak Portra 800 (Push 1)", kind: "negative",
            support: "film", stage: "filming", targetPrint: "kodak_portra_endura"),
        .init(
            id: "kodak_portra_800_push2", name: "Kodak Portra 800 (Push 2)", kind: "negative",
            support: "film", stage: "filming", targetPrint: "kodak_portra_endura"),
        .init(
            id: "kodak_portra_endura", name: "Kodak Professional Portra Endura", kind: "negative",
            support: "paper", stage: "printing", targetPrint: nil),
        .init(
            id: "kodak_supra_endura", name: "Kodak Professional Supra Endura", kind: "negative",
            support: "paper", stage: "printing", targetPrint: nil),
        .init(
            id: "kodak_ultra_endura", name: "Kodak Professional Ultra Endura", kind: "negative",
            support: "paper", stage: "printing", targetPrint: nil),
        .init(
            id: "kodak_ultramax_400", name: "Kodak Ultramax 400", kind: "negative", support: "film",
            stage: "filming", targetPrint: "kodak_portra_endura"),
        .init(
            id: "kodak_verita_200d", name: "Kodak Verita 200D", kind: "negative", support: "film",
            stage: "filming", targetPrint: "kodak_2383"),
        .init(
            id: "kodak_vision3_200t", name: "Kodak Vision3 200T", kind: "negative", support: "film",
            stage: "filming", targetPrint: "kodak_2383"),
        .init(
            id: "kodak_vision3_250d", name: "Kodak Vision3 250D", kind: "negative", support: "film",
            stage: "filming", targetPrint: "kodak_2383"),
        .init(
            id: "kodak_vision3_500t", name: "Kodak Vision3 500T", kind: "negative", support: "film",
            stage: "filming", targetPrint: "kodak_2383"),
        .init(
            id: "kodak_vision3_50d", name: "Kodak Vision3 50D", kind: "negative", support: "film",
            stage: "filming", targetPrint: "kodak_2383"),
    ]
    static let films = all.filter { $0.stage == "filming" }
    static let prints = all.filter { $0.stage == "printing" }

    enum Category: String, CaseIterable, Identifiable, Sendable {
        case photoNegative, cinemaNegative, reversal, photoPaper, cinemaPrint
        var id: Self { self }
        var shortTitle: String {
            switch self {
            case .photoNegative: String(localized: "film_stock.photo", defaultValue: "Photo")
            case .cinemaNegative: String(localized: "film_stock.cine", defaultValue: "Cine")
            case .reversal: String(localized: "film_stock.slide", defaultValue: "Slide")
            case .photoPaper: String(localized: "film_stock.paper", defaultValue: "Paper")
            case .cinemaPrint: String(localized: "film_stock.film", defaultValue: "Film")
            }
        }
        var title: String {
            switch self {
            case .photoNegative:
                String(
                    localized: "film_stock.color_negative_photo",
                    defaultValue: "Color negative · Photo")
            case .cinemaNegative:
                String(
                    localized: "film_stock.color_negative_cinema",
                    defaultValue: "Color negative · Cinema")
            case .reversal:
                String(localized: "film_stock.color_reversal", defaultValue: "Color reversal")
            case .photoPaper:
                String(
                    localized: "film_stock.photographic_paper", defaultValue: "Photographic paper")
            case .cinemaPrint:
                String(localized: "film_stock.cinema_print_film", defaultValue: "Cinema print film")
            }
        }
        static let films: [Self] = [.photoNegative, .cinemaNegative, .reversal]
        static let prints: [Self] = [.photoPaper, .cinemaPrint]
    }
    var category: Category {
        if stage == "printing" { return support == "paper" ? .photoPaper : .cinemaPrint }
        if isPositive { return .reversal }
        // Negative groups follow the upstream stock’s intended print medium.
        if let targetPrint, Self.all.first(where: { $0.id == targetPrint })?.support == "film" {
            return .cinemaNegative
        }
        return .photoNegative
    }

}
