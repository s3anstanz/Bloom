import Foundation

/// The faint ⇧ ⌘ ⌃ keys beside the pointer that remind someone new how to open a flower. They fade in once a file
/// drag has gone a moment without a key, so quick drags to the Trash or a folder never see them, and they stop for good
/// once any flower has opened, on this launch or a later one.
public struct KeyHint {
    /// How long a drag goes without a key before the hint shows.
    public static let delay: TimeInterval = 1
    /// How far right of the pointer, and above it, the hint starts. Finder drags a file's icon centred on where it was
    /// picked up with its name below, and a list row's name to the pointer's right, so this keeps the hint off both.
    public static let clearance = CGSize(width: 44, height: 14)
    /// How far below the pointer a dragged icon's name can reach, for when the hint has to go below.
    public static let nameReach: CGFloat = 76
    /// The setting that records a flower has opened.
    public static let retiredKey = "keyHintRetired"

    private let defaults: UserDefaults
    private var dragStartedAt: TimeInterval?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True once a flower has opened, so the hint never shows again.
    public var isRetired: Bool {
        defaults.bool(forKey: Self.retiredKey)
    }

    /// A drag of files began at `time`, on the clock `isShowing(at:)` reads.
    public mutating func dragStarted(at time: TimeInterval) {
        dragStartedAt = time
    }

    /// A key opened a flower. The hint goes, and stays gone.
    public mutating func flowerOpened() {
        dragStartedAt = nil
        defaults.set(true, forKey: Self.retiredKey)
    }

    public mutating func dragEnded() {
        dragStartedAt = nil
    }

    public func isShowing(at time: TimeInterval) -> Bool {
        guard let dragStartedAt, !isRetired else { return false }
        return time - dragStartedAt >= Self.delay
    }

    /// Where a hint of `size` goes for a pointer at `pointer`, in AppKit screen coordinates (y up): above and right of
    /// the pointer, clear of the dragged icon and its name, flipped to the left or below where the screen runs out.
    public static func origin(for pointer: CGPoint, size: CGSize, in screen: CGRect) -> CGPoint {
        var x = pointer.x + clearance.width
        if x + size.width > screen.maxX { x = pointer.x - clearance.width - size.width }
        var y = pointer.y + clearance.height
        if y + size.height > screen.maxY { y = pointer.y - nameReach - size.height }
        return CGPoint(x: x, y: y)
    }
}
