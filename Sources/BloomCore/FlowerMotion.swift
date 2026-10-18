import Foundation

/// When each moment of one flower began, in seconds since the reference date.
public struct FlowerTimeline: Equatable {
    public enum Entrance: Equatable {
        /// A new drag: the glass opens and the petals unfurl.
        case bloom
        /// Another flower during the same drag: its petals turn into place.
        case turn
    }

    public var entrance: Entrance
    public var opened: TimeInterval
    /// When the glass began to open. A flower switch keeps the bloom's, so a quick switch doesn't snap the glass open.
    public var glassOpened: TimeInterval
    /// When the petals arrived; checking a video for sound can hold them back a moment.
    public var petalsShown: TimeInterval
    public var dropped: TimeInterval?
    public var chosen = 0
    public private(set) var finished: TimeInterval?
    public private(set) var succeeded = false
    /// When the drag ended without a drop on a petal.
    public var closed: TimeInterval?

    public init(entrance: Entrance = .bloom, opened: TimeInterval = 0) {
        self.entrance = entrance
        self.opened = opened
        glassOpened = opened
        petalsShown = opened
    }

    /// Records the result. One that comes back almost at once still lets the drop's pulse play before the check or warning.
    public mutating func finish(succeeded: Bool, at now: TimeInterval) {
        finished = max(now, (dropped ?? now) + FlowerMotion.minimumWork)
        self.succeeded = succeeded
    }
}

/// How every part of the flower looks at one instant. Scales and opacities are fractions; offsets are in points.
public struct FlowerFrame: Equatable {
    public struct Petal: Equatable {
        public internal(set) var scale = 1.0
        /// Degrees around the flower's center.
        public internal(set) var rotation = 0.0
        public internal(set) var opacity = 1.0
        /// 0 is the resting colour, 1 the lit colour of a petal under the cursor.
        public internal(set) var light = 0.0
        public internal(set) var labelOpacity = 1.0
        /// How far the label sits toward the center before it slides out.
        public internal(set) var labelInset = 0.0

        public init() {}
    }

    public internal(set) var discScale = 1.0
    public internal(set) var discOpacity = 1.0
    public internal(set) var haloScale = 1.0
    public internal(set) var haloOpacity = 0.0
    /// Where the glint is in its sweep across the glass, from -1 to 1.
    public internal(set) var glintOffset = 0.0
    public internal(set) var glintOpacity = 0.0
    public internal(set) var pistilScale = 1.0
    public internal(set) var pistilOpacity = 1.0
    /// How much of the center's ring is drawn.
    public internal(set) var ringTrim = 1.0
    public internal(set) var pulseScale = 1.0
    public internal(set) var pulseOpacity = 0.0
    public internal(set) var fileOpacity = 1.0
    public internal(set) var spinnerOpacity = 0.0
    public internal(set) var checkOpacity = 0.0
    public internal(set) var checkTrim = 1.0
    public internal(set) var warningOpacity = 0.0
    public internal(set) var warningScale = 1.0
    public internal(set) var saturation = 1.0
    /// Sideways offset while the flower shakes no.
    public internal(set) var shake = 0.0
    public internal(set) var tabsOpacity = 1.0
    public internal(set) var tabsOffset = 0.0
    public internal(set) var petals: [Petal]

    init(petals: Int) {
        self.petals = Array(repeating: Petal(), count: max(petals, 0))
    }
}

/// The flower's choreography. Times inside are milliseconds of motion; the bloom, a flower switch and a success
/// play at half speed, while letting go and a failure play at full speed so leaving never feels slow.
public enum FlowerMotion {
    static let showPace = 0.5
    static let minimumWork = 0.36
    /// How long letting go takes to fold the flower away.
    public static let closeDuration = 0.4

