import AppKit
import BloomCore
import SwiftUI
import UniformTypeIdentifiers

enum HelpLayout {
    /// Room around the glass for its shadow. Clicks pass through the clear part of the window.
    static let margin: CGFloat = 48
    static let cardWidth: CGFloat = 360
    static let guideWidth: CGFloat = 440
    static let padding: CGFloat = 20
    static let flowerSide: CGFloat = 320
    static let captionHeight: CGFloat = 56
}

@MainActor
final class HelpModel: ObservableObject {
    enum Showing {
        case card, guide
    }

    @Published var showing = Showing.card
    @Published var kind = FieldGuide.Kind.photo
    @Published var mode = Mode.convert
    /// Counts each time the glass appears, so it comes in and its light sweeps across once more.
    @Published var appearance = 0
    /// Where along the glass's top its pointer meets the menu bar icon, or nil when the icon can't be seen.
    @Published var pointerX: CGFloat?
}

/// The first-launch card and the field guide, in one glass panel under the menu bar icon. The guide only shows the
/// petals: nothing in it runs, and it stays open while the person drags a file to try one for real.
@MainActor
final class FieldGuidePanel {
    static let shared = FieldGuidePanel()

    private let model = HelpModel()
    private let flower = RadialModel()
    private let card = FirstLaunchCard()
    private lazy var panel: NSPanel = makePanel()
    private var motionRun = 0

    /// Shows the card under the icon on Bloom's first launch, until it's answered.
    func introduceIfDue() {
        guard card.isDue else { return }
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
            // Opening Bloom's menu answers the card too: What Can Bloom Do? is right there.
            Task { @MainActor in
                guard self.isShowing(.card) else { return }
                self.notNow()
            }
        }
        Task { @MainActor in
            // The menu bar icon's window appears a moment after launch.
            for _ in 0..<30 where Self.iconFrame() == nil {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard self.card.isDue else { return }
            self.present(.card)
        }
    }

    /// Opening the guide answers the card, even one still waiting for the menu bar icon, so it never replaces the guide.
    func showGuide() {
        card.answered()
        present(.guide)
    }

    func close() {
        dragLog.notice("Closing the \(self.model.showing == .card ? "first-launch card" : "field guide", privacy: .public)")
        panel.orderOut(nil)
        flower.highlighted = nil
    }

    private func notNow() {
        card.answered()
        close()
    }

    private func isShowing(_ showing: HelpModel.Showing) -> Bool {
        panel.isVisible && model.showing == showing
    }

    private func present(_ showing: HelpModel.Showing) {
        model.showing = showing
        model.appearance += 1
        if showing == .guide {
            flower.highlighted = nil
            showFlower(turning: false)
        }
        let icon = Self.iconFrame().map { "\(Int($0.minX)), \(Int($0.minY))" } ?? "not on screen"
        dragLog.notice(
            "Showing the \(showing == .card ? "first-launch card" : "field guide", privacy: .public); icon \(icon, privacy: .public)")
        place()
        panel.orderFrontRegardless()
    }

    private func pick(_ kind: FieldGuide.Kind) {
        guard kind != model.kind else { return }
        model.kind = kind
        showFlower(turning: true)
    }

    private func pick(_ mode: Mode) {
        guard mode != model.mode else { return }
        model.mode = mode
        showFlower(turning: true)
    }

    /// `offset` is the pointer relative to the flower's center, y pointing up, or nil once it leaves the flower.
    private func point(_ offset: CGPoint?) {
        let index = offset.flatMap {
            PetalLayout.index(at: $0, count: flower.items.count, innerRadius: RadialLayout.hubRadius, outerRadius: RadialLayout.ringRadius)
        }
        guard index != flower.highlighted else { return }
        flower.highlighted = index
        if index != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    }

