import Foundation

private struct Case: Decodable {
    let stock: String, uv: [Double], ir: [Double], input: [[Double]], expected: [[Double]]
}
private struct Fixture: Decodable { let cases: [Case] }
@main struct Checks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let library = try ModelLibrary(
            directory: root.appendingPathComponent("SpektraCam/Resources/ModelData"))
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Reference/Fixtures/filtered-exposure.json")))
        var count = 0
        var maximum = 0.0
        func check(_ a: SIMD3<Double>, _ b: SIMD3<Double>, tolerance: Double) {
            for ch in 0..<3 {
                let error = abs(a[ch] - b[ch])
                precondition(error.isFinite && error < tolerance, "Spectral table mismatch \(error)")
                count += 1
                maximum = max(maximum, error)
            }
        }
        // Reconstruct every unfiltered table from shared Float16 spectra and stock windows.
        for table in library.index.exposureTables {
            let original = try library.exposure(stock: table.stock)
            let native = try library.filteredExposure(
                stock: table.stock, uv: SIMD3(0, 410, 8), ir: SIMD3(0, 675, 15))
            for (a, b) in zip(original.table.samples, native.table.samples) { check(a, b, tolerance: 1e-10) }
        }
        for c in fixture.cases {
            let native = try library.exposure(
                stock: c.stock, uv: ModelLibrary.vector(c.uv), ir: ModelLibrary.vector(c.ir))
            for i in c.input.indices {
                check(
                    native.raw(ModelLibrary.vector(c.input[i])), ModelLibrary.vector(c.expected[i]),
                    tolerance: 1e-10)
            }
        }
        print(
            "PASS: reconstructed all 20 stock tables from shared spectra; \(fixture.cases.count) UV/IR filming cases; \(count) values; max absolute error \(maximum)"
        )
    }
}