    public static func frame(_ timeline: FlowerTimeline, at now: TimeInterval, petals: Int, reduceMotion: Bool) -> FlowerFrame {
        var frame = FlowerFrame(petals: petals)
        openGlass(&frame, motion(now - timeline.glassOpened, pace: showPace), reduceMotion: reduceMotion)
        let elapsed = motion(now - timeline.opened, pace: showPace)
        let lag = motion(timeline.petalsShown - timeline.opened, pace: showPace)
        switch timeline.entrance {
        case .bloom: unfurl(&frame, elapsed, lag: lag, reduceMotion: reduceMotion)
        case .turn: turn(&frame, elapsed, lag: lag, reduceMotion: reduceMotion)
        }
        if let dropped = timeline.dropped {
            work(&frame, motion(now - dropped, pace: showPace), chosen: timeline.chosen, reduceMotion: reduceMotion)
        }
        if let finished = timeline.finished {
            if timeline.succeeded {
                succeed(&frame, motion(now - finished, pace: showPace), chosen: timeline.chosen, reduceMotion: reduceMotion)
            } else {
                fail(&frame, motion(now - finished, pace: 1), reduceMotion: reduceMotion)
            }
        }
        if let closed = timeline.closed {
            close(&frame, motion(now - closed, pace: 1), reduceMotion: reduceMotion)
        }
        return frame
    }

    /// The time after which `frame` stops changing, apart from the spinner turning while Bloom works.
    public static func endTime(of timeline: FlowerTimeline, petals: Int) -> TimeInterval {
        let last = Double(max(petals - 1, 0))
        let lag = motion(timeline.petalsShown - timeline.opened, pace: showPace)
        let entrance: Double
        switch timeline.entrance {
        case .bloom: entrance = max(110, lag) + last * 28 + 700
        case .turn: entrance = max(0, lag) + last * 16 + 600
        }
        var end = max(timeline.opened + seconds(entrance, pace: showPace), timeline.glassOpened + seconds(700, pace: showPace))
        if let dropped = timeline.dropped {
            end = max(end, dropped + seconds(400, pace: showPace))
        }
        if let finished = timeline.finished {
            end = max(end, finished + (timeline.succeeded ? seconds(520, pace: showPace) : seconds(700, pace: 1)))
        }
        if let closed = timeline.closed {
            end = max(end, closed + closeDuration)
        }
        return end
    }

    /// The glass opens like an iris, the center pops in and draws its ring, a glint crosses, and the tabs rise.
    private static func openGlass(_ frame: inout FlowerFrame, _ ms: Double, reduceMotion: Bool) {
        if reduceMotion {
            let fade = clamp(ms / 150)
            frame.discOpacity = fade
            frame.pistilOpacity = fade
            frame.tabsOpacity = fade
            return
        }
        frame.discScale = lerp(0.2, 1, spring(ms, response: 0.34, damping: 0.74))
        frame.discOpacity = easeOut(clamp(ms / 90))
        halo(&frame, clamp((ms - 40) / 520), from: 0.7, to: 1.3, peak: 0.5)
        let sweep = clamp((ms - 180) / 460)
        frame.glintOffset = lerp(-1, 1, easeInOut(sweep))
        frame.glintOpacity = bump(sweep)
        frame.pistilScale = lerp(0.4, 1, spring(ms - 30, response: 0.3, damping: 0.58))
        frame.pistilOpacity = clamp((ms - 30) / 80)
        frame.ringTrim = easeOut(clamp((ms - 100) / 360))
        frame.tabsOpacity = easeOut(clamp((ms - 220) / 220))
        frame.tabsOffset = 8 * (1 - frame.tabsOpacity)
    }

    /// The petals unfurl clockwise from 12 o'clock, each catching the light as it lands.
    private static func unfurl(_ frame: inout FlowerFrame, _ ms: Double, lag: Double, reduceMotion: Bool) {
        if reduceMotion {
            fadePetals(&frame, clamp((ms - lag) / 150))
            return
        }
        let start = max(110, lag)
        for index in frame.petals.indices {
            let local = ms - start - Double(index) * 28
            let settle = spring(local, response: 0.42, damping: 0.66)
            frame.petals[index].scale = lerp(0.15, 1, settle)
            frame.petals[index].rotation = lerp(-35, 0, settle)
            frame.petals[index].opacity = easeOut(clamp(local / 100))
            frame.petals[index].light = 0.85 * bump((local - 60) / 320)
            let label = easeOut(clamp((local - 170) / 160))
            frame.petals[index].labelOpacity = label
            frame.petals[index].labelInset = 6 * (1 - label)
        }
    }