    /// Puts the guide's flower for the chosen kind and key on screen, blooming when the guide opens and turning into
    /// place when the person picks another.
    private func showFlower(turning: Bool) {
        let kind = model.kind
        let now = Date().timeIntervalSinceReferenceDate
        var timeline = FlowerTimeline(entrance: turning ? .turn : .bloom, opened: now)
        if turning { timeline.glassOpened = flower.timeline.glassOpened }
        flower.mode = model.mode
        flower.items = FieldGuide.items(for: kind, mode: model.mode).map { item in
            guard case .action(let action) = item.operation else { return item }
            var item = item
            item.unavailable = QuickActions.unavailability(of: action, for: [kind.sample])
            return item
        }
        flower.itemsLoaded = true
        flower.highlighted = nil
        flower.phase = .choosing
        flower.status = nil
        flower.fileCount = 1
        flower.icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: kind.sample.pathExtension) ?? .data)
        flower.isVisible = true
        flower.timeline = timeline
        motionRun += 1
        let run = motionRun
        flower.isAnimating = true
        let remaining = FlowerMotion.endTime(of: timeline, petals: flower.items.count) - now
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(remaining, 0) * 1_000_000_000))
            guard run == self.motionRun else { return }
            self.flower.isAnimating = false
        }
    }

    /// Sizes the window to the card or guide and puts it under the menu bar icon.
    private func place() {
        guard let host = panel.contentView else { return }
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        let glass = CGSize(width: fitting.width - 2 * HelpLayout.margin, height: fitting.height - 2 * HelpLayout.margin)
        let icon = Self.iconFrame()
        let screen = icon.flatMap(Self.screen(showing:)) ?? NSScreen.main ?? NSScreen.screens.first
        var origin = FieldGuide.origin(under: icon, size: glass, in: screen?.visibleFrame ?? .zero)
        model.pointerX = icon.map { $0.midX - origin.x }
        // The glass keeps room for its pointer either way, so without one it rises to sit where the pointer would.
        if icon == nil { origin.y += GlassShape.pointer.height }
        panel.setFrame(
            NSRect(x: origin.x - HelpLayout.margin, y: origin.y - HelpLayout.margin, width: fitting.width, height: fitting.height),
            display: true
        )
    }

    /// Where Bloom's menu bar icon is, or nil when the menu bar has no room for it, as beside a camera notch. SwiftUI's
    /// menu bar extra doesn't say, but its window does.
    static func iconFrame() -> NSRect? {
        let window = NSApp.windows.first { $0.className.contains("NSStatusBarWindow") && $0.isVisible && $0.frame.height < 60 }
        return window.flatMap { screen(showing: $0.frame) == nil ? nil : $0.frame }
    }

    /// The screen whose menu bar shows `icon`. An icon the menu bar has no room for keeps a window that hangs below it,
    /// or sits behind the camera notch.
    private static func screen(showing icon: NSRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard screen.frame.contains(CGPoint(x: icon.midX, y: icon.midY)), icon.minY >= screen.visibleFrame.maxY - 1,
                icon.maxY <= screen.frame.maxY + 1
            else { return false }
            guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return true }
            return icon.maxX <= left.maxX || icon.minX >= right.minX
        }
    }

    private func makePanel() -> NSPanel {
        let panel = UnconstrainedPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let actions = HelpActions(
            showMe: { [unowned self] in self.showGuide() },
            notNow: { [unowned self] in self.notNow() },
            close: { [unowned self] in self.close() },
            pickKind: { [unowned self] in self.pick($0) },
            pickMode: { [unowned self] in self.pick($0) },
            point: { [unowned self] in self.point($0) }
        )
        let host = FirstClickHostingView(rootView: HelpView(model: model, flower: flower, actions: actions))
        panel.contentView = host
        return panel
    }
}

/// Stays where it's put. AppKit would push it below the menu bar, but its top is the glass's clear shadow margin, and
/// the glass itself has to come right up to the icon.
private final class UnconstrainedPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Answers a click even while another app is in front, which is always, since Bloom never comes forward for these.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct HelpActions {
    let showMe: () -> Void
    let notNow: () -> Void
    let close: () -> Void
    let pickKind: (FieldGuide.Kind) -> Void
    let pickMode: (Mode) -> Void
    let point: (CGPoint?) -> Void
}

