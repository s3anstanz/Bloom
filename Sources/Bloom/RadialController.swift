import AppKit
import BloomCore
import SwiftUI

enum RadialLayout {
    static let size = CGSize(width: 340, height: 384)
    /// Flower center in SwiftUI coordinates (origin at top-left).
    static let ringCenter = CGPoint(x: 170, y: 170)
    static let ringRadius: CGFloat = 150
    static let hubRadius: CGFloat = 50
}

@MainActor
final class RadialModel: ObservableObject {
    enum Phase: Equatable {
        case choosing, working, done, failed
    }

    @Published var items: [WheelItem] = []
    @Published var itemsLoaded = false
    @Published var highlighted: Int?
    @Published var phase: Phase = .choosing
    @Published var status: String?
    @Published var mode: Mode = .convert
    @Published var icon: NSImage?
    @Published var fileCount = 0
    @Published var isVisible = false
}

/// Owns the floating flower window: placement, hover selection, and running the chosen petal.
@MainActor
final class RadialController {
    let model = RadialModel()
    private var files: [URL] = []
    private var hideTask: Task<Void, Never>?
    private var presentation = 0
    private lazy var panel: NSPanel = makePanel()

    func present(mode: Mode, files: [URL]) {
        guard model.phase != .working else { return }
        hideTask?.cancel()
        let isNewDrag = !panel.isVisible || !model.isVisible || model.phase != .choosing
        self.files = files
        model.mode = mode
        model.items = []
        model.itemsLoaded = false
        model.highlighted = nil
        model.phase = .choosing
        model.status = nil
        model.fileCount = files.count
        model.icon =
            files.count == 1
            ? NSWorkspace.shared.icon(forFile: files[0].path)
            : NSWorkspace.shared.icon(forFiles: files.map(\.path))
        if isNewDrag { place(at: NSEvent.mouseLocation) }
        panel.orderFrontRegardless()
        if !model.isVisible {
            Task { @MainActor in self.model.isVisible = true }
        }
        presentation += 1
        let current = presentation
        Task { @MainActor in
            let items = await WheelCatalog.items(for: files, mode: mode)
            guard current == self.presentation, self.model.phase == .choosing else { return }
            self.model.items = items
            self.model.itemsLoaded = true
        }
    }

    func dragEnded() {
        if model.phase == .choosing { dismiss(after: 0) }
    }

    /// `offset` is the cursor position relative to the flower's center, y pointing up.
    @discardableResult
    func hover(_ offset: CGPoint?) -> Bool {
        let index = offset.flatMap { itemIndex(at: $0) }
        if index != model.highlighted {
            model.highlighted = index
            if index != nil {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        return index != nil
    }

    func performDrop() -> Bool {
        guard model.phase == .choosing,
            let index = model.highlighted,
            model.items.indices.contains(index)
        else { return false }
        let item = model.items[index]
        let files = self.files
        // DragWatcher can see the mouse-up first and start hiding the flower before this drop arrives.
        hideTask?.cancel()
        model.isVisible = true
        model.phase = .working
        model.status = item.progress
        Task { @MainActor in
            do {
                let message: String
                switch item.operation {
                case .convert(let format):
                    let outputs = try await Engine.convert(files, to: format)
                    message = Self.savedMessage(outputs)
                case .tool(let tool):
                    let outputs = try await Engine.apply(tool, to: files)
                    message = Self.savedMessage(outputs)
                case .action(let action):
                    if action == .move { self.hideNow() }
                    guard let result = try QuickActions.run(action, on: files) else {
                        self.hideNow()
                        return
                    }
                    message = result
                }
                self.model.phase = .done
                self.model.status = message
                NSSound(named: "Pop")?.play()
                self.dismiss(after: 1.4)
            } catch {
                self.model.phase = .failed
                self.model.status = error.localizedDescription
                self.dismiss(after: 4)
            }
        }
        return true
    }

    private static func savedMessage(_ outputs: [URL]) -> String {
        outputs.count == 1 ? "Saved \(outputs[0].lastPathComponent)" : "Saved \(outputs.count) files"
    }

    private func itemIndex(at offset: CGPoint) -> Int? {
        guard model.phase == .choosing else { return nil }
        return PetalLayout.index(
            at: offset,
            count: model.items.count,
            innerRadius: RadialLayout.hubRadius,
            outerRadius: RadialLayout.ringRadius
        )
    }

    private func hideNow() {
        hideTask?.cancel()
        model.isVisible = false
        panel.orderOut(nil)
        model.items = []
    }

    private func dismiss(after delay: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.model.isVisible = false
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self.panel.orderOut(nil)
            self.model.phase = .choosing
            self.model.highlighted = nil
            // Emptying the petals makes the next drag's petals appear fresh, so they bloom again.
            self.model.items = []
        }
    }

    private func place(at point: NSPoint) {
        let size = RadialLayout.size
        var origin = NSPoint(
            x: point.x - RadialLayout.ringCenter.x,
            y: point.y - (size.height - RadialLayout.ringCenter.y)
        )
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            let frame = screen.frame
            origin.x = min(max(origin.x, frame.minX), frame.maxX - size.width)
            origin.y = min(max(origin.y, frame.minY), frame.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
    }

    private func makePanel() -> NSPanel {
        let frame = NSRect(origin: .zero, size: RadialLayout.size)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let host = NSHostingView(rootView: FlowerView(model: model))
        host.frame = frame
        host.autoresizingMask = [.width, .height]
        let dropTarget = DropTargetView(frame: frame)
        dropTarget.autoresizingMask = [.width, .height]
        dropTarget.controller = self

        let container = NSView(frame: frame)
        container.addSubview(host)
        container.addSubview(dropTarget)
        panel.contentView = container
        return panel
    }
}

/// Transparent layer above the SwiftUI flower that receives the Finder drag.
final class DropTargetView: NSView {
    weak var controller: RadialController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        controller?.hover(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        controller?.performDrop() ?? false
    }

    private func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let offset = CGPoint(
            x: point.x - RadialLayout.ringCenter.x,
            y: point.y - (bounds.height - RadialLayout.ringCenter.y)
        )
        guard controller?.hover(offset) == true else { return [] }
        // Finder narrows the operation to .generic while ⌘ is held and .link while ⌃ is held; refusing those would bounce the drop.
        let allowed = sender.draggingSourceOperationMask
        return [NSDragOperation.copy, .generic, .link].first { allowed.contains($0) } ?? []
    }
}
