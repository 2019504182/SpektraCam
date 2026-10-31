import Foundation

private struct CurveCase: Decodable {
    let id: String
    let axis: [Double]
    let curves: [[Double]]
    let gamma: Double
    let input: [[Double]]
    let expected: [[Double]]
}
private struct SpectralCase: Decodable {
    let channels: [[Double]], base: [Double], illuminant: [Double], cmfs: [[Double]]
    let density: [[Double]], spectrum: [[Double]], light: [[Double]], xyz: [[Double]]
}
private struct Fixtures: Decodable {
    let revision: String
    let curveCases: [CurveCase]
    let spectralCase: SpectralCase
}
@main struct SpectralChecks {
    static func main() throws {
        let path = CommandLine.arguments[1]
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let fixtures = try decoder.decode(Fixtures.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        func rgb(_ a: [Double]) -> SIMD3<Double> { precondition(a.count == 3); return .init(a[0], a[1], a[2]) }
        var maxError = 0.0, count = 0
        func check(_ actual: Double, _ expected: Double) {
            if actual.isNaN && expected.isNaN { count += 1; return }
            let error = abs(actual - expected)
            precondition(error < 1e-11 + abs(expected) * 1e-12, "Parity failure: \(actual) versus \(expected)")
            maxError = max(maxError, error); count += 1
        }
        for fixture in fixtures.curveCases {
            let curve = try SpectralCore.DensityCurve(axis: fixture.axis, values: fixture.curves.map(rgb), gamma: fixture.gamma)
            for (input, expected) in zip(fixture.input, fixture.expected) {
                let actual = curve.density(at: rgb(input))
                for channel in 0..<3 { check(actual[channel], expected[channel]) }
            }
        }
        let f = fixtures.spectralCase
        let basis = try SpectralCore.SpectralBasis(channels: f.channels.map(rgb), base: f.base, illuminant: f.illuminant, cmfs: f.cmfs.map(rgb))
        for i in f.density.indices {
            let spectrum = basis.densitySpectrum(rgb(f.density[i]))
            let light = try basis.transmittedLight(spectrum)
            for j in spectrum.indices { check(spectrum[j], f.spectrum[i][j]); check(light[j], f.light[i][j]) }
            let xyz = basis.xyz(rgb(f.density[i]))
            for channel in 0..<3 { check(xyz[channel], f.xyz[i][channel]) }
        }
        print("PASS: \(fixtures.curveCases.count) stock/gamma/interpolation cases; \(count) spectral-stage values; max absolute error \(maxError)")
    }
}
