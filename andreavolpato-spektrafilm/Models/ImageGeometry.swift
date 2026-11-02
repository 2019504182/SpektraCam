import CoreGraphics
import Foundation

/// Applied before the normalized crop rectangle. Positive angles turn left.
nonisolated struct ImageGeometry: Codable, Equatable, Sendable {
    var quarterTurns = 0
    var straightenDegrees = 0.0
    var flippedHorizontally = false
    var flippedVertically = false
    var framingX = 0.0
    var framingY = 0.0

    var isIdentity: Bool { self == ImageGeometry() }

    mutating func rotateLeft() {
        quarterTurns = (quarterTurns + 1) % 4
        swap(&flippedHorizontally, &flippedVertically)
        let previousX = framingX
        framingX = framingY
        framingY = -previousX
    }

    mutating func flipHorizontal() {
        flippedHorizontally.toggle()
        framingX = -framingX
        straightenDegrees = -straightenDegrees
    }

    mutating func flipVertical() {
        flippedVertically.toggle()
        framingY = -framingY
        straightenDegrees = -straightenDegrees
    }

    /// Zoom needed to keep all output corners inside the rotated source.
    /// This preserves the frame's original aspect and avoids transparent borders.
    func constrainedScale(in size: CGSize) -> CGFloat {
        guard straightenDegrees != 0 else { return 1 }
        let angle = abs(straightenDegrees) * .pi / 180
        let c = cos(angle)
        let s = sin(angle)
        let required = max(c + size.height / size.width * s, c + size.width / size.height * s)
        return required + 2 / min(size.width, size.height)
    }
    /// Clamp translation in the source's rotated axes. Panning never changes scale.
    func boundedFraming(in size: CGSize) -> CGPoint {
        guard straightenDegrees != 0, size.width > 0, size.height > 0 else { return .zero }
        let angle = straightenDegrees * .pi / 180
        let c = cos(angle), s = sin(angle)
        let zoom = constrainedScale(in: size)
        let marginX = max(0, (zoom * size.width - abs(c) * size.width - abs(s) * size.height) / 2)
        let marginY = max(0, (zoom * size.height - abs(s) * size.width - abs(c) * size.height) / 2)
        let tx = framingX * size.width, ty = -framingY * size.height
        let u = min(max(c * tx + s * ty, -marginX), marginX)
        let v = min(max(-s * tx + c * ty, -marginY), marginY)
        return CGPoint(x: (c * u - s * v) / size.width, y: -(s * u + c * v) / size.height)
    }

}

extension ImageGeometry {
    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        quarterTurns = try values.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0
        straightenDegrees = try values.decodeIfPresent(Double.self, forKey: .straightenDegrees) ?? 0
        flippedHorizontally = try values.decodeIfPresent(Bool.self, forKey: .flippedHorizontally) ?? false
        flippedVertically = try values.decodeIfPresent(Bool.self, forKey: .flippedVertically) ?? false
        framingX = try values.decodeIfPresent(Double.self, forKey: .framingX) ?? 0
        framingY = try values.decodeIfPresent(Double.self, forKey: .framingY) ?? 0
    }
}