private struct HelpView: View {
    @ObservedObject var model: HelpModel
    let flower: RadialModel
    let actions: HelpActions

    var body: some View {
        Group {
            switch model.showing {
            case .card:
                Glass(width: HelpLayout.cardWidth, cornerRadius: 24, pointerX: model.pointerX) { CardContent(actions: actions) }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("bloom.firstLaunchCard")
            case .guide:
                Glass(width: HelpLayout.guideWidth, cornerRadius: 28, pointerX: model.pointerX) {
                    GuideContent(model: model, flower: flower, actions: actions)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("bloom.fieldGuide")
            }
        }
        // A fresh view each time the glass appears, so it comes in again.
        .id(model.appearance)
        .padding(HelpLayout.margin)
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }
}

// MARK: The card

private struct CardContent: View {
    let actions: HelpActions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                BloomGlyph()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bloom lives here")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Drag any file, tap a key, and a flower of things to do opens around it.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
            HStack(spacing: 8) {
                ForEach(FlowerTabs.modes, id: \.self) { mode in
                    VStack(spacing: 2) {
                        Text(HelpText.key(mode))
                            .font(.system(size: 16))
                            .foregroundStyle(HelpText.keyColor(mode))
                        Text(HelpText.title(mode))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(GlassTile(cornerRadius: 14, tint: PetalPalette.forMode(mode).deep.opacity(0.17)))
                    .accessibilityElement(children: .combine)
                }
            }
            HStack(spacing: 12) {
                Text("See what it can do?")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
                GlassButton(title: "Not Now", action: actions.notNow)
                    .accessibilityIdentifier("bloom.notNow")
                Button(action: actions.showMe) {
                    Text("Show Me")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(HelpText.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(Capsule().fill(Color.white).shadow(color: HelpText.shadow.opacity(0.28), radius: 8, y: 6))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bloom.showMe")
            }
        }
        .foregroundStyle(Color.white)
    }
}

/// Bloom's menu bar icon, drawn from the same petals, in the three flowers' colours.
private struct BloomGlyph: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 24
            context.scaleBy(x: scale, y: scale)
            let center = CGPoint(x: 12, y: 12)
            let colors = FlowerTabs.modes.map { PetalPalette.forMode($0).light }
            for index in 0..<6 {
                let petal = PetalLayout.outline(center: center, angle: Double(index) * .pi / 3, width: 5.8, inner: 4.4, outer: 11.4)
                context.fill(Path(petal), with: .color(colors[index % 3]))
            }
            var ring = Path(ellipseIn: CGRect(x: 12 - 3.1, y: 12 - 3.1, width: 6.2, height: 6.2))
            ring.addEllipse(in: CGRect(x: 12 - 1.7, y: 12 - 1.7, width: 3.4, height: 3.4))
            context.fill(ring, with: .color(.white), style: FillStyle(eoFill: true))
        }
        .accessibilityHidden(true)
    }
}

// MARK: The guide

private struct GuideContent: View {
    @ObservedObject var model: HelpModel
    @ObservedObject var flower: RadialModel
    let actions: HelpActions

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What can Bloom do?")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Pick a kind of file, then a key. Point at a petal to read it.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
                Spacer(minLength: 0)
                Button(action: actions.close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(GlassTile(cornerRadius: 14, tint: Color.white.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("bloom.closeGuide")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Chips(selected: model.kind, width: HelpLayout.guideWidth - 2 * HelpLayout.padding, pick: actions.pickKind)
            ZStack {
                FlowerView(model: flower, showsTabsAndCaption: false, frostsBehind: false)
                    // The flower's window centres its glass a little above the middle.
                    .offset(y: RadialLayout.size.height / 2 - RadialLayout.ringCenter.y)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                PointerTracker(
                    label: "The \(HelpText.title(model.mode)) flower for a \(model.kind.title.lowercased())", onMove: actions.point
                )
                .frame(width: HelpLayout.flowerSide, height: HelpLayout.flowerSide)
            }
            .frame(width: HelpLayout.flowerSide, height: HelpLayout.flowerSide)
            Tabs(selected: model.mode, pick: actions.pickMode)
            Text(caption)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(flower.highlighted == nil ? 0.6 : 1))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: HelpLayout.captionHeight)
                .background(GlassTile(cornerRadius: 14, tint: Color.white.opacity(0.06)))
                .accessibilityIdentifier("bloom.guideCaption")
            Text("Try it for real: drag any file and tap ⇧, ⌘ or ⌃.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.58))
        }
        .foregroundStyle(Color.white)
    }

