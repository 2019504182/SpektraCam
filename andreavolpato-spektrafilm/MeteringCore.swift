// Auto-exposure methods and preview sampling from spektrafilm 3bb2c2d. GPLv3.
import Foundation

nonisolated enum MeteringCore {
    struct Image: Sendable {
        let width: Int, height: Int, luminance: [Double]
        init(width: Int, height: Int, luminance: [Double]) throws {
            guard width > 0, height > 0, luminance.count == width * height else {
                throw SpectralCore.Failure.invalidShape
            }
            self.width = width
            self.height = height
            self.luminance = luminance
        }
        func smallPreview(maximum: Int = 256) throws -> Image {
            guard max(width, height) > maximum else { return self }
            let scale = Double(maximum) / Double(max(width, height))
            let outWidth = max(1, Int((Double(width) * scale).rounded(.toNearestOrEven)))
            let outHeight = max(1, Int((Double(height) * scale).rounded(.toNearestOrEven)))
            let sigmaY = max(0, (Double(height) / Double(outHeight) - 1) / 2)
            let sigmaX = max(0, (Double(width) / Double(outWidth) - 1) / 2)
            // skimage rescale(order: 0) applies Gaussian anti-aliasing for float images.
            var filtered = gaussian(luminance, sigma: sigmaY, vertical: true)
            filtered = gaussian(filtered, sigma: sigmaX, vertical: false)
            var output = [Double]()
            output.reserveCapacity(outWidth * outHeight)
            for y in 0..<outHeight {
                let sourceY = min(
                    height - 1, Int(floor((Double(y) + 0.5) * Double(height) / Double(outHeight))))
                for x in 0..<outWidth {
                    let sourceX = min(
                        width - 1, Int(floor((Double(x) + 0.5) * Double(width) / Double(outWidth))))
                    output.append(filtered[sourceY * width + sourceX])
                }
            }
            return try Image(width: outWidth, height: outHeight, luminance: output)
        }
        func exposureEV(method: String) -> Double {
            let mean = luminance.reduce(0, +) / Double(luminance.count)
            let measured: Double
            switch method {
            case "average": measured = mean
            case "median":
                let sorted = luminance.sorted()
                let middle = sorted.count / 2
                measured = sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
            case "center_weighted", "partial", "multi_zone":
                let long = Double(max(width, height))
                var weighted = 0.0
                var total = 0.0
                var ringSums = [0.0, 0.0, 0.0]
                var ringCounts = [0, 0, 0]
                for y in 0..<height {
                    for x in 0..<width {
                        let nx = (Double(x) / Double(width) - 0.5) * Double(width) / long
                        let ny = (Double(y) / Double(height) - 0.5) * Double(height) / long
                        let r = hypot(nx, ny)
                        let value = luminance[y * width + x]
                        if method == "center_weighted" {
                            let weight = exp(-(nx * nx + ny * ny) / (2 * 0.2 * 0.2))
                            weighted += value * weight
                            total += weight
                        } else if method == "partial" {
                            if r < 0.15 {
                                weighted += value
                                total += 1
                            }
                        } else {
                            let ring = r < 0.05 ? 0 : r < 0.25 ? 1 : r < 0.5 ? 2 : -1
                            if ring >= 0 {
                                ringSums[ring] += value
                                ringCounts[ring] += 1
                            }
                        }
                    }
                }
                if method == "multi_zone" {
                    for i in 0..<3 where ringCounts[i] > 0 {
                        let weight = [0.5, 0.3, 0.2][i]
                        weighted += weight * ringSums[i] / Double(ringCounts[i])
                        total += weight
                    }
                }
                measured = total > 0 ? weighted / total : mean
            case "matrix":
                let cellHeight = height / 5
                let cellWidth = width / 5
                var weighted = 0.0
                var total = 0.0
                if cellHeight > 0 && cellWidth > 0 {
                    for r in 0..<5 {
                        for c in 0..<5 {
                            var sum = 0.0
                            for y in (r * cellHeight)..<((r + 1) * cellHeight) {
                                for x in (c * cellWidth)..<((c + 1) * cellWidth) {
                                    sum += luminance[y * width + x]
                                }
                            }
                            let distance = hypot(Double(r - 2) / 2, Double(c - 2) / 2) / sqrt(2)
                            let weight = (1 + cos(.pi * distance)) / 2
                            weighted += weight * sum / Double(cellHeight * cellWidth)
                            total += weight
                        }
                    }
                }
                measured = total > 0 ? weighted / total : 0
            case "highlight_weighted":
                let total = luminance.reduce(0) { $0 + $1 * $1 }
                measured = total < 1e-12 ? mean : luminance.reduce(0) { $0 + $1 * $1 * $1 } / total
            default: return 0
            }
            let ev = -log2(measured / 0.184)
            return ev.isInfinite ? 0 : ev
        }
        private func gaussian(_ source: [Double], sigma: Double, vertical: Bool) -> [Double] {
            guard sigma > 1e-15 else { return source }
            let radius = Int(4 * sigma + 0.5)
            var kernel = (-radius...radius).map { exp(-0.5 * Double($0 * $0) / (sigma * sigma)) }
            let sum = kernel.reduce(0, +)
            kernel = kernel.map { $0 / sum }
            func mirror(_ index: Int, _ size: Int) -> Int {
                if size == 1 { return 0 }
                let period = 2 * (size - 1)
                let normalized = ((index % period) + period) % period
                return normalized < size ? normalized : period - normalized
            }
            var output = source
            for y in 0..<height {
                for x in 0..<width {
                    var value = 0.0
                    for i in -radius...radius {
                        let sy = vertical ? mirror(y + i, height) : y
                        let sx = vertical ? x : mirror(x + i, width)
                        value += source[sy * width + sx] * kernel[i + radius]
                    }
                    output[y * width + x] = value
                }
            }
            return output
        }
    }
}
