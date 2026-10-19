import CoreGraphics
import Foundation

/// Which petal the cursor points at. Petal 0 sits at 12 o'clock and the rest follow clockwise.
public enum PetalLayout {
    /// `offset` is the cursor relative to the flower's center, with y pointing up (AppKit coordinates).
    /// Returns nil inside the center, where letting go cancels, and outside the flower.
    public static func index(at offset: CGPoint, count: Int, innerRadius: CGFloat, outerRadius: CGFloat) -> Int? {
        let distance = hypot(offset.x, offset.y)
        guard count > 0, distance > innerRadius, distance <= outerRadius else { return nil }
        let slice = 2 * Double.pi / Double(count)
        var angle = atan2(Double(offset.x), Double(offset.y))
        if angle < 0 { angle += 2 * Double.pi }
        return Int((angle + slice / 2) / slice) % count
    }

    /// A petal pointing outward at `angle` (radians clockwise from 12 o'clock): narrow near `center`, round at the tip.
    /// Drawn with y pointing down, as in SwiftUI and flipped images. The flower and the menu bar icon share it.
    public static func outline(center: CGPoint, angle: Double, width: CGFloat, inner: CGFloat, outer: CGFloat) -> CGPath {
        let cosine = CGFloat(cos(angle))
        let sine = CGFloat(sin(angle))
        // `across` runs sideways over the petal; `out` runs from the flower's center toward the tip.
        func point(_ across: CGFloat, _ out: CGFloat) -> CGPoint {
            CGPoint(x: center.x + across * cosine + out * sine, y: center.y + across * sine - out * cosine)
        }
        let length = outer - inner
        let half = width / 2
        let path = CGMutablePath()
        path.move(to: point(0, inner))
        path.addCurve(
            to: point(0, outer),
            control1: point(half * 1.25, inner + length * 0.35),
            control2: point(half, outer + length * 0.06)
        )
        path.addCurve(
            to: point(0, inner),
            control1: point(-half, outer + length * 0.06),
            control2: point(-half * 1.25, inner + length * 0.35)
        )
        path.closeSubpath()
        return path
    }
}