    private var caption: String {
        if let index = flower.highlighted, flower.items.indices.contains(index) {
            return FieldGuide.caption(for: flower.items[index])
        }
        if flower.items.isEmpty { return "Nothing to convert this kind of file to. Try ⌘ Tools or ⌃ Actions." }
        return "Point at a petal to read it."
    }
}

/// One row of kinds of file that fills the guide's width. Each chip is as wide as its name plus an equal share of
/// what's left, so none is squeezed onto a second line.
private struct Chips: View {
    static let spacing: CGFloat = 6
    static let inset: CGFloat = 8
    let selected: FieldGuide.Kind
    let width: CGFloat
    let pick: (FieldGuide.Kind) -> Void

    var body: some View {
        let kinds = FieldGuide.Kind.allCases
        let names = kinds.map { ceil(Self.nameWidth($0.title)) + 2 * Self.inset }
        let spare = max(0, width - names.reduce(0, +) - Self.spacing * CGFloat(kinds.count - 1)) / CGFloat(kinds.count)
        HStack(spacing: Self.spacing) {
            ForEach(Array(kinds.enumerated()), id: \.offset) { index, kind in
                let isSelected = kind == selected
                Button {
                    pick(kind)
                } label: {
                    Text(kind.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(isSelected ? HelpText.ink : Color.white.opacity(0.86))
                        .frame(width: names[index] + spare, height: 30)
                        .background(
                            Group {
                                if isSelected {
                                    Capsule().fill(Color.white.opacity(0.92))
                                } else {
                                    GlassTile(cornerRadius: 15, tint: Color.white.opacity(0.08))
                                }
                            }
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bloom.chip.\(kind.title)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(width: width)
    }

    private static func nameWidth(_ name: String) -> CGFloat {
        let base = NSFont.systemFont(ofSize: 12, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 12) } ?? base
        return (name as NSString).size(withAttributes: [.font: font]).width
    }
}

/// Clickable tabs under the guide's flower. The chosen one fills with its petal colour.
private struct Tabs: View {
    let selected: Mode
    let pick: (Mode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(FlowerTabs.modes, id: \.self) { mode in
                let deep = PetalPalette.forMode(mode).deep
                let isSelected = mode == selected
                Button {
                    pick(mode)
                } label: {
                    Text("\(HelpText.key(mode)) \(HelpText.title(mode))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            Capsule()
                                .fill(isSelected ? deep.opacity(0.72) : Color.clear)
                                .overlay(Capsule().strokeBorder(Color.white.opacity(isSelected ? 0.3 : 0), lineWidth: 1))
                                .shadow(color: deep.opacity(isSelected ? 0.45 : 0), radius: 7, y: 4)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bloom.tab.\(HelpText.title(mode))")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(GlassTile(cornerRadius: 18, tint: Color.white.opacity(0.07)))
        .animation(.easeInOut(duration: 0.2), value: selected)
    }
}

/// Follows the pointer over the guide's flower. It never takes a click.
private struct PointerTracker: NSViewRepresentable {
    let label: String
    let onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        // The end-to-end journeys find the flower by this, and its frame is exactly the flower's.
        view.setAccessibilityIdentifier("bloom.guideFlower")
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onMove = onMove
        view.setAccessibilityLabel(label)
    }

    final class TrackingView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        private var monitors: [Any] = []
        private var isInside = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            guard window != nil else { return }
            // Bloom never comes forward, so the pointer's moves go to the app in front. A global monitor sees them
            // there, with no Accessibility access, and a local one while they're Bloom's own.
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
            if let global = NSEvent.addGlobalMonitorForEvents(
                matching: mask,
                handler: { [weak self] _ in
                    MainActor.assumeIsolated { self?.follow() }
                })
            {
                monitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(
                matching: mask,
                handler: { [weak self] event in
                    self?.follow()
                    return event
                })
            {
                monitors.append(local)
            }
        }

        private func follow() {
            guard let window, window.isVisible else { return }
            let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            guard bounds.contains(point) else {
                if isInside { onMove?(nil) }
                isInside = false
                return
            }
            isInside = true
            onMove?(CGPoint(x: point.x - bounds.midX, y: isFlipped ? bounds.midY - point.y : point.y - bounds.midY))
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

// MARK: Glass

/// The card's and the guide's frosted glass, the flower's material with a lighter top: a soft edge of light, a glint
/// that sweeps across once as it comes in, and a shadow below.
private struct Glass<Content: View>: View {
    let width: CGFloat
    let cornerRadius: CGFloat
    let pointerX: CGFloat?
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    @State private var glint: CGFloat = -1

    var body: some View {
        let shape = GlassShape(cornerRadius: cornerRadius, pointerX: pointerX)
        let content = content().padding(HelpLayout.padding).padding(.top, GlassShape.pointer.height).frame(width: width)
        surface(content, shape)
            // It grows out of its pointer.
            .scaleEffect(entered || reduceMotion ? 1 : 0.94, anchor: UnitPoint(x: (pointerX ?? width * 0.85) / width, y: 0))
            .offset(y: entered || reduceMotion ? 0 : -10)
            .opacity(entered ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.72)) { entered = true }
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.3).delay(0.35)) { glint = 1 }
            }
    }

    /// The flower's frosted glass, with a lighter top and a soft rim of light.
    private func surface<Surface: View>(_ view: Surface, _ shape: GlassShape) -> some View {
        view.background(
            ZStack {
                // Two shadows: a wide soft one and a close one under the edge.
                shape.fill(HelpText.shadow.opacity(0.42)).blur(radius: 30).offset(y: 28)
                shape.fill(HelpText.shadow.opacity(0.22)).blur(radius: 5).offset(y: 3)
                Frost(shape: shape)
                // Dark enough that the glass stays dark, and its text reads, over a white page.
                shape.fill(Color(red: 16 / 255, green: 18 / 255, blue: 28 / 255).opacity(0.78))
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.10), location: 0),
                            .init(color: Color.white.opacity(0.03), location: 0.46),
                            .init(color: Color.white.opacity(0), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                GeometryReader { proxy in
                    Ellipse()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: min(260, proxy.size.width * 0.75), height: 160)
                        .blur(radius: 30)
                        .offset(x: -40, y: -60)
                }
                .clipShape(shape)
                sweep(shape)
                // Strokes twice as wide, clipped to the glass, leave a 1 pt line inside its edge.
                shape.stroke(Color.white.opacity(0.14), lineWidth: 2).clipShape(shape)
                // A line of light along the top edge.
                shape.stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.42), location: 0),
                            .init(color: Color.white.opacity(0), location: 0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 2
                )
                .clipShape(shape)
            }
            .allowsHitTesting(false)
        )
    }

