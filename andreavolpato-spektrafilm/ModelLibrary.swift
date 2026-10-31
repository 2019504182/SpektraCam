import Foundation

/// Immutable, attributed spectral data; image edits never mutate stock profiles.
nonisolated struct ModelLibrary: Sendable {
    struct Profile: Decodable, Sendable {
        let id: String, name: String, positive: Bool, stage: String
        let logExposure: [Double], densityCurves: [[Double]], densityLayers: [[[Double]]]
        let channels: [[Double]], base: [Double], sensitivity: [[Double]], viewingIlluminant: [Double]
        let centers: [[Double]], amplitudes: [[Double]], sigmas: [[Double]], scanMatrix: [[Double]]
        let referenceIlluminant: [Double]?, sensitivityWindow: [[Double]]?, compressionMapOffset: Int?
    }
    struct Table: Decodable, Sendable {
        let stock: String, size: Int, byteOffset: Int, byteLength: Int, matrix: [[Double]]
    }
    struct Gamut: Decodable, Sendable {
        let white: [Double], lAxis: [Double], hAxis: [Double], matrixToXYZ: [[Double]],
            matrixFromXYZ: [[Double]]
    }
    struct Index: Decodable, Sendable {
        let version: Int, revision: String, profiles: [String: Profile], exposureTables: [Table]
        let spectralLUTSize: Int?
        let wavelengths: [Double], cmfs: [[Double]], enlargerIlluminant: [Double]
        let neutralFilters: [String: [String: [Double]]], gamut: Gamut, rgbRoundTrip: [[Double]],
            meteringY: [Double]
    }
    enum Failure: Error { case missingData, unsupportedVersion, unknownStock }
    let index: Index
    private let tables: Data
    private let boundaries: Data
    private let spectra: ExposureTableCore.Spectra?
    private let compressionMaps: Data?

    init(directory: URL) throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        index = try decoder.decode(
            Index.self, from: Data(contentsOf: directory.appending(path: "StockProfiles.json")))
        guard index.version == 1, index.revision == "3bb2c2d2801ff68b92019cf1dbcbb133d60832bc" else {
            throw Failure.unsupportedVersion
        }
        tables = try Data(contentsOf: directory.appending(path: "HanatosTables.f64"), options: .mappedIfSafe)
        boundaries = try Data(
            contentsOf: directory.appending(path: "GamutBoundary.f64"), options: .mappedIfSafe)
        let source = directory.appending(path: "HanatosSpectra.f16")
        if FileManager.default.fileExists(atPath: source.path), let size = index.spectralLUTSize {
            let data = try Data(contentsOf: source, options: .mappedIfSafe)
            guard data.count == size * size * index.wavelengths.count * 2 else { throw Failure.missingData }
            spectra = .init(data: data)
            compressionMaps = try Data(
                contentsOf: directory.appending(path: "InputCompressionMaps.f64"), options: .mappedIfSafe)
        } else {
            spectra = nil
            compressionMaps = nil
        }
    }
    func exposure(stock: String, uv: SIMD3<Double> = SIMD3(0, 410, 8), ir: SIMD3<Double> = SIMD3(0, 675, 15))
        throws -> UpsamplingCore.FilmExposure
    {
        if uv.x > 0 || ir.x > 0 { return try filteredExposure(stock: stock, uv: uv, ir: ir) }
        guard let table = index.exposureTables.first(where: { $0.stock == stock }) else {
            throw Failure.unknownStock
        }
        let values = try Self.doubles(tables, offset: table.byteOffset, length: table.byteLength)
        guard values.count == table.size * table.size * 3 else { throw Failure.missingData }
        let samples = stride(from: 0, to: values.count, by: 3).map {
            SIMD3(values[$0], values[$0 + 1], values[$0 + 2])
        }
        return try .init(
            rgbBasisXYZ: table.matrix.map(Self.vector),
            table: UpsamplingCore.Table2D(size: table.size, samples: samples))
    }
    func filteredExposure(stock: String, uv: SIMD3<Double>, ir: SIMD3<Double>) throws
        -> UpsamplingCore.FilmExposure
    {
        guard let spectra, let compressionMaps, let size = index.spectralLUTSize,
            let profile = index.profiles[stock], let reference = profile.referenceIlluminant,
            let window = profile.sensitivityWindow, let offset = profile.compressionMapOffset,
            let table = index.exposureTables.first(where: { $0.stock == stock })
        else { throw Failure.missingData }
        let mapping = try Self.doubles(compressionMaps, offset: offset, length: size * size * 2 * 8)
        let coordinates = stride(from: 0, to: mapping.count, by: 2).map {
            SIMD2(mapping[$0], mapping[$0 + 1])
        }
        let samples = try ExposureTableCore.prepare(
            spectra: spectra.doubles(), size: size, wavelengths: index.wavelengths,
            sensitivity: profile.sensitivity.map(Self.vector), window: window.map(Self.vector),
            illuminant: reference, coordinates: coordinates, uv: uv, ir: ir)
        return try .init(
            rgbBasisXYZ: table.matrix.map(Self.vector),
            table: UpsamplingCore.Table2D(size: size, samples: samples))
    }
    func outputCompression() throws -> GamutCore.CAM16Compression {
        let g = index.gamut
        let values = try Self.doubles(boundaries, offset: 0, length: boundaries.count)
        let boundary = try GamutCore.Boundary(lightness: g.lAxis, hue: g.hAxis, values: values)
        return try .init(
            white: Self.vector(g.white), boundary: boundary, matrixToXYZ: g.matrixToXYZ.map(Self.vector),
            matrixFromXYZ: g.matrixFromXYZ.map(Self.vector))
    }
    static func vector(_ values: [Double]) -> SIMD3<Double> {
        precondition(values.count == 3, "Corrupt three-channel model data")
        return SIMD3(values[0], values[1], values[2])
    }
    private static func doubles(_ data: Data, offset: Int, length: Int) throws -> [Double] {
        guard offset >= 0, length >= 0, length % 8 == 0, offset <= data.count - length else {
            throw Failure.missingData
        }
        return data.withUnsafeBytes { bytes in
            stride(from: offset, to: offset + length, by: 8).map {
                Double(
                    bitPattern: UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt64.self))
                )
            }
        }
    }
}
