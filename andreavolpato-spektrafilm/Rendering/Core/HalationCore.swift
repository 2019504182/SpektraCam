// Emulsion scatter and additive/renormalized multi-bounce halation. spektrafilm 3bb2c2d, GPLv3.
import Foundation

nonisolated enum HalationCore {
    typealias RGB = SIMD3<Double>
    struct Parameters: Sendable {
        var active = true
        var scatterAmount = 1.0, scatterScale = 1.0, amount = 1.0, scale = 1.0
        var scatterCore = RGB(2.2, 2, 1.6), scatterTail = RGB(9.3, 9.7, 9.1),
            tailWeight = RGB(0.78, 0.65, 0.67)
        var strength = RGB(0.05, 0.015, 0), firstSigma = RGB(repeating: 65)
        var bounces = 3, decay = 0.5, renormalize = true
    }
    static func apply(_ image: SpatialCore.Image, parameters p: Parameters, pixelSizeMicrometers: Double)
        throws -> SpatialCore.Image
    {
        guard pixelSizeMicrometers > 0 && pixelSizeMicrometers.isFinite else {
            throw SpectralCore.Failure.invalidShape
        }
        guard p.active else { return image }
        var output = image
        let sigma = p.scatterCore * p.scatterScale / pixelSizeMicrometers
        let tail = p.scatterTail * p.scatterScale / pixelSizeMicrometers
        if p.scatterAmount > 0 && (anyPositive(sigma) || anyPositive(tail)) {
            let core = image.gaussian(lowerBound(sigma))
            let exponential = image.exponential(lowerBound(tail))
            for i in output.pixels.indices {
                let scattered =
                    (RGB(repeating: 1) - p.tailWeight) * core.pixels[i] + p.tailWeight * exponential.pixels[i]
                output.pixels[i] = image.pixels[i] * (1 - p.scatterAmount) + scattered * p.scatterAmount
            }
        }
        let amount = p.strength * p.amount
        let haloSigma = p.firstSigma * p.scale / pixelSizeMicrometers
        if p.bounces >= 1 && anyPositive(amount) && anyPositive(haloSigma) {
            var weights = (0..<p.bounces).map { pow(p.decay, Double($0)) }
            let total = weights.reduce(0, +)
            weights = weights.map { $0 / total }
            var blur = Array(repeating: RGB.zero, count: output.pixels.count)
            for k in 1...p.bounces {
                let blurred = output.gaussian(lowerBound(haloSigma * sqrt(Double(k))))
                for i in blur.indices { blur[i] += blurred.pixels[i] * weights[k - 1] }
            }
            for i in output.pixels.indices {
                output.pixels[i] += amount * blur[i]
                if p.renormalize { output.pixels[i] /= RGB(repeating: 1) + amount }
            }
        }
        return output
    }
    private static func anyPositive(_ v: RGB) -> Bool { v.x > 0 || v.y > 0 || v.z > 0 }
    private static func lowerBound(_ v: RGB) -> RGB { RGB(max(v.x, 1e-6), max(v.y, 1e-6), max(v.z, 1e-6)) }
}

nonisolated enum HighlightBoostCore {
    static func apply(_ image: SpatialCore.Image, ev: Double, range: Double, protectEV: Double) throws
        -> SpatialCore.Image
    {
        guard ev >= 0, protectEV >= 0, (0...1).contains(range) else {
            throw SpectralCore.Failure.invalidCurve
        }
        guard ev != 0 else { return image }
        let maximum = image.pixels.reduce(-Double.infinity) { max($0, max($1.x, max($1.y, $1.z))) }
        var output = image
        if maximum == 0 {
            output.pixels = Array(repeating: .zero, count: image.pixels.count)
            return output
        }
        let x0 = min(max(0.184 * pow(2, protectEV), 0), maximum)
        if x0 == maximum { return image }
        let a = pow(28, 1 - range)
        let normalized = x0 / maximum
        let denominator = exp(a * (1 - normalized)) - a * (1 - normalized) - 1
        guard denominator > 0 else { throw SpectralCore.Failure.invalidCurve }
        let inverseMax = 1 / maximum
        let scale = (pow(2, ev) - 1) / denominator * maximum
        for i in output.pixels.indices {
            for channel in 0..<3 {
                let value = image.pixels[i][channel]
                if value > x0 {
                    let dx = (value - x0) * inverseMax
                    output.pixels[i][channel] = value + scale * (exp(a * dx) - a * dx - 1)
                }
            }
        }
        return output
    }
}