    /// The band of light that crosses the glass once as it comes in, like the flower's.
    private func sweep(_ shape: GlassShape) -> some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [Color.white.opacity(0), Color.white.opacity(0.2), Color.white.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 100, height: proxy.size.height * 2)
            .rotationEffect(.degrees(25))
            .offset(x: (proxy.size.width + 260) * (glint + 1) / 2 - 200, y: -proxy.size.height / 2)
        }
        .clipShape(shape)
    }
}

/// The glass's outline: a rounded rectangle, and on its top edge a small pointer up to the menu bar icon. Room for the
/// pointer is kept above the rectangle even when there's none, so the glass is the same size either way.
struct GlassShape: Shape {
    static let pointer = CGSize(width: 26, height: 10)
    let cornerRadius: CGFloat
    /// Where along the top the pointer's tip is, or nil for none.
    let pointerX: CGFloat?

    func path(in rect: CGRect) -> Path {
        let top = rect.minY + Self.pointer.height
        let radius = min(cornerRadius, (rect.maxY - top) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: top))
        if let pointerX {
            let half = Self.pointer.width / 2
            let x = min(max(rect.minX + pointerX, rect.minX + radius + half), rect.maxX - radius - half)
            // Soft shoulders into a rounded tip, like a popover's arrow.
            path.addLine(to: CGPoint(x: x - half, y: top))
            path.addCurve(
                to: CGPoint(x: x - 2.4, y: rect.minY + 1.3),
                control1: CGPoint(x: x - half * 0.45, y: top),
                control2: CGPoint(x: x - 4.8, y: rect.minY + 3.4)
            )
            path.addQuadCurve(to: CGPoint(x: x + 2.4, y: rect.minY + 1.3), control: CGPoint(x: x, y: rect.minY - 0.7))
            path.addCurve(
                to: CGPoint(x: x + half, y: top),
                control1: CGPoint(x: x + 4.8, y: rect.minY + 3.4),
                control2: CGPoint(x: x + half * 0.45, y: top)
            )
        }
        let corners = [
            (CGPoint(x: rect.maxX, y: top), CGPoint(x: rect.maxX, y: rect.maxY)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: top)),
            (CGPoint(x: rect.minX, y: top), CGPoint(x: rect.maxX, y: top)),
        ]
        for (corner, next) in corners {
            path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
        }
        path.closeSubpath()
        return path
    }
}

