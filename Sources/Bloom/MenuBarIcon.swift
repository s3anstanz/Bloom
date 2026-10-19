import AppKit
import BloomCore

/// Bloom's menu bar icon follows what Bloom is doing: closed a little at rest, in full bloom while a file is dragged, a
/// bright petal circling while a petal works, and a filled center for a moment once the result is saved.
@MainActor
final class MenuBarIcon: ObservableObject {
    enum State {
        case resting, open, working, saved
    }

    static let shared = MenuBarIcon()

    @Published private(set) var image = MenuBarGlyph.image(.resting)
    private var state = State.resting
    private var motion: Task<Void, Never>?

    func dragStarted() {
        if state == .resting || state == .saved { show(.open) }
    }

    /// The drop and the end of the drag can arrive in either order, so a drop that started work keeps the icon working.
    func dragEnded() {
        if state == .open { show(.resting) }
    }

    func working() {
        show(.working)
    }

    func finished(saved: Bool) {
        show(saved ? .saved : .resting)
    }

    private func show(_ next: State) {
        state = next
        motion?.cancel()
        motion = nil
        image = MenuBarGlyph.image(next)
        switch next {
        case .working where !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion:
            motion = Task { [weak self] in
                var lead = 0
                while !Task.isCancelled {
                    self?.image = MenuBarGlyph.image(.working, lead: lead)
                    lead = (lead + 1) % 6
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            }
        case .saved:
            motion = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled else { return }
                self?.show(.resting)
            }
        default:
            break
        }
    }
}

/// Six of the flower's petals around a ring, drawn on a 24-point grid.
enum MenuBarGlyph {
    /// As tall as the icons beside it in the menu bar.
    static let side: CGFloat = 18

    /// A template image, which macOS colours for light and dark menu bars.
    static func image(_ state: MenuBarIcon.State, lead: Int? = nil) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            paint(state, lead: lead, in: context, side: rect.width, color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws the glyph `side` points square at the context's origin, with y pointing down. While working, `lead` is
    /// the brightest petal and the ones behind it fade.
    static func paint(_ state: MenuBarIcon.State, lead: Int?, in context: CGContext, side: CGFloat, color: NSColor) {
        context.saveGState()
        context.scaleBy(x: side / 24, y: side / 24)
        let center = CGPoint(x: 12, y: 12)
        let resting = state == .resting
        for index in 0..<6 {
            let angle = Double(index) * .pi / 3
            let petal =
                resting
                ? PetalLayout.outline(center: center, angle: angle, width: 5.4, inner: 3.8, outer: 10.2)
                : PetalLayout.outline(center: center, angle: angle, width: 5.8, inner: 4.4, outer: 11.4)
            let fade = lead.map { Double((($0 - index) % 6 + 6) % 6) * 0.15 } ?? 0
            context.setFillColor(color.withAlphaComponent(1 - fade).cgColor)
            context.addPath(petal)
            context.fillPath()
        }
        let ring: CGFloat = resting ? 2.6 : 3.1
        context.setFillColor(color.cgColor)
        context.addEllipse(in: CGRect(x: 12 - ring, y: 12 - ring, width: ring * 2, height: ring * 2))
        if state != .saved {
            let hole: CGFloat = resting ? 1.2 : 1.7
            context.addEllipse(in: CGRect(x: 12 - hole, y: 12 - hole, width: hole * 2, height: hole * 2))
        }
        context.fillPath(using: .evenOdd)
        context.restoreGState()
    }
}
