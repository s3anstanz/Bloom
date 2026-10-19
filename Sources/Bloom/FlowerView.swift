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

    /// `lit` runs from 0 (resting) to 1 (the petal under the cursor).
    func fill(lit: Double) -> RadialGradient {
        RadialGradient(
            colors: [light.opacity(0.32 + 0.68 * lit), deep.opacity(0.24 + 0.76 * lit)],
            center: .center,
            startRadius: RadialLayout.hubRadius,
            endRadius: RadialLayout.ringRadius
        )
    }

    /// Choices sit beyond the glass, so their light runs from their bases to their tips.
    func choiceFill(lit: Double) -> RadialGradient {
        RadialGradient(
            colors: [light.opacity(0.45 + 0.55 * lit), deep.opacity(0.4 + 0.6 * lit)],
            center: .center,
            startRadius: ChoiceLayout.innerRadius,
            endRadius: ChoiceLayout.outerRadius
        )
    }
}

struct FlowerView: View {
    @ObservedObject var model: RadialModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var anchor: UnitPoint {
        UnitPoint(
            x: RadialLayout.ringCenter.x / RadialLayout.size.width,
            y: RadialLayout.ringCenter.y / RadialLayout.size.height
        )
    }

    var body: some View {
        TimelineView(.animation(paused: !model.isAnimating)) { context in
            // Once the motion has settled, draw its final frame rather than the last tick before it.
            let now = model.clock ?? (model.isAnimating ? context.date.timeIntervalSinceReferenceDate : .infinity)
            let frame = FlowerMotion.frame(
                model.timeline,
                at: now,
                petals: model.items.count,
                choices: openChoices.count,
                reduceMotion: reduceMotion
            )
            content(frame)
        }
        .frame(width: RadialLayout.size.width, height: RadialLayout.size.height)
        .scaleEffect(model.isVisible ? 1 : 0.94, anchor: anchor)
        .opacity(model.isVisible ? 1 : 0)
        .animation(model.isVisible ? nil : .easeIn(duration: 0.25), value: model.isVisible)
        .animation(.easeOut(duration: 0.12), value: model.highlighted)
        .animation(.easeOut(duration: 0.12), value: model.highlightedChoice)
        .animation(.easeOut(duration: 0.12), value: model.hoveredTab)
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .animation(.easeInOut(duration: 0.25), value: model.mode)
        .environment(\.colorScheme, .dark)
    }

    private func content(_ frame: FlowerFrame) -> some View {
        let palette = PetalPalette.forMode(model.mode)
        return ZStack {
            flower(palette, frame)
                .frame(width: RadialLayout.ringRadius * 2, height: RadialLayout.ringRadius * 2)
                .position(RadialLayout.ringCenter)
            if model.phase == .choosing {
                TabRow(current: model.mode, hovered: model.hoveredTab)
                    .opacity(frame.tabsOpacity)
                    .offset(y: frame.tabsOffset)
                    .position(x: RadialLayout.ringCenter.x, y: RadialLayout.ringCenter.y + RadialLayout.tabsDrop)
            }
            if let caption {
                CaptionPill(text: caption)
                    .position(x: RadialLayout.ringCenter.x, y: captionY)
            }
        }
        .offset(x: frame.shake)
    }

    private func flower(_ palette: PetalPalette, _ frame: FlowerFrame) -> some View {
        let diameter = RadialLayout.ringRadius * 2 * CGFloat(frame.discScale)
        return ZStack {
            // Nearly invisible, but it keeps the whole circle a drop target while the glass is still opening.
            Circle().fill(Color.black.opacity(0.01))
            Circle()
                .fill(
                    RadialGradient(
                        colors: [palette.deep.opacity(0.55), palette.deep.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: RadialLayout.ringRadius
                    )
                )
                .scaleEffect(frame.haloScale)
                .opacity(frame.haloOpacity)
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.35))
                    .blur(radius: 16)
                    .offset(y: 8)
                FrostedDisc()
                Glint(offset: frame.glintOffset, diameter: diameter)
                    .opacity(frame.glintOpacity)
            }
            .frame(width: diameter, height: diameter)
            .opacity(frame.discOpacity)
            ZStack {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    PetalView(
                        item: item,
                        index: index,
                        count: model.items.count,
                        palette: palette,
                        motion: frame.petals.indices.contains(index) ? frame.petals[index] : FlowerFrame.Petal(),
                        isHighlighted: model.highlighted == index
                    )
                }
                if let parent = model.openChoices, !openChoices.isEmpty {
                    let parentAngle = 2 * Double.pi * Double(parent) / Double(model.items.count)
                    // Nearly invisible, but it keeps the pointer over the window on its way out to the choices.
                    ChoiceBacking(angle: parentAngle, count: openChoices.count)
                        .fill(Color.black.opacity(0.01))
                    ForEach(Array(openChoices.enumerated()), id: \.element.id) { index, choice in
                        ChoicePetalView(
                            item: choice,
                            angle: ChoiceLayout.angle(of: index, count: openChoices.count, around: parentAngle),
                            parentAngle: parentAngle,
                            palette: palette,
                            motion: frame.choices.indices.contains(index) ? frame.choices[index] : FlowerFrame.Petal(),
                            isHighlighted: model.highlightedChoice == index
                        )
                    }
                }
            }
            .saturation(frame.saturation)
            Pistil(model: model, palette: palette, frame: frame)
        }
    }

    private var caption: String? {
        guard model.phase == .choosing else { return model.status }
        guard model.timeline.closed == nil else { return nil }
        if let index = model.highlighted, model.items.indices.contains(index) {
            let item = model.items[index]
            if model.openChoices == index, let choice = model.highlightedChoice, item.choices.indices.contains(choice) {
                return item.choices[choice].detail
            }
            return item.detail
        }
        if model.items.isEmpty {
            guard model.itemsLoaded else { return nil }
            return model.mode == .convert ? "No conversions for this file" : "No tools for this file"
        }
        return nil
    }

    /// The open petal's choices, like Compress's sizes.
    private var openChoices: [WheelItem] {
        guard let parent = model.openChoices, model.items.indices.contains(parent) else { return [] }
        return model.items[parent].choices
    }

    /// Below the tabs while choosing; in their place once they hide for progress and the result.
    private var captionY: CGFloat {
        if model.phase == .choosing {
            return RadialLayout.ringCenter.y + RadialLayout.tabsDrop + RadialLayout.tabSize.height / 2 + 23
        }
        return RadialLayout.ringCenter.y + RadialLayout.ringRadius + 22
    }
}

