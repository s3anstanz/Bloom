import Foundation

/// Tells when a press of the mouse button became a file drag, from the drag pasteboard's change count: Finder writes
/// that pasteboard as a drag begins, so a change since the press means this press is dragging.
///
/// Bloom reads the count when it handles the press, which can be well after the press itself while the app is busy.
/// By then Finder may already have written the pasteboard for this very drag, so a press handled late keeps the
/// count from before instead of taking one that already includes the drag.
public struct DragStart {
    /// How long after a press Bloom can handle it and still read the count from before its drag began.
    public static let lateness: TimeInterval = 0.05
    private var baseline: Int

    public init(changeCount: Int) {
        baseline = changeCount
    }

    /// Records a press of the button that Bloom handled `late` seconds after it happened.
    public mutating func pressed(changeCount: Int, late: TimeInterval) {
        if late <= Self.lateness { baseline = changeCount }
    }

    /// Says whether a drag began since the press, and counts that drag as seen.
    public mutating func began(changeCount: Int) -> Bool {
        guard changeCount != baseline else { return false }
        baseline = changeCount
        return true
    }
}
