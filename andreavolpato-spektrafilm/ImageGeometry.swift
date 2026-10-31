import CoreGraphics
import Foundation

/// Applied before the normalized crop rectangle. Positive angles turn left.
nonisolated struct ImageGeometry: Codable, Equatable, Sendable {
    var quarterTurns = 0
    var straightenDegrees = 0.0
    var flippedHorizontally = false
    var flippedVertically = false

    var isIdentity: Bool { self == ImageGeometry() }

    mutating func rotateLeft() {
        quarterTurns = (quarterTurns + 1) % 4
        swap(&flippedHorizontally, &flippedVertically)
    }

    mutating func flipHorizontal() {
        flippedHorizontally.toggle()
        straightenDegrees = -straightenDegrees
    }

    mutating func flipVertical() {
        flippedVertically.toggle()
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
}