/// One tab per flower under the petals. The open flower's tab is filled with its petal colour.
private struct TabRow: View {
    let current: Mode
    let hovered: Mode?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FlowerTabs.modes, id: \.self) { mode in
                Text(Self.label(mode))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(mode == current ? 1 : 0.75))
                    .frame(width: RadialLayout.tabSize.width, height: RadialLayout.tabSize.height)
                    .background(Capsule().fill(segmentColor(mode)).padding(3))
            }
        }
        // One continuous backdrop: the window passes drags through fully transparent gaps.
        .background(Capsule().fill(Color.black.opacity(0.75)))
    }

    private func segmentColor(_ mode: Mode) -> Color {
        let deep = PetalPalette.forMode(mode).deep
        if mode == current { return deep }
        return mode == hovered ? deep.opacity(0.4) : .clear
    }

    private static func label(_ mode: Mode) -> String {
        switch mode {
        case .convert: return "⇧ Convert"
        case .tools: return "⌘ Tools"
        case .actions: return "⌃ Actions"
        }
    }
}

/// One option. Its unfurling comes from `motion`; it lifts outward while pointed at.
private struct PetalView: View {
    let item: WheelItem
    let index: Int
    let count: Int
    let palette: PetalPalette
    let motion: FlowerFrame.Petal
    let isHighlighted: Bool

    var body: some View {
        let slice = 2 * Double.pi / Double(count)
        let angle = Double(index) * slice
        let midRadius = (RadialLayout.hubRadius + RadialLayout.ringRadius) / 2
        let width = count < 3 ? 92 : min(2 * midRadius * CGFloat(sin(slice / 2)) * 1.05, 92)
        let petal = Petal(angle: angle, width: width, inner: RadialLayout.hubRadius - 2, outer: RadialLayout.ringRadius - 12)
        let labelRadius =
            RadialLayout.hubRadius - 2 + (RadialLayout.ringRadius - 10 - RadialLayout.hubRadius) * 0.55 - CGFloat(motion.labelInset)
        let lit = isHighlighted ? 1 : motion.light
        let lift: CGFloat = isHighlighted ? 8 : 0
        ZStack {
            petal
                .fill(palette.fill(lit: lit))
                .shadow(color: palette.deep.opacity(0.7 * lit), radius: 14)
            petal
                .stroke(Color.white.opacity(0.18 + 0.37 * lit), lineWidth: 1)
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(item.title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 62)
            .foregroundStyle(Color.white.opacity(0.9 + 0.1 * lit))
            .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)
            .scaleEffect(isHighlighted ? 1.12 : 1)
            .opacity(motion.labelOpacity)
            .offset(x: labelRadius * CGFloat(sin(angle)), y: -labelRadius * CGFloat(cos(angle)))
        }
        .offset(x: lift * CGFloat(sin(angle)), y: -lift * CGFloat(cos(angle)))
        .scaleEffect(motion.scale)
        .rotationEffect(.degrees(motion.rotation))
        .opacity(motion.opacity)
    }
}

/// One of a petal's choices, past its tip. It grows out from the glass's edge where its petal points.
private struct ChoicePetalView: View {
    let item: WheelItem
    let angle: Double
    let parentAngle: Double
    let palette: PetalPalette
    let motion: FlowerFrame.Petal
    let isHighlighted: Bool

