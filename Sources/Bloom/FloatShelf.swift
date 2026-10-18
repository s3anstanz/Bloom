import AppKit

/// Floating cards that hold files on screen so they can be dragged somewhere later.
@MainActor
final class FloatShelf {
    static let shared = FloatShelf()

    private var panels: [NSPanel] = []

    func show(_ files: [URL], near point: NSPoint) {
        let size = FloatCardView.size
        let frame = NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = FloatCardView(files: files) { [weak self, weak panel] in
            guard let card = panel else { return }
            card.orderOut(nil)
            self?.panels.removeAll { $0 === card }
        }
        panel.orderFrontRegardless()
        panels.append(panel)
    }
}

final class FloatCardView: NSView {
    static let size = NSSize(width: 132, height: 140)

    private let onClose: () -> Void

    init(files: [URL], onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(frame: NSRect(origin: .zero, size: FloatCardView.size))

        let background = NSVisualEffectView(frame: bounds)
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = NSImage(size: FloatCardView.size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22).fill()
            return true
        }
        addSubview(background)

        let icon = FileDragView(frame: NSRect(x: (FloatCardView.size.width - 72) / 2, y: 44, width: 72, height: 72))
        icon.files = files
        icon.image =
            files.count == 1
            ? NSWorkspace.shared.icon(forFile: files[0].path)
            : NSWorkspace.shared.icon(forFiles: files.map(\.path))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.onDelivered = onClose
        addSubview(icon)

        let label = NSTextField(labelWithString: files.count == 1 ? files[0].lastPathComponent : "\(files.count) files")
        label.frame = NSRect(x: 10, y: 18, width: FloatCardView.size.width - 20, height: 16)
        label.alignment = .center
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(label)

        let close = NSButton(frame: NSRect(x: 8, y: FloatCardView.size.height - 26, width: 18, height: 18))
        close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        close.imageScaling = .scaleProportionallyUpOrDown
        close.contentTintColor = .white
        close.target = self
        close.action = #selector(closeCard)
        addSubview(close)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    @objc private func closeCard() {
        onClose()
    }
}

/// The card's icon: dragging it hands the files to wherever they're dropped, then the card closes.
final class FileDragView: NSImageView, NSDraggingSource {
    var files: [URL] = []
    var onDelivered: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else { return }
        for file in files {
            NSWorkspace.shared.open(file)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let items = files.map { file -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: file as NSURL)
            item.setDraggingFrame(bounds, contents: image)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if !operation.isEmpty { onDelivered?() }
    }
}
