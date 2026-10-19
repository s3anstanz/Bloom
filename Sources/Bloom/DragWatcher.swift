import AppKit
import BloomCore

/// Watches for file drags anywhere on screen and opens the flower when ⇧, ⌘ or ⌃ is tapped mid-drag.
@MainActor
final class DragWatcher: NSObject {
    private let radial: RadialController
    private let pasteboard = NSPasteboard(name: .drag)
    private var dragStart = DragStart(changeCount: 0)
    private var files: [URL] = []
    private var taps = KeyTaps(heldAtDragStart: [])
    private var timer: Timer?

    init(radial: RadialController) {
        self.radial = radial
        super.init()
    }

    func start() {
        dragStart = DragStart(changeCount: pasteboard.changeCount)
        // Global mouse monitors need no Accessibility permission (only key monitors do).
        _ = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            let pressedAt = event.timestamp
            Task { @MainActor in self.mouseDown(pressedAt: pressedAt) }
        }
        _ = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
            Task { @MainActor in self.mouseDragged() }
        }
    }

    /// `pressedAt` is the press's time since the Mac started, the clock `systemUptime` reads.
    private func mouseDown(pressedAt: TimeInterval) {
        let late = ProcessInfo.processInfo.systemUptime - pressedAt
        if late > DragStart.lateness {
            dragLog.notice("Mouse button down \(late, format: .fixed(precision: 2), privacy: .public) s before Bloom saw it")
        }
        dragStart.pressed(changeCount: pasteboard.changeCount, late: late)
    }

    private func mouseDragged() {
        guard timer == nil, dragStart.began(changeCount: pasteboard.changeCount) else { return }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        files = urls
        dragLog.notice("Drag started with \(urls.count, privacy: .public) files")
        taps = KeyTaps(heldAtDragStart: Self.heldKeys())
        MenuBarIcon.shared.dragStarted()
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
        dragLog.notice("Mouse button up; flower open: \(self.taps.isOpen, privacy: .public)")
        if taps.isOpen { radial.dragEnded() }
        MenuBarIcon.shared.dragEnded()
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
