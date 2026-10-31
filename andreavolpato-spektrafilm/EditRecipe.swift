import Foundation

/// Stable upstream parameter paths keep UI names separate from the physical model.
nonisolated struct EditRecipe: Codable, Equatable, Sendable {
    struct Source: Codable, Equatable, Sendable {
        var exposureEV = 0.0
        var warmth = 0.0
        var tint = 0.0
        var saturation = 1.0
    }
    var source = Source()
    var mix = 1.0
    var version = 1
    var upstreamRevision = "3bb2c2d2801ff68b92019cf1dbcbb133d60832bc"
    var filmID = "kodak_portra_400"
    var printID = "kodak_portra_endura"
    var scanFilm = false
    var crop = CropSelection()
    var geometry = ImageGeometry()
    var temperature: Double?
    var numbers: [String: Double] = [:]
    var flags: [String: Bool] = [:]
    var choices: [String: String] = [:]

    init() {}
    enum CodingKeys: String, CodingKey {
        case source, mix, version, upstreamRevision, filmID, printID, scanFilm, crop, geometry, temperature,
            numbers,
            flags, choices
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decodeIfPresent(Source.self, forKey: .source) ?? Source()
        mix = try values.decodeIfPresent(Double.self, forKey: .mix) ?? 1
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: values, debugDescription: "Unsupported edit-recipe version")
        }
        upstreamRevision =
            try values.decodeIfPresent(String.self, forKey: .upstreamRevision) ?? upstreamRevision
        filmID = try values.decodeIfPresent(String.self, forKey: .filmID) ?? filmID
        printID = try values.decodeIfPresent(String.self, forKey: .printID) ?? printID
        scanFilm = try values.decodeIfPresent(Bool.self, forKey: .scanFilm) ?? false
        crop = try values.decodeIfPresent(CropSelection.self, forKey: .crop) ?? CropSelection()
        geometry = try values.decodeIfPresent(ImageGeometry.self, forKey: .geometry) ?? ImageGeometry()
        temperature = try values.decodeIfPresent(Double.self, forKey: .temperature)
        numbers = try values.decodeIfPresent([String: Double].self, forKey: .numbers) ?? [:]
        flags = try values.decodeIfPresent([String: Bool].self, forKey: .flags) ?? [:]
        choices = try values.decodeIfPresent([String: String].self, forKey: .choices) ?? [:]
    }

    func number(_ path: String) -> Double {
        numbers[path] ?? defaultNumber(path)
    }
    func defaultNumber(_ path: String) -> Double {
        StockDefaults.numbers[filmID]?[path] ?? ParameterDefinition.byPath[path]?.defaultNumber ?? 0
    }
    func flag(_ path: String) -> Bool {
        flags[path] ?? ParameterDefinition.byPath[path]?.defaultFlag ?? false
    }
    func choice(_ path: String) -> String {
        choices[path] ?? ParameterDefinition.byPath[path]?.defaultChoice ?? ""
    }
    mutating func removeDefaultOverrides() {
        numbers = numbers.filter { defaultNumber($0.key) != $0.value }
        flags = flags.filter { ParameterDefinition.byPath[$0.key]?.defaultFlag != $0.value }
        choices = choices.filter { ParameterDefinition.byPath[$0.key]?.defaultChoice != $0.value }
    }
    /// A new stock uses its natural route; a print choice is retained for later printing.
    mutating func selectFilm(_ stock: FilmStock) {
        guard stock.id != filmID else { return }
        let resetKeys = Set(StockDefaults.numbers[filmID]?.keys.map { $0 } ?? []).union(stock.defaults.keys)
        filmID = stock.id
        for key in resetKeys { numbers.removeValue(forKey: key) }
        scanFilm = stock.isPositive
    }
    /// UI stops map to the upstream linear enlarger exposure multiplier.
    var printExposureEV: Double {
        get { log2(max(number("enlarger.print_exposure"), pow(2, -10))) }
        set { numbers["enlarger.print_exposure"] = pow(2, newValue) }
    }
    /// Geometry is applied after film rendering and must not invalidate its expensive cache.
    var processingRecipe: Self {
        var copy = self
        copy.crop = CropSelection()
        copy.geometry = ImageGeometry()
        return copy
    }
    var bypassesPrint: Bool { scanFilm }
}

nonisolated struct ParameterDefinition: Identifiable, Sendable {
    let id: String
    let title: String
    var defaultNumber: Double?
    var defaultFlag: Bool?
    var defaultChoice: String?
    var options: [String] = []
    var sliderRange: ClosedRange<Double> = 0...1
    var step: Double = 0.01
    var minimum: Double?
    var maximum: Double?
    var unit: String = ""

    static func number(
        _ id: String, _ title: String, _ value: Double, _ range: ClosedRange<Double>,
        step: Double, minimum: Double?, maximum: Double?, unit: String
    ) -> Self {
        .init(
            id: id, title: title, defaultNumber: value, sliderRange: range,
            step: step, minimum: minimum, maximum: maximum, unit: unit)
    }
    static func flag(_ id: String, _ title: String, _ value: Bool) -> Self {
        .init(id: id, title: title, defaultFlag: value)
    }
    static func choice(_ id: String, _ title: String, _ value: String, _ options: [String]) -> Self {
        .init(id: id, title: title, defaultChoice: value, options: options)
    }
    static let byGroup = Dictionary(grouping: catalog) { definition in
        definition.id.split(separator: ".").dropLast().joined(separator: ".")
    }
    var fieldName: String { String(id.split(separator: ".").last!.split(separator: "[").first!) }
    static let byPath = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
}