    /// Another flower's petals turn into place while the center redraws its ring in the new colour.
    private static func turn(_ frame: inout FlowerFrame, _ ms: Double, lag: Double, reduceMotion: Bool) {
        if reduceMotion {
            fadePetals(&frame, clamp((ms - lag) / 150))
            return
        }
        frame.ringTrim = easeOut(clamp(ms / 300))
        halo(&frame, clamp(ms / 380), from: 0.9, to: 1.15, peak: 0.35)
        let start = max(0, lag)
        for index in frame.petals.indices {
            let local = ms - start - Double(index) * 16
            let settle = spring(local, response: 0.36, damping: 0.7)
            frame.petals[index].scale = lerp(0.8, 1, settle)
            frame.petals[index].rotation = lerp(-28, 0, settle)
            frame.petals[index].opacity = easeOut(clamp(local / 90))
            frame.petals[index].light = 0.7 * bump((local - 30) / 300)
            let label = easeOut(clamp((local - 120) / 120))
            frame.petals[index].labelOpacity = label
            frame.petals[index].labelInset = 6 * (1 - label)
        }
    }

    /// After a drop: the chosen petal stays lit and pulses, the others step back, and the spinner replaces the file.
    private static func work(_ frame: inout FlowerFrame, _ ms: Double, chosen: Int, reduceMotion: Bool) {
        let count = frame.petals.count
        for index in frame.petals.indices {
            if index == chosen {
                frame.petals[index].light = 1
                if !reduceMotion { frame.petals[index].scale *= 1 + 0.06 * bump(ms / 260) }
                continue
            }
            let gap = Double(min(abs(index - chosen), count - abs(index - chosen)))
            let back = reduceMotion ? clamp(ms / 150) : easeOut(clamp((ms - gap * 20) / 220))
            frame.petals[index].opacity *= lerp(1, 0.28, back)
            frame.petals[index].labelOpacity *= lerp(1, 0.4, back)
            if !reduceMotion { frame.petals[index].scale *= lerp(1, 0.94, back) }
        }
        frame.fileOpacity = 1 - easeOut(clamp((ms - 100) / 120))
        frame.spinnerOpacity = easeOut(clamp((ms - 180) / 120))
        frame.tabsOpacity *= 1 - clamp(ms / 150)
    }

    private static func succeed(_ frame: inout FlowerFrame, _ ms: Double, chosen: Int, reduceMotion: Bool) {
        frame.spinnerOpacity *= 1 - clamp(ms / 100)
        frame.checkOpacity = clamp(ms / 60)
        if reduceMotion { return }
        frame.checkTrim = easeOut(clamp(ms / 220))
        if frame.petals.indices.contains(chosen) {
            frame.petals[chosen].scale *= 1 + 0.05 * bump(ms / 300)
        }
        let pulse = clamp(ms / 420)
        if pulse > 0, pulse < 1 {
            frame.pulseScale = lerp(1, 1.6, easeOut(pulse))
            frame.pulseOpacity = 0.7 * (1 - pulse)
        }
        halo(&frame, clamp(ms / 500), from: 0.9, to: 1.25, peak: 0.45)
    }

    private static func fail(_ frame: inout FlowerFrame, _ ms: Double, reduceMotion: Bool) {
        frame.spinnerOpacity *= 1 - clamp(ms / 100)
        frame.warningOpacity = clamp(ms / 80)
        frame.saturation = lerp(1, 0.15, easeOut(clamp(ms / 300)))
        if reduceMotion { return }
        frame.warningScale = lerp(0.3, 1, spring(ms, response: 0.3, damping: 0.55))
        if ms > 0, ms < 380 {
            let progress = ms / 380
            frame.shake = 9 * sin(2 * Double.pi * 3 * progress) * (1 - progress)
        }
    }

