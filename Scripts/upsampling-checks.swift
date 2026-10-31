import Foundation
private struct Case: Decodable {
    let stock: String, size: Int, byteOffset: Int, byteLength: Int
    let matrix: [[Double]], input: [[Double]], expected: [[Double]]
}
private struct Fixtures: Decodable { let cases: [Case] }
@main struct UpsamplingChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixture = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: root.appending(path: "upsampling-stages.json")))
        let bytes = try Data(contentsOf: root.appending(path: "hanatos-tables.f64"))
        func rgb(_ values: [Double]) -> SIMD3<Double> { .init(values[0],values[1],values[2]) }
        var maximum = 0.0, count = 0
        for f in fixture.cases {
            let values = bytes.subdata(in: f.byteOffset..<(f.byteOffset + f.byteLength)).withUnsafeBytes {
                Array($0.bindMemory(to: UInt64.self)).map { Double(bitPattern: UInt64(littleEndian: $0)) }
            }
            let samples = stride(from: 0, to: values.count, by: 3).map { SIMD3(values[$0],values[$0+1],values[$0+2]) }
            let table = try UpsamplingCore.Table2D(size: f.size, samples: samples)
            let exposure = try UpsamplingCore.FilmExposure(rgbBasisXYZ: f.matrix.map(rgb), table: table)
            for (input,expected) in zip(f.input,f.expected) {
                let result = exposure.raw(rgb(input))
                for ch in 0..<3 {
                    let error = abs(result[ch]-expected[ch])
                    precondition(error < 1e-9 + abs(expected[ch]) * 1e-10, "Upsampling mismatch \(f.stock): \(result[ch]) vs \(expected[ch])")
                    maximum = max(maximum,error);count += 1
                }
            }
        }
        print("PASS: Hanatos stock-specific runtime for \(fixture.cases.count) films; \(count) values; max absolute error \(maximum)")
    }
}