    var body: some View {
        let petal = Petal(angle: angle, width: ChoiceLayout.width, inner: ChoiceLayout.innerRadius, outer: ChoiceLayout.outerRadius)
        let lit = isHighlighted ? 1 : motion.light
        let lift: CGFloat = isHighlighted ? 6 : 0
        let labelRadius = (ChoiceLayout.innerRadius + ChoiceLayout.outerRadius) / 2 - CGFloat(motion.labelInset)
        let growFrom = UnitPoint(x: 0.5 + 0.5 * sin(parentAngle), y: 0.5 - 0.5 * cos(parentAngle))
        ZStack {
            petal.fill(Color.black.opacity(0.6))
            petal
                .fill(palette.choiceFill(lit: lit))
                .shadow(color: palette.deep.opacity(0.7 * lit), radius: 12)
            petal
                .stroke(Color.white.opacity(0.25 + 0.3 * lit), lineWidth: 1)
            VStack(spacing: 1) {
                Text(item.title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                if let badge = item.badge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .opacity(0.85)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 54)
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)
            .scaleEffect(isHighlighted ? 1.1 : 1)
            .opacity(motion.labelOpacity)
            .offset(x: labelRadius * CGFloat(sin(angle)), y: -labelRadius * CGFloat(cos(angle)))
        }
        .offset(x: lift * CGFloat(sin(angle)), y: -lift * CGFloat(cos(angle)))
        .scaleEffect(motion.scale, anchor: growFrom)
        .opacity(motion.opacity)
    }
}

/// The band beyond the glass where a petal's choices sit, from the glass's edge out past their tips.
private struct ChoiceBacking: Shape {
    let angle: Double
    let count: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let reach = (Double(count) / 2 + 0.5) * ChoiceLayout.spread
        let steps = 16
        func point(_ radius: CGFloat, _ step: Int) -> CGPoint {
            let at = angle - reach + 2 * reach * Double(step) / Double(steps)
            return CGPoint(x: center.x + radius * CGFloat(sin(at)), y: center.y - radius * CGFloat(cos(at)))
        }
        var path = Path()
        path.move(to: point(RadialLayout.ringRadius - 4, 0))
        for step in 0...steps {
            path.addLine(to: point(ChoiceLayout.outerRadius + 10, step))
        }
        for step in (0...steps).reversed() {
            path.addLine(to: point(RadialLayout.ringRadius - 4, step))
        }
        path.closeSubpath()
        return path
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
    let frame: FlowerFrame

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.45))
            Circle().fill(palette.light.opacity(0.12))
            Circle()
                .inset(by: 0.75)
                .trim(from: 0, to: frame.ringTrim)
                .stroke(palette.light.opacity(0.6), lineWidth: 1.5)
                .rotationEffect(.degrees(-90))
            Circle()
                .strokeBorder(palette.light.opacity(0.6), lineWidth: 1.5)
                .scaleEffect(frame.pulseScale)
                .opacity(frame.pulseOpacity)
            if let index = pointedPetal {
                // A short arc on the ring that points at the petal under the cursor.
                Circle()
                    .inset(by: 0.75)
                    .trim(from: 0, to: 40.0 / 360)
                    .stroke(palette.light, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-110 + 360 * Double(index) / Double(model.items.count)))
            }
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
                    .opacity(frame.fileOpacity)
            }
            Spinner(isTurning: frame.spinnerOpacity > 0)
                .opacity(frame.spinnerOpacity)
            ZStack {
                Circle().fill(palette.light)
                Checkmark()
                    .trim(from: 0, to: frame.checkTrim)
                    .stroke(Color.black.opacity(0.75), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 34, height: 34)
            .opacity(frame.checkOpacity)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.yellow)
                .scaleEffect(frame.warningScale)
                .opacity(frame.warningOpacity)
        }
        .frame(width: RadialLayout.hubRadius * 2, height: RadialLayout.hubRadius * 2)
        .scaleEffect(frame.pistilScale)
        .opacity(frame.pistilOpacity)
    }

    private var pointedPetal: Int? {
        guard model.phase == .choosing, model.timeline.closed == nil else { return nil }
        guard let index = model.highlighted, model.items.indices.contains(index) else { return nil }
        return index
    }
}

/// Turns while Bloom works, on its own clock so the rest of the flower can rest during a long job.
private struct Spinner: View {
    let isTurning: Bool

    var body: some View {
        TimelineView(.animation(paused: !isTurning)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(360 * turn))
            }
            .frame(width: 22, height: 22)
        }
    }
}

private struct Checkmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.43, y: rect.minY + rect.height * 0.66))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.34))
        return path
    }
}

/// A band of light that sweeps once across the glass as it opens.
private struct Glint: View {
    let offset: Double
    let diameter: CGFloat

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0), Color.white.opacity(0.26), Color.white.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 120, height: 600)
            .rotationEffect(.degrees(25))
            .offset(x: 260 * offset)
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .allowsHitTesting(false)
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

/// Frosted dark disc behind the petals.
private struct FrostedDisc: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        // A behind-window effect ignores SwiftUI clipping, so the circle comes from a mask image, stretched as the disc opens.
        let diameter = RadialLayout.ringRadius * 2
        let mask = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        mask.resizingMode = .stretch
        view.maskImage = mask
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
