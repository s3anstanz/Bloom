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
}
