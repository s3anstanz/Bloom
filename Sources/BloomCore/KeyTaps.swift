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
    private var shown: Mode?

    public init(heldAtDragStart: Set<ModifierKey>) {
        held = heldAtDragStart.subtracting([.shift])
    }

    public var isOpen: Bool { shown != nil }

    /// Returns the flower to show when a newly pressed key changes it, otherwise nil.
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
        guard mode != shown else { return nil }
        shown = mode
        return mode
    }
}
