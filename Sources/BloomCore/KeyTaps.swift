/// The modifier keys that open a flower while a file is being dragged.
public enum ModifierKey: Hashable {
    case shift, command, control
}

/// Turns the keys held during one drag into flower changes.
///
/// A key counts when it goes down, so the open flower stays after the key is released, and tapping another
/// key switches flowers. Finder uses ⌘ and ⌃ while dragging (move and make alias), so if either is already
/// held when the drag starts it must be pressed again; ⇧ has no Finder meaning and opens Convert at once.
public struct KeyTaps {
    private var held: Set<ModifierKey>
    public private(set) var isOpen = false

    public init(heldAtDragStart: Set<ModifierKey>) {
        held = heldAtDragStart.subtracting([.shift])
    }

    /// Returns the flower for a key that just went down, otherwise nil. Pressing the open flower's key again
    /// reports it again, so a key always brings its flower back after a tab switched away from it.
    public mutating func update(held now: Set<ModifierKey>) -> Mode? {
        let pressed = now.subtracting(held)
        held = now
        let mode: Mode
        if pressed.contains(.shift) {
            mode = .convert
        } else if pressed.contains(.command) {
            mode = .tools
        } else if pressed.contains(.control) {
            mode = .actions
        } else {
            return nil
        }
        isOpen = true
        return mode
    }
}
