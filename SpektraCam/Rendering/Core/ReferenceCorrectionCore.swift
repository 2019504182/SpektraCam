// Stock-anchored black/white references from spektrafilm 3bb2c2d. GPLv3.
import Foundation

nonisolated struct ReferenceCorrectionCore: Sendable {
    typealias RGB = SIMD3<Double>
    let active: Bool, gain: Double, offset: Double, filmingScale: Double, printingScale: Double
    init(recipe: EditRecipe, film: ModelLibrary.Profile, paper: ModelLibrary.Profile, color: ColorPipeline)
        throws
    {
        let black = recipe.flag("scanner.black_correction")
        let white = recipe.flag("scanner.white_correction")
        if (!black && !white) || (recipe.bypassesPrint && !film.positive) {
            active = false
            gain = 1
            offset = 0
            filmingScale = 1
            printingScale = 1
            return
        }
        active = true
        func scanY(_ density: RGB) -> Double {
            let xyz = color.scanBasis.xyz(density)
            return pow(10, log10(max(xyz.y, 0) + 1e-10))
        }
        let maximum = film.densityCurves.map(ModelLibrary.vector).reduce(RGB(repeating: -.infinity)) {
            RGB(max($0.x, $1.x), max($0.y, $1.y), max($0.z, $1.z))
        }
        let yBlack: Double
        let yWhite: Double
        if recipe.bypassesPrint {
            yBlack = scanY(maximum)
            yWhite = scanY(.zero)
        } else {
            guard let enlarger = color.enlarger, !paper.positive else {
                throw ColorPipeline.Failure.unsupportedRecipe
            }
            let stockCurve = try SpectralCore.DensityCurve(
                axis: paper.logExposure, values: paper.densityCurves.map(ModelLibrary.vector))
            func developReference(_ density: RGB) -> RGB {
                let raw = enlarger.baseExposure(density)
                let logRaw = RGB(
                    log10(max(raw.x, 0) + 1e-10), log10(max(raw.y, 0) + 1e-10), log10(max(raw.z, 0) + 1e-10))
                return stockCurve.density(at: logRaw)
            }
            let minimum = RGB(
                recipe.number("film_render.grain.density_min[0]"),
                recipe.number("film_render.grain.density_min[1]"),
                recipe.number("film_render.grain.density_min[2]"))
            yBlack = scanY(developReference(-minimum))
            yWhite = scanY(developReference(maximum))
        }
        func decodeLevel(_ key: String) -> Double {
            let v = recipe.number(key)
            let linear = v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            let rgb = ColorPipeline.apply(color.encodingMatrix, RGB(repeating: linear))
            return (rgb.x + rgb.y + rgb.z) / 3
        }
        let targetBlack = black ? decodeLevel("scanner.black_level") : yBlack
        let targetWhite = white ? decodeLevel("scanner.white_level") : yWhite
        let m = (targetWhite - targetBlack) / (yWhite - yBlack + 1e-10)
        let q = targetBlack - m * yBlack
        gain = m
        offset = q
        let correctedGray = (0.184 - q) / m
        guard correctedGray.isFinite, correctedGray > 0 else { throw SpectralCore.Failure.invalidCurve }
        func exposureScale(_ profile: ModelLibrary.Profile, positive: Bool) -> Double {
            let sign = positive ? -1.0 : 1.0
            let axis = profile.densityCurves.map { ($0[0] + $0[1] + $0[2]) / 3 * sign }
            let bases = profile.base.filter { $0.isFinite }
            let base = bases.reduce(0, +) / Double(bases.count)
            func interpolate(_ x: Double) -> Double {
                if x <= axis[0] { return profile.logExposure[0] }
                if x >= axis[axis.count - 1] { return profile.logExposure[axis.count - 1] }
                var low = 0
                var high = axis.count
                while low < high {
                    let middle = (low + high) / 2
                    if axis[middle] <= x { low = middle + 1 } else { high = middle }
                }
                let i = low - 1
                let dx = axis[i + 1] - axis[i]
                let t = dx == 0 ? 0 : (x - axis[i]) / dx
                return profile.logExposure[i] + t * (profile.logExposure[i + 1] - profile.logExposure[i])
            }
            let corrected = interpolate((-log10(correctedGray) - base) * sign) * sign
            let original = interpolate((-log10(0.184) - base) * sign) * sign
            let factor = pow(10, corrected - original)
            return positive ? 1 / factor : factor
        }
        filmingScale = recipe.bypassesPrint && film.positive ? exposureScale(film, positive: true) : 1
        printingScale = recipe.bypassesPrint ? 1 : exposureScale(paper, positive: false)
    }
    func correct(_ xyz: RGB) -> RGB {
        guard active else { return xyz }
        let luminance = min(max(gain * xyz.y + offset, 0), 1)
        return xyz * (luminance / (xyz.y + 1e-10))
    }
}
