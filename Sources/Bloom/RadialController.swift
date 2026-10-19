import AppKit
import BloomCore
import SwiftUI

enum RadialLayout {
    static let size = CGSize(width: 340, height: 420)
    /// Flower center in SwiftUI coordinates (origin at top-left).
    static let ringCenter = CGPoint(x: 170, y: 170)
    static let ringRadius: CGFloat = 150
    static let hubRadius: CGFloat = 50
    /// How far below the flower's center the tab row's center sits.
    static let tabsDrop: CGFloat = 182
    static let tabSize = CGSize(width: 96, height: 30)
    /// Waiting this long on a tab before switching keeps an overshoot past the bottom petal from changing flowers.
    static let tabDwell: Double = 0.2
}

@MainActor
final class RadialModel: ObservableObject {
    enum Phase: Equatable {
        case choosing, working, done, failed
    }

    @Published var items: [WheelItem] = []
    @Published var itemsLoaded = false
    @Published var highlighted: Int?
    @Published var hoveredTab: Mode?
    @Published var phase: Phase = .choosing
    @Published var status: String?
    @Published var mode: Mode = .convert
    @Published var icon: NSImage?
    @Published var fileCount = 0
    @Published var isVisible = false
    @Published var timeline = FlowerTimeline()
    @Published var isAnimating = false
    /// Set by `Bloom --preview` to draw the flower at that instant instead of following the clock.
    @Published var clock: TimeInterval?
}

/// Owns the floating flower window: placement, hover selection, and running the chosen petal.
@MainActor
final class RadialController {
    let model = RadialModel()
    private var files: [URL] = []
    private var hideTask: Task<Void, Never>?
    private var tabTask: Task<Void, Never>?
    private var presentation = 0
    private var motionRun = 0
    private lazy var panel: NSPanel = makePanel()

    func present(mode: Mode, files: [URL]) {
        guard model.phase != .working else { return }
        hideTask?.cancel()
        let isNewDrag = !panel.isVisible || !model.isVisible || model.phase != .choosing || model.timeline.closed != nil
        if !isNewDrag, model.mode == mode, files == self.files { return }
        if isNewDrag {
            tabTask?.cancel()
            model.hoveredTab = nil
        }
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
        var timeline = FlowerTimeline(entrance: isNewDrag ? .bloom : .turn, opened: Self.now)
        if !isNewDrag { timeline.glassOpened = model.timeline.glassOpened }
        model.timeline = timeline
        animate()
        panel.orderFrontRegardless()
        model.isVisible = true
        presentation += 1
        let current = presentation
        Task { @MainActor in
            let items = await WheelCatalog.items(for: files, mode: mode)
            guard current == self.presentation, self.model.phase == .choosing else { return }
            self.model.items = items
            self.model.itemsLoaded = true
            self.model.timeline.petalsShown = Self.now
            self.animate()
        }
    }

    /// Letting go anywhere but on a petal folds the flower away.
    func dragEnded() {
        guard model.phase == .choosing, model.timeline.closed == nil else { return }
        model.timeline.closed = Self.now
        animate()
        dismiss(after: FlowerMotion.closeDuration)
    }

    /// `offset` is the cursor position relative to the flower's center, y pointing up.
    @discardableResult
    func hover(_ offset: CGPoint?) -> Bool {
        // After the button comes up the flower folds, but the drag can still report where it was let go before it
        // delivers the drop. Petals keep answering so that drop lands on the petal under it; AppKit cancels a drop
        // whose last report found none. Tabs stop switching flowers.
        let isFolding = model.timeline.closed != nil
        if !isFolding {
            hoverTab(offset.flatMap { tab(at: $0) })
        }
        let index = offset.flatMap { itemIndex(at: $0) }
        if index != model.highlighted {
            model.highlighted = index
            if index != nil, !isFolding {
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
        // DragWatcher can see the mouse-up first and start folding the flower away before this drop arrives.
        hideTask?.cancel()
        model.isVisible = true
        model.timeline.closed = nil
        model.phase = .working
        model.status = item.progress
        model.timeline.dropped = Self.now
        model.timeline.chosen = index
        animate()
        MenuBarIcon.shared.working()
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
                        MenuBarIcon.shared.finished(saved: false)
                        return
                    }
                    message = result
                }
                self.model.phase = .done
                self.model.status = message
                self.finish(succeeded: true)
                MenuBarIcon.shared.finished(saved: true)
                NSSound(named: "Pop")?.play()
                self.dismiss(after: 1.4)
            } catch {
                IssueLink.lastFailure = IssueReport.Failure(
                    petal: item.title,
                    mode: self.model.mode,
                    files: files,
                    message: error.localizedDescription
                )
                self.model.phase = .failed
                self.model.status = error.localizedDescription
                self.finish(succeeded: false)
                MenuBarIcon.shared.finished(saved: false)
                self.dismiss(after: 4)
            }
        }
        return true
    }

    private func finish(succeeded: Bool) {
        model.timeline.finish(succeeded: succeeded, at: Self.now)
        animate()
    }

    /// Keeps the flower's animation clock running until its latest moment settles, then lets it rest.
    private func animate() {
        motionRun += 1
        let run = motionRun
        model.isAnimating = true
        let remaining = FlowerMotion.endTime(of: model.timeline, petals: model.items.count) - Self.now
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(remaining, 0) * 1_000_000_000))
            guard run == self.motionRun else { return }
            self.model.isAnimating = false
        }
    }

    private static var now: TimeInterval {
        Date().timeIntervalSinceReferenceDate
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

    private func tab(at offset: CGPoint) -> Mode? {
        guard model.phase == .choosing else { return nil }
        return FlowerTabs.mode(
            at: CGPoint(x: offset.x, y: offset.y + RadialLayout.tabsDrop),
            tabWidth: RadialLayout.tabSize.width,
            height: RadialLayout.tabSize.height
        )
    }

    private func hoverTab(_ mode: Mode?) {
        guard mode != model.hoveredTab else { return }
        model.hoveredTab = mode
        tabTask?.cancel()
        guard let mode, mode != model.mode else { return }
        tabTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(RadialLayout.tabDwell * 1_000_000_000))
            guard !Task.isCancelled, self.model.mode != mode else { return }
            self.present(mode: mode, files: self.files)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    private func hideNow() {
        hideTask?.cancel()
        tabTask?.cancel()
        model.isVisible = false
        panel.orderOut(nil)
        model.items = []
    }

    private func dismiss(after delay: Double) {
        hideTask?.cancel()
        tabTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.model.isVisible = false
            try? await Task.sleep(nanoseconds: 260_000_000)
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
