import AppKit
import BloomCore

/// Watches for file drags anywhere on screen and opens the flower when ⇧, ⌘ or ⌃ is tapped mid-drag.
@MainActor
final class DragWatcher: NSObject {
    private let radial: RadialController
    private let pasteboard = NSPasteboard(name: .drag)
    private var baseline = 0
    private var files: [URL] = []
    private var taps = KeyTaps(heldAtDragStart: [])
    private var timer: Timer?

    init(radial: RadialController) {
        self.radial = radial
        super.init()
    }

    func start() {
        baseline = pasteboard.changeCount
        // Global mouse monitors need no Accessibility permission (only key monitors do).
        _ = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            Task { @MainActor in self.mouseDown() }
        }
        _ = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
            Task { @MainActor in self.mouseDragged() }
        }
    }

    private func mouseDown() {
        baseline = pasteboard.changeCount
    }

    private func mouseDragged() {
        guard timer == nil, pasteboard.changeCount != baseline else { return }
        baseline = pasteboard.changeCount
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        files = urls
        taps = KeyTaps(heldAtDragStart: Self.heldKeys())
        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    @objc private func tick() {
        guard NSEvent.pressedMouseButtons & 1 == 1 else {
            finish()
            return
        }
        if let mode = taps.update(held: Self.heldKeys()) {
            radial.present(mode: mode, files: files)
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        if taps.isOpen { radial.dragEnded() }
        taps = KeyTaps(heldAtDragStart: [])
    }

    private static func heldKeys() -> Set<ModifierKey> {
        let flags = NSEvent.modifierFlags
        var keys: Set<ModifierKey> = []
        if flags.contains(.shift) { keys.insert(.shift) }
        if flags.contains(.command) { keys.insert(.command) }
        if flags.contains(.control) { keys.insert(.control) }
        return keys
    }
}
