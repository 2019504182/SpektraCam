// Non-spatial DIR chemistry ported from spektrafilm 3bb2c2d. GPLv3.
import Foundation

nonisolated enum CouplerCore {
    typealias RGB = SpectralCore.RGB
    /// Rows donate inhibitor; columns receive it. Spatial diffusion is a later stage.
    struct Matrix: Sendable {
        let rows: [RGB]
        init(rows: [RGB]) throws {
            guard rows.count == 3 else { throw SpectralCore.Failure.invalidShape }
            self.rows = rows
        }
        func inhibition(from donor: RGB) -> RGB {
            rows[0] * donor.x + rows[1] * donor.y + rows[2] * donor.z
        }
    }
    struct NonSpatialDevelopment: Sendable {
        let original: SpectralCore.DensityCurve
        let beforeCouplers: SpectralCore.DensityCurve
        let matrix: Matrix
        let positive: Bool
        let maximum: RGB

        init(axis: [Double], normalizedCurves: [RGB], gamma: Double, matrix: Matrix, positive: Bool) throws {
            guard !normalizedCurves.isEmpty else { throw SpectralCore.Failure.invalidShape }
            self.matrix = matrix
            self.positive = positive
            maximum = normalizedCurves.reduce(RGB(repeating: -.infinity)) {
                RGB(max($0.x, $1.x), max($0.y, $1.y), max($0.z, $1.z))
            }
            original = try SpectralCore.DensityCurve(axis: axis, values: normalizedCurves, gamma: gamma)
            var shiftedAxes = Array(repeating: [Double](), count: 3)
            for i in axis.indices {
                let silver = positive ? maximum - normalizedCurves[i] : normalizedCurves[i]
                let inhibitor = matrix.inhibition(from: silver)
                for ch in 0..<3 { shiftedAxes[ch].append(axis[i] - inhibitor[ch]) }
            }
            var corrected = normalizedCurves
            for ch in 0..<3 {
                // Positive profiles use negation on both sides upstream; interpolation is linear.
                let table = normalizedCurves.map { RGB(repeating: $0[ch]) }
                let channel = try SpectralCore.DensityCurve(axis: shiftedAxes[ch], values: table)
                for i in axis.indices { corrected[i][ch] = channel.density(at: RGB(repeating: axis[i])).x }
            }
            beforeCouplers = try SpectralCore.DensityCurve(axis: axis, values: corrected, gamma: gamma)
        }
        func density(at logExposure: RGB) -> RGB {
            let density = original.density(at: logExposure)
            let silver = positive ? maximum - density : density
            return beforeCouplers.density(at: logExposure - matrix.inhibition(from: silver))
        }
    }
}
