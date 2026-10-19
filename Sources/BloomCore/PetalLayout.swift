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

/// Choices that bloom past a petal's tip, like Compress's sizes: side by side, centered on the petal, beyond the glass.
public enum ChoiceLayout {
    /// Radians between neighbouring choices.
    public static let spread = Double.pi / 6
    public static let innerRadius: CGFloat = 156
    public static let outerRadius: CGFloat = 222
    public static let width: CGFloat = 58

    /// Radians clockwise from 12 o'clock of choice `index` of `count`, around a petal pointing at `petalAngle`.
    public static func angle(of index: Int, count: Int, around petalAngle: Double) -> Double {
        petalAngle + (Double(index) - Double(count - 1) / 2) * spread
    }

    /// Which choice the cursor points at. `offset` is relative to the flower's center, with y pointing up (AppKit
    /// coordinates). The choices answer from the glass's edge outward, so moving out from the petal never crosses a gap.
    public static func index(at offset: CGPoint, count: Int, around petalAngle: Double, glassRadius: CGFloat) -> Int? {
        let distance = hypot(offset.x, offset.y)
        guard count > 0, distance > glassRadius, distance <= outerRadius + 8 else { return nil }
        let relative = remainder(atan2(Double(offset.x), Double(offset.y)) - petalAngle, 2 * Double.pi)
        let slot = (relative / spread + Double(count - 1) / 2).rounded()
        guard slot >= 0, slot < Double(count) else { return nil }
        return Int(slot)
    }
}
