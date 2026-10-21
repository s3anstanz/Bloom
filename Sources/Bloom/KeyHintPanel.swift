import AppKit
import BloomCore
import SwiftUI

enum KeyHintLayout {
    static let size = CGSize(width: 124, height: 122)
    static let fadeIn = 0.35
    static let fadeOut = 0.15
}

@MainActor
final class KeyHintModel: ObservableObject {
    @Published var isVisible = false
}

/// The window beside the pointer that shows `KeyHint`. Clicks and drops pass straight through it.
@MainActor
final class KeyHintPanel {
    private let model = KeyHintModel()
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?

    init() {
        // Made at launch, like the flower's window, so the first drag doesn't wait for it.
        let frame = NSRect(origin: .zero, size: KeyHintLayout.size)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: KeyHintView(model: model))
        host.frame = frame
        panel.contentView = host
    }

    /// Shows or hides the hint, keeping it beside the pointer at `pointer` (AppKit screen coordinates) while it shows.
    func update(showing: Bool, pointer: NSPoint) {
        if showing {
            let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })?.visibleFrame ?? .infinite
            panel.setFrameOrigin(KeyHint.origin(for: pointer, size: KeyHintLayout.size, in: screen))
            guard !model.isVisible else { return }
            hideTask?.cancel()
            panel.orderFrontRegardless()
            dragLog.notice("Showing the key hint")
            fade(to: true, duration: KeyHintLayout.fadeIn)
        } else {
            guard model.isVisible else { return }
            fade(to: false, duration: KeyHintLayout.fadeOut)
            hideTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(KeyHintLayout.fadeOut * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func fade(to visible: Bool, duration: Double) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            model.isVisible = visible
        } else {
            withAnimation(.easeOut(duration: duration)) { model.isVisible = visible }
        }
    }
}

private struct KeyHintView: View {
    @ObservedObject var model: KeyHintModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("⇧", "Convert")
            row("⌘", "Tools")
            row("⌃", "Actions")
        }
        .padding(.horizontal, 12)
        .frame(width: KeyHintLayout.size.width, height: KeyHintLayout.size.height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .environment(\.colorScheme, .dark)
        .opacity(model.isVisible ? 0.92 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bloom.keyHint")
    }

    private func row(_ key: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        )
                )
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color.white)
    }
}