/// Frosted dark glass behind the glass's outline, like the flower's disc.
private struct Frost: NSViewRepresentable {
    let shape: GlassShape

    func makeNSView(context: Context) -> MaskedEffectView {
        let view = MaskedEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        // Dark whatever the Mac's appearance, like the flower's glass.
        view.appearance = NSAppearance(named: .darkAqua)
        view.shape = shape
        return view
    }

    func updateNSView(_ view: MaskedEffectView, context: Context) {
        view.shape = shape
    }

    /// A behind-window effect ignores SwiftUI clipping, so its outline comes from a mask redrawn at its size.
    final class MaskedEffectView: NSVisualEffectView {
        var shape: GlassShape? {
            didSet { needsLayout = true }
        }

        override func layout() {
            super.layout()
            guard let shape, bounds.width > 0, bounds.height > 0 else { return }
            maskImage = NSImage(size: bounds.size, flipped: true) { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.addPath(shape.path(in: rect).cgPath)
                context.fillPath()
                return true
            }
        }
    }
}

/// A pane of glass inside the card or guide: a tint, a light top edge and a faint rim.
private struct GlassTile: View {
    let cornerRadius: CGFloat
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(tint)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.35), location: 0),
                            .init(color: Color.white.opacity(0.16), location: 0.3),
                            .init(color: Color.white.opacity(0.12), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
    }
}

private struct GlassButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(GlassTile(cornerRadius: 16, tint: Color.white.opacity(isHovered ? 0.2 : 0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

private enum HelpText {
    /// The dark text on the white Show Me button and the chosen chip, #1B1D26.
    static let ink = Color(red: 27 / 255, green: 29 / 255, blue: 38 / 255)
    /// The glass's shadow, a deep blue-black.
    static let shadow = Color(red: 6 / 255, green: 8 / 255, blue: 20 / 255)

    static func key(_ mode: Mode) -> String {
        switch mode {
        case .convert: return "⇧"
        case .tools: return "⌘"
        case .actions: return "⌃"
        }
    }

    static func title(_ mode: Mode) -> String {
        switch mode {
        case .convert: return "Convert"
        case .tools: return "Tools"
        case .actions: return "Actions"
        }
    }

    /// Each key's glyph in a paler shade of its petal colour.
    static func keyColor(_ mode: Mode) -> Color {
        switch mode {
        case .convert: return Color(red: 1.0, green: 0.76, blue: 0.82)
        case .tools: return Color(red: 0.86, green: 0.79, blue: 1.0)
        case .actions: return Color(red: 0.74, green: 0.92, blue: 1.0)
        }
    }
}
