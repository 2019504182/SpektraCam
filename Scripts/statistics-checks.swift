import Foundation

@main struct Checks {
    static func main() throws {
        let vectors: [(SIMD4<UInt32>, SIMD2<UInt32>, SIMD4<UInt32>)] = [
            (.zero, .zero, .init(0x6627_e8d5, 0xe169_c58d, 0xbc57_ac4c, 0x9b00_dbd8)),
            (
                .init(repeating: .max), .init(repeating: .max),
                .init(0x408f_276d, 0x41c8_3b0e, 0xa20b_c7c6, 0x6d54_51fd)
            ),
            (
                .init(0x243f_6a88, 0x85a3_08d3, 0x1319_8a2e, 0x0370_7344), .init(0xa409_3822, 0x299f_31d0),
                .init(0xd16c_fe09, 0x94fd_cceb, 0x5001_e420, 0x2412_6ea1)
            ),
        ]
        for (counter, key, expected) in vectors {
            precondition(StatisticsCore.philox(counter, key: key) == expected)
        }
        let count = 200_000
        for mean in [0.01, 0.5, 5, 9.99, 10, 30, 100, 10000, 1e8, 1e12] {
            var sum = 0.0
            var squares = 0.0
            var zeros = 0
            for i in 0..<count {
                var random = StatisticsCore.Stream(pixel: UInt64(i), domain: 41, seed: 20_261_031)
                let value = try random.poisson(mean: mean)
                precondition(value >= 0 && value.rounded() == value)
                let centered = value - mean
                sum += centered
                squares += centered * centered
                if value == 0 { zeros += 1 }
            }
            let bias = sum / Double(count)
            let variance = squares / Double(count) - bias * bias
            precondition(abs(bias) < 7 * sqrt(mean / Double(count)), "Poisson mean \(mean): \(bias)")
            precondition(
                abs(variance / mean - 1) < 7 * sqrt((2 + 1 / mean) / Double(count)),
                "Poisson variance \(mean): \(variance)")
            if mean < 10 {
                let probability = exp(-mean)
                let observed = Double(zeros) / Double(count)
                precondition(
                    abs(observed - probability) < 7 * sqrt(probability * (1 - probability) / Double(count)))
            }
        }
        // Pixel/domain addressing must be stable across traversal and independent across stages.
        var uniforms = [Double]()
        var normals = [Double]()
        for i in 0..<count {
            var a = StatisticsCore.Stream(pixel: UInt64(i), domain: 7, seed: 42)
            var b = StatisticsCore.Stream(pixel: UInt64(i), domain: 7, seed: 42)
            let u = a.uniform()
            precondition(u == b.uniform() && u > 0 && u < 1)
            uniforms.append(u)
            normals.append(a.normal())
        }
        let normalMean = normals.reduce(0, +) / Double(count)
        let normalVariance = normals.reduce(0) { $0 + $1 * $1 } / Double(count) - normalMean * normalMean
        precondition(abs(normalMean) < 0.02 && abs(normalVariance - 1) < 0.03)
        let uniformMean = uniforms.reduce(0, +) / Double(count)
        let lag =
            zip(uniforms.dropLast(), uniforms.dropFirst()).reduce(0) { $0 + ($1.0 - 0.5) * ($1.1 - 0.5) }
            / Double(count - 1) * 12
        precondition(abs(uniformMean - 0.5) < 0.005 && abs(lag) < 0.015)
        for mean in [0.0, -1, .infinity, Double.nan] {
            if mean == 0 { continue }
            var random = StatisticsCore.Stream(pixel: 0, domain: 0, seed: 0)
            do {
                _ = try random.poisson(mean: mean)
                preconditionFailure("Invalid mean accepted")
            } catch StatisticsCore.Failure.invalidDistribution {}
        }
        print(
            "PASS: three official Philox known-answer vectors; 2,000,000 Poisson draws (lambda 0.01…1e12), uniform/normal moments, zero masses, adjacent-pixel correlation and deterministic addressing"
        )
    }
}
