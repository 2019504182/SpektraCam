// Diffusion-filter PSFs from spektrafilm 3bb2c2d. GPLv3.
// Native Double convolution uses Apple's Accelerate FFT; no analytic Gaussian substitution.
import Accelerate
import Foundation

nonisolated enum DiffusionCore {
    typealias RGB = SIMD3<Double>
    enum Failure: Error { case unknownFamily, invalidParameter, fftSetup }
    struct Parameters: Sendable, Hashable {
        var active = false, family = "black_pro_mist", strength = 0.5, spatialScale = 1.0, warmth = 0.0
        var intensity = RGB(repeating: 1), size = RGB(repeating: 1)
    }
    private struct Family: Sendable {
        let centers: RGB, weights: RGB, alpha: Double, warmth: Double, gain: Double
    }
    private static let families: [String: Family] = [
        "glimmerglass": .init(
            centers: RGB(10, 50, 260), weights: RGB(0.6, 0.3, 0.1), alpha: 3.2, warmth: 0, gain: 0.65),
        "black_pro_mist": .init(
            centers: RGB(16, 95, 380), weights: RGB(0.4, 0.47, 0.13), alpha: 3.5, warmth: 0.65, gain: 0.75),
        "pro_mist": .init(
            centers: RGB(14, 150, 650), weights: RGB(0.28, 0.42, 0.3), alpha: 2.9, warmth: 0.4, gain: 1.05),
        "cinebloom": .init(
            centers: RGB(20, 200, 1000), weights: RGB(0.22, 0.3, 0.48), alpha: 2.5, warmth: 0.85, gain: 1),
    ]

    static func scatter(strength: Double, family: String) throws -> Double {
        guard let cfg = families[family] else { throw Failure.unknownFamily }
        if strength <= 0 { return 0 }
        guard strength.isFinite else { throw Failure.invalidParameter }
        let axis = [-3.0, -2, -1, 0, 1]
        let values = [0.1, 0.2, 0.35, 0.55, 0.75]
        let x = log2(max(strength, 1e-6))
        let base: Double
        if x <= axis[0] {
            base = values[0]
        } else if x >= axis[4] {
            base = values[4]
        } else {
            let i = (0..<4).first { axis[$0 + 1] > x }!
            base = values[i] + (values[i + 1] - values[i]) * (x - axis[i])
        }
        return min(max(base * cfg.gain, 0), 0.99)
    }
    private static func resolved(_ p: Parameters) throws -> Family {
        guard let base = families[p.family] else { throw Failure.unknownFamily }
        guard p.spatialScale.isFinite, p.warmth.isFinite,
            (0..<3).allSatisfy({ p.intensity[$0].isFinite && p.size[$0].isFinite })
        else { throw Failure.invalidParameter }
        if p.intensity == RGB(repeating: 1) && p.size == RGB(repeating: 1) { return base }
        var weights = base.weights
        for i in 0..<3 { weights[i] *= max(p.intensity[i], 0) }
        let total = weights.x + weights.y + weights.z
        // Reference fallback ignores size overrides when every intensity is zero.
        if total <= 0 { return base }
        var centers = base.centers
        for i in 0..<3 { centers[i] *= max(p.size[i], 1e-6) }
        guard (0..<3).allSatisfy({ centers[$0].isFinite }), total.isFinite else {
            throw Failure.invalidParameter
        }
        return .init(
            centers: centers, weights: weights / total, alpha: base.alpha, warmth: base.warmth,
            gain: base.gain)
    }
    static func components(pixelSize: Double, parameters p: Parameters) throws -> [(Double, RGB)] {
        guard pixelSize.isFinite, pixelSize > 0 else { throw Failure.invalidParameter }
        let cfg = try resolved(p)
        let spreads = [1.5, 2.0, 2.5]
        let counts = [2, 3, 4]
        let effectiveWarmth = min(max(cfg.warmth + p.warmth, -1.5), 1.5)
        let warmAxis = RGB(1.3, 0.15, -1.45)
        var components = [(Double, RGB)]()
        for group in 0..<3 {
            let count = counts[group]
            let lo = log(cfg.centers[group] / spreads[group])
            let hi = log(cfg.centers[group] * spreads[group])
            let lambdas = (0..<count).map { exp(lo + Double($0) / Double(count - 1) * (hi - lo)) }
            var weights = lambdas.map { group == 2 ? pow($0, 2 - cfg.alpha) : 1 }
            let total = weights.reduce(0, +)
            weights = weights.map { $0 / total }
            var channelWeights = weights.map { RGB(repeating: $0) }
            if group == 1 {
                var gradient = (0..<count).map { -1 + 2 * Double($0) / Double(count - 1) }
                let center = zip(weights, gradient).reduce(0) { $0 + $1.0 * $1.1 } / weights.reduce(0, +)
                gradient = gradient.map { $0 - center }
                for c in 0..<3 {
                    let raw = weights.indices.map {
                        max(weights[$0] * (1 + effectiveWarmth * warmAxis[c] * gradient[$0]), 0)
                    }
                    let sum = raw.reduce(0, +)
                    for k in weights.indices { channelWeights[k][c] = sum > 0 ? raw[k] / sum : weights[k] }
                }
            }
            for k in lambdas.indices {
                components.append(
                    (
                        max(lambdas[k] * max(p.spatialScale, 1e-6) / pixelSize, 1e-6),
                        channelWeights[k] * cfg.weights[group]
                    ))
            }
        }
        return components
    }
    static func kernel(radius: Int, pixelSize: Double, parameters p: Parameters) throws -> SpatialCore.Image {
        guard radius >= 0, pixelSize.isFinite, pixelSize > 0 else { throw Failure.invalidParameter }
        let components = try components(pixelSize: pixelSize, parameters: p)
        let edge = 2 * radius + 1
        var pixels = Array(repeating: RGB.zero, count: edge * edge)
        var total = RGB.zero
        for y in 0..<edge {
            for x in 0..<edge {
                let r = hypot(Double(x - radius), Double(y - radius))
                var value = RGB.zero
                for (lambda, weight) in components {
                    value += weight * (exp(-r / lambda) / (2 * Double.pi * lambda * lambda))
                }
                pixels[y * edge + x] = value
                total += value
            }
        }
        for i in pixels.indices { pixels[i] /= total }
        return try .init(width: edge, height: edge, pixels: pixels)
    }
    static func radius(width: Int, height: Int, pixelSize: Double, parameters p: Parameters) throws -> Int {
        guard width > 0, height > 0 else { throw Failure.invalidParameter }
        guard pixelSize.isFinite, pixelSize > 0 else { throw Failure.invalidParameter }
        let cfg = try resolved(p)
        let maximum = cfg.centers.z * 2.5 * p.spatialScale / pixelSize
        guard maximum.isFinite else { throw Failure.invalidParameter }
        let limit = max(min(width, height) / 2 - 1, 1)
        return Int(min(ceil(max(8 * maximum, 5)), Double(limit)))
    }
    static func apply(_ image: SpatialCore.Image, pixelSize: Double, parameters p: Parameters) throws
        -> SpatialCore.Image
    {
        guard p.active, p.strength > 0, p.spatialScale > 0 else { return image }
        let fraction = try scatter(strength: p.strength, family: p.family)
        let radius = try radius(width: image.width, height: image.height, pixelSize: pixelSize, parameters: p)
        let psf = try kernel(radius: radius, pixelSize: pixelSize, parameters: p)
        let blurred = try convolve(image, kernel: psf, radius: radius)
        var output = image
        for i in output.pixels.indices {
            output.pixels[i] = image.pixels[i] * (1 - fraction) + blurred.pixels[i] * fraction
        }
        return output
    }
    /// Linear convolution with whole-sample mirror padding, matching np.pad(mode: reflect).
    /// Center-shifted circular embedding needs only image + two borders. The retained
    /// crop never samples the wrapped area, avoiding full-convolution padding overhead.
    static func convolve(_ image: SpatialCore.Image, kernel: SpatialCore.Image, radius: Int) throws
        -> SpatialCore.Image
    {
        func powerOfTwo(_ value: Int) -> (Int, Int) {
            var n = 1
            var log = 0
            while n < value {
                n *= 2
                log += 1
            }
            return (n, log)
        }
        let (width, lw) = powerOfTwo(image.width + 2 * radius)
        let (height, lh) = powerOfTwo(image.height + 2 * radius)
        guard let setup = vDSP_create_fftsetupD(vDSP_Length(max(lw, lh)), FFTRadix(kFFTRadix2)) else {
            throw Failure.fftSetup
        }
        defer { vDSP_destroy_fftsetupD(setup) }
        func transform(_ real: inout [Double], _ imaginary: inout [Double], _ direction: FFTDirection) {
            real.withUnsafeMutableBufferPointer { r in
                imaginary.withUnsafeMutableBufferPointer { i in
                    var split = DSPDoubleSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    vDSP_fft2d_zipD(setup, &split, 1, 0, vDSP_Length(lw), vDSP_Length(lh), direction)
                }
            }
        }
        func mirror(_ index: Int, _ count: Int) -> Int {
            if count == 1 { return 0 }
            let period = 2 * (count - 1)
            let p = ((index % period) + period) % period
            return p < count ? p : period - p
        }
        let count = width * height
        let paddedWidth = image.width + 2 * radius
        let paddedHeight = image.height + 2 * radius
        var output = image
        for channel in 0..<3 {
            var real = Array(repeating: 0.0, count: count)
            var imaginary = real
            var kr = real
            var ki = real
            for y in 0..<paddedHeight {
                for x in 0..<paddedWidth {
                    real[y * width + x] =
                        image.pixels[
                            mirror(y - radius, image.height) * image.width + mirror(x - radius, image.width)][
                            channel]
                }
            }
            for y in 0..<kernel.height {
                for x in 0..<kernel.width {
                    let row = (y - radius + height) % height
                    let column = (x - radius + width) % width
                    kr[row * width + column] = kernel.pixels[y * kernel.width + x][channel]
                }
            }
            transform(&real, &imaginary, FFTDirection(kFFTDirection_Forward))
            transform(&kr, &ki, FFTDirection(kFFTDirection_Forward))
            for i in 0..<count {
                let a = real[i]
                let b = imaginary[i]
                real[i] = a * kr[i] - b * ki[i]
                imaginary[i] = a * ki[i] + b * kr[i]
            }
            transform(&real, &imaginary, FFTDirection(kFFTDirection_Inverse))
            for y in 0..<image.height {
                for x in 0..<image.width {
                    output.pixels[y * image.width + x][channel] =
                        real[(y + radius) * width + x + radius] / Double(count)
                }
            }
        }
        return output
    }
}