    /// Letting go: the petals fold back into the center and the glass closes like an iris.
    private static func close(_ frame: inout FlowerFrame, _ ms: Double, reduceMotion: Bool) {
        if reduceMotion {
            let fade = 1 - clamp(ms / 150)
            frame.discOpacity *= fade
            frame.pistilOpacity *= fade
            frame.tabsOpacity *= fade
            for index in frame.petals.indices {
                frame.petals[index].opacity *= fade
                frame.petals[index].labelOpacity *= fade
            }
            return
        }
        let last = frame.petals.count - 1
        for index in frame.petals.indices {
            let fold = easeIn(clamp((ms - Double(last - index) * 12) / 180))
            frame.petals[index].scale *= lerp(1, 0.15, fold)
            frame.petals[index].rotation += lerp(0, -35, fold)
            frame.petals[index].opacity *= 1 - clamp((fold - 0.2) / 0.8)
            frame.petals[index].labelOpacity *= 1 - clamp(ms / 80)
        }
        frame.pistilScale *= lerp(1, 0.4, easeIn(clamp((ms - 120) / 180)))
        frame.pistilOpacity *= 1 - clamp((ms - 160) / 140)
        let iris = easeIn(clamp((ms - 140) / 200))
        frame.discScale *= lerp(1, 0.2, iris)
        frame.discOpacity *= 1 - iris
        frame.tabsOpacity *= 1 - clamp(ms / 150)
    }

    private static func fadePetals(_ frame: inout FlowerFrame, _ opacity: Double) {
        for index in frame.petals.indices {
            frame.petals[index].opacity = opacity
            frame.petals[index].labelOpacity = opacity
        }
    }

    private static func halo(_ frame: inout FlowerFrame, _ progress: Double, from: Double, to: Double, peak: Double) {
        guard progress > 0, progress < 1 else { return }
        frame.haloScale = lerp(from, to, easeOut(progress))
        frame.haloOpacity = progress < 0.25 ? peak * progress / 0.25 : peak * (1 - (progress - 0.25) / 0.75)
    }

    /// Milliseconds of motion `seconds` after a moment began, capped so a long-settled flower stays put.
    private static func motion(_ seconds: TimeInterval, pace: Double) -> Double {
        min(seconds * 1000 * pace, 60_000)
    }

    private static func seconds(_ ms: Double, pace: Double) -> TimeInterval {
        ms / 1000 / pace
    }

    /// SwiftUI's `.spring(response:dampingFraction:)`, `ms` milliseconds after it starts.
    private static func spring(_ ms: Double, response: Double, damping: Double) -> Double {
        guard ms > 0 else { return 0 }
        let elapsed = ms / 1000
        let natural = 2 * Double.pi / response
        let damped = natural * (1 - damping * damping).squareRoot()
        let decay = exp(-damping * natural * elapsed)
        return 1 - decay * (cos(damped * elapsed) + damping * natural / damped * sin(damped * elapsed))
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func lerp(_ from: Double, _ to: Double, _ amount: Double) -> Double {
        from + (to - from) * amount
    }

    private static func easeOut(_ value: Double) -> Double {
        1 - pow(1 - value, 3)
    }

    private static func easeIn(_ value: Double) -> Double {
        value * value * value
    }

    private static func easeInOut(_ value: Double) -> Double {
        value < 0.5 ? 4 * value * value * value : 1 - pow(-2 * value + 2, 3) / 2
    }

    /// Rises from 0 to 1 and back to 0 as `value` goes from 0 to 1.
    private static func bump(_ value: Double) -> Double {
        value > 0 && value < 1 ? sin(Double.pi * value) : 0
    }
}
