import AppKit
import BloomCore
import SwiftUI

/// Petal colours per wheel: blossom pink for Convert, violet for Tools, sky blue for Actions.
struct PetalPalette {
    let light: Color
    let deep: Color

    static func forMode(_ mode: Mode) -> PetalPalette {
        switch mode {
        case .convert:
            return PetalPalette(light: Color(red: 1.0, green: 0.64, blue: 0.72), deep: Color(red: 0.93, green: 0.27, blue: 0.47))
        case .tools:
            return PetalPalette(light: Color(red: 0.79, green: 0.68, blue: 1.0), deep: Color(red: 0.50, green: 0.33, blue: 0.96))
        case .actions:
            return PetalPalette(light: Color(red: 0.56, green: 0.87, blue: 1.0), deep: Color(red: 0.16, green: 0.56, blue: 0.96))
        }
    }

    func fill(lit: Bool) -> RadialGradient {
        RadialGradient(
            colors: lit ? [light, deep] : [light.opacity(0.32), deep.opacity(0.24)],
            center: .center,
            startRadius: RadialLayout.hubRadius,
            endRadius: RadialLayout.ringRadius
        )
    }
}

struct FlowerView: View {
    @ObservedObject var model: RadialModel

    private var anchor: UnitPoint {
        UnitPoint(
            x: RadialLayout.ringCenter.x / RadialLayout.size.width,
            y: RadialLayout.ringCenter.y / RadialLayout.size.height
        )
    }

    var body: some View {
        let palette = PetalPalette.forMode(model.mode)
        ZStack {
            flower(palette)
                .frame(width: RadialLayout.ringRadius * 2, height: RadialLayout.ringRadius * 2)
                .position(RadialLayout.ringCenter)
            if let caption {
                CaptionPill(text: caption)
                    .position(x: RadialLayout.ringCenter.x, y: RadialLayout.ringCenter.y + RadialLayout.ringRadius + 22)
            }
        }
        .frame(width: RadialLayout.size.width, height: RadialLayout.size.height)
        .scaleEffect(model.isVisible ? 1 : 0.9, anchor: anchor)
        .opacity(model.isVisible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.isVisible)
        .animation(.easeOut(duration: 0.12), value: model.highlighted)
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .animation(.easeInOut(duration: 0.25), value: model.mode)
        .environment(\.colorScheme, .dark)
    }

    private func flower(_ palette: PetalPalette) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.35))
                .blur(radius: 16)
                .offset(y: 8)
            FrostedDisc()
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                PetalView(
                    item: item,
                    index: index,
                    count: model.items.count,
                    palette: palette,
                    isHighlighted: model.highlighted == index
                )
            }
            Pistil(model: model, palette: palette)
        }
    }

    private var caption: String? {
        guard model.phase == .choosing else { return model.status }
        if let index = model.highlighted, model.items.indices.contains(index) {
            return model.items[index].detail
        }
        if model.items.isEmpty {
            guard model.itemsLoaded else { return nil }
            return model.mode == .convert ? "No conversions for this file" : "No tools for this file"
        }
        switch model.mode {
        case .convert: return "Convert  ·  ⌘ Tools  ·  ⌃ Actions"
        case .tools: return "Tools  ·  ⇧ Convert  ·  ⌃ Actions"
        case .actions: return "Actions  ·  ⇧ Convert  ·  ⌘ Tools"
        }
    }
}

/// One option. It unfurls from the center when it appears and lifts outward while pointed at.
private struct PetalView: View {
    let item: WheelItem
    let index: Int
    let count: Int
    let palette: PetalPalette
    let isHighlighted: Bool

    @State var opened = false

    var body: some View {
        let slice = 2 * Double.pi / Double(count)
        let angle = Double(index) * slice
        let midRadius = (RadialLayout.hubRadius + RadialLayout.ringRadius) / 2
        let width = count < 3 ? 92 : min(2 * midRadius * CGFloat(sin(slice / 2)) * 1.05, 92)
        let petal = Petal(angle: angle, width: width, inner: RadialLayout.hubRadius - 2, outer: RadialLayout.ringRadius - 12)
        let labelRadius = RadialLayout.hubRadius - 2 + (RadialLayout.ringRadius - 10 - RadialLayout.hubRadius) * 0.55
        let lift: CGFloat = isHighlighted ? 8 : 0
        ZStack {
            petal
                .fill(palette.fill(lit: isHighlighted))
                .shadow(color: palette.deep.opacity(isHighlighted ? 0.7 : 0), radius: 14)
            petal
                .stroke(Color.white.opacity(isHighlighted ? 0.55 : 0.18), lineWidth: 1)
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(item.title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 62)
            .foregroundStyle(Color.white.opacity(isHighlighted ? 1 : 0.9))
            .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)
            .scaleEffect(isHighlighted ? 1.12 : 1)
            .offset(x: labelRadius * CGFloat(sin(angle)), y: -labelRadius * CGFloat(cos(angle)))
        }
        .offset(x: lift * CGFloat(sin(angle)), y: -lift * CGFloat(cos(angle)))
        .scaleEffect(opened ? 1 : 0.15)
        .rotationEffect(.degrees(opened ? 0 : -35))
        .opacity(opened ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62).delay(Double(index) * 0.035)) {
                opened = true
            }
        }
    }
}

/// A petal pointing outward at `angle` (radians clockwise from 12 o'clock): narrow at the center, round at the tip.
private struct Petal: Shape {
    let angle: Double
    let width: CGFloat
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let cosine = CGFloat(cos(angle))
        let sine = CGFloat(sin(angle))
        // `across` runs sideways over the petal; `out` runs from the flower's center toward the tip.
        func point(_ across: CGFloat, _ out: CGFloat) -> CGPoint {
            CGPoint(x: center.x + across * cosine + out * sine, y: center.y + across * sine - out * cosine)
        }
        let length = outer - inner
        let half = width / 2
        var path = Path()
        path.move(to: point(0, inner))
        path.addCurve(
            to: point(0, outer),
            control1: point(half * 1.25, inner + length * 0.35),
            control2: point(half, outer + length * 0.06)
        )
        path.addCurve(
            to: point(0, inner),
            control1: point(-half, outer + length * 0.06),
            control2: point(-half * 1.25, inner + length * 0.35)
        )
        path.closeSubpath()
        return path
    }
}

/// The flower's center: the dragged file, then progress and the result.
private struct Pistil: View {
    @ObservedObject var model: RadialModel
    let palette: PetalPalette

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.45))
            Circle().fill(palette.light.opacity(0.12))
            Circle().strokeBorder(palette.light.opacity(0.6), lineWidth: 1.5)
            switch model.phase {
            case .choosing:
                if let icon = model.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 46, height: 46)
                        .overlay(alignment: .topTrailing) {
                            if model.fileCount > 1 {
                                CountBadge(count: model.fileCount, color: palette.deep)
                            }
                        }
                }
            case .working:
                ProgressView()
                    .controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(palette.light)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.yellow)
            }
        }
        .frame(width: RadialLayout.hubRadius * 2, height: RadialLayout.hubRadius * 2)
    }
}

private struct CountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
            .offset(x: 10, y: -6)
    }
}

private struct CaptionPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .frame(maxWidth: 320)
    }
}

/// Frosted dark disc behind the petals. It also keeps the whole flower circle a drop target, gaps between petals included.
private struct FrostedDisc: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        // A behind-window effect ignores SwiftUI clipping, so the circle comes from a mask image.
        let diameter = RadialLayout.ringRadius * 2
        view.maskImage = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
