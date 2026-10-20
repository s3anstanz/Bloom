import Foundation

/// The row of tabs under the flower, one per flower in key order. Dragging over a tab switches to its flower.
public enum FlowerTabs {
    public static let modes: [Mode] = [.convert, .tools, .actions]

    /// `offset` is the cursor relative to the center of the row, with y pointing up (AppKit coordinates).
    /// Returns nil off the row.
    public static func mode(at offset: CGPoint, tabWidth: CGFloat, height: CGFloat) -> Mode? {
        let rowWidth = tabWidth * CGFloat(modes.count)
        guard abs(offset.y) <= height / 2, abs(offset.x) < rowWidth / 2 else { return nil }
        return modes[Int((offset.x + rowWidth / 2) / tabWidth)]
    }
}
