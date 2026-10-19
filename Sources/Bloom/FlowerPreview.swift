import AppKit
import BloomCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// `Bloom --preview <folder>` plays each moment of the flower over a colourful backdrop and saves it as a GIF and a strip of
/// stills, so the Preview workflow can show a pull request's UI changes without anyone recording the screen.
@MainActor
final class FlowerPreview {
    private struct Failure: LocalizedError {
        let errorDescription: String?

        init(_ message: String) {
            errorDescription = message
        }
    }

    private struct Moment {
        let name: String
        let title: String
    }

    private typealias Still = (image: CGImage, label: String)

    private static let fps = 20.0
    private let folder: URL
    private let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("BloomPreview-\(UUID().uuidString)")
    private let model = RadialModel()
    private var items: [Mode: [WheelItem]] = [:]
    private var windows: [NSWindow] = []
    private var captureRect = CGRect.zero
    private var captures = 0
    private var moments: [Moment] = []

    static func run(into folder: URL) async {
        do {
            try await FlowerPreview(folder: folder).record()
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Bloom preview failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private init(folder: URL) {
        self.folder = folder
    }

    private static var settled: FlowerTimeline {
        var timeline = FlowerTimeline(entrance: .bloom, opened: -10)
        timeline.petalsShown = -10
        return timeline
    }

    private func record() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let photo = try samplePhoto()
        for mode in FlowerTabs.modes {
            items[mode] = await WheelCatalog.items(for: [photo], mode: mode)
        }
        guard let first = items[.convert]?.first, case .convert(let format) = first.operation else {
            throw Failure("The sample photo has no Convert petals.")
        }
        model.icon = NSWorkspace.shared.icon(forFile: photo.path)
        model.fileCount = 1
        model.itemsLoaded = true
        model.isVisible = true
        try openWindows()

        var bloom = FlowerTimeline(entrance: .bloom, opened: 0)
        bloom.petalsShown = 0
        show(.convert, bloom)
        try await film(Moment(name: "bloom", title: "⇧ Convert blooms"), until: endTime(bloom, .convert) + 0.2)

        show(.convert, Self.settled)
        model.clock = 0
        var stills: [Still] = []
        for index in [0, 2, 4] where model.items.indices.contains(index) {
            model.highlighted = index
            try await pause(0.4)
            let image = try await capture()
            stills.append((image, "On \(model.items[index].title)"))
        }
        try save(Moment(name: "hover", title: "Pointing at petals"), stills, delay: 0.8)

        var turn = FlowerTimeline(entrance: .turn, opened: 0)
        turn.glassOpened = -10
        try await film(Moment(name: "switch", title: "Switching to ⌘ Tools"), from: -0.3, until: endTime(turn, .tools) + 0.2) { now in
            if now < 0 {
                self.show(.convert, Self.settled)
            } else if self.model.mode != .tools {
                self.show(.tools, turn)
            }
        }

        try await chooseASize()

        try await drop(
            Moment(name: "saved", title: "Dropping on a petal"),
            succeeded: true,
            result: "Saved \(photo.deletingPathExtension().lastPathComponent).\(format.rawValue)"
        )
        try await drop(
            Moment(name: "failed", title: "A drop that fails"),
            succeeded: false,
            result: "Can’t convert this file to \(first.title)."
        )

        var letGo = Self.settled
        letGo.closed = 0
        try await film(Moment(name: "let-go", title: "Letting go"), from: -0.2, until: FlowerMotion.closeDuration + 0.1) { now in
            self.show(.convert, now < 0 ? Self.settled : letGo)
        }

        try writeMenuBarIcon()
        try writeIndex()
    }

    /// The pointer rests on Compress until its sizes open, then points at each one.
    private func chooseASize() async throws {
        guard let compress = items[.tools]?.first, !compress.choices.isEmpty else {
            throw Failure("The sample photo's Compress petal has no sizes.")
        }
        var sizes = Self.settled
        sizes.choicesOpened = 0
        try await film(Moment(name: "sizes", title: "Resting on Compress"), from: -0.2, until: 0.9) { now in
            self.show(.tools, now < 0 ? Self.settled : sizes)
            self.model.highlighted = 0
            self.model.openChoices = now < 0 ? nil : 0
        }
        var stills: [Still] = []
        for index in compress.choices.indices {
            model.highlightedChoice = index
            try await pause(0.4)
            stills.append((try await capture(), "On \(compress.choices[index].title)"))
        }
        try save(Moment(name: "choose-size", title: "Pointing at sizes"), stills, delay: 0.8)
    }

    /// The pointer rests on the first petal, the file drops on it at 0 s and the result comes back at 0.9 s.
    private func drop(_ moment: Moment, succeeded: Bool, result: String) async throws {
        let returned = 0.9
        var timeline = Self.settled
        timeline.dropped = 0
        timeline.chosen = 0
        timeline.finish(succeeded: succeeded, at: returned)
        let progress = items[.convert]?.first?.progress
        try await film(moment, from: -0.3, until: endTime(timeline, .convert) + 0.3) { now in
            if now < 0 {
                self.show(.convert, Self.settled)
            } else {
                self.model.timeline = timeline
                self.model.phase = now < returned ? .working : succeeded ? .done : .failed
                self.model.status = now < returned ? progress : result
            }
            self.model.highlighted = 0
        }
    }

    private func show(_ mode: Mode, _ timeline: FlowerTimeline) {
        model.mode = mode
        model.items = items[mode] ?? []
        model.phase = .choosing
        model.status = nil
        model.highlighted = nil
        model.openChoices = nil
        model.highlightedChoice = nil
        model.timeline = timeline
    }

    private func endTime(_ timeline: FlowerTimeline, _ mode: Mode) -> TimeInterval {
        FlowerMotion.endTime(of: timeline, petals: items[mode]?.count ?? 0, choices: items[mode]?.first?.choices.count ?? 0)
    }

    /// Steps the flower's clock frame by frame, letting `update` set the scene for each instant before it's captured.
    private func film(
        _ moment: Moment,
        from start: TimeInterval = 0,
        until end: TimeInterval,
        _ update: (TimeInterval) -> Void = { _ in }
    ) async throws {
        update(start)
        model.clock = start
        // Lets the previous moment's colour and selection fades finish.
        try await pause(0.5)
        var frames: [Still] = []
        for step in 0...Int(((end - start) * Self.fps).rounded(.up)) {
            let now = start + Double(step) / Self.fps
            update(now)
            model.clock = now
            let image = try await capture()
            frames.append((image, String(format: "%.2f s", now)))
        }
        try save(moment, frames, delay: 1 / Self.fps)
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func openWindows() throws {
        guard let primary = NSScreen.screens.first else { throw Failure("There's no display to draw the flower on.") }
        let size = RadialLayout.size
        let visible = primary.visibleFrame
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        windows = [
            window(NSHostingView(rootView: Backdrop()), frame: frame.insetBy(dx: -60, dy: -60), level: .floating),
            window(NSHostingView(rootView: FlowerView(model: model)), frame: frame, level: .popUpMenu),
        ]
        // `screencapture -R` measures from the top-left of the main display.
        captureRect = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    private func window(_ content: NSView, frame: NSRect, level: NSWindow.Level) -> NSWindow {
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = level
        window.contentView = content
        window.orderFrontRegardless()
        return window
    }

    /// Captures the screen under the flower, so the glass shows the backdrop through it as it does on the desktop.
    private func capture() async throws -> CGImage {
        try await pause(0.08)
        captures += 1
        let file = scratch.appendingPathComponent("frame-\(captures).png")
        let rect = captureRect
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))", file.path]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard process.terminationStatus == 0,
            let source = CGImageSourceCreateWithURL(file as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
            let points = Self.pointSized(image)
        else {
            throw Failure("Couldn’t capture the screen. Allow Screen Recording for the app that runs the preview.")
        }
        return points
    }

    /// Draws a capture at one pixel per point, which keeps the GIFs small enough to show in a pull request.
    private static func pointSized(_ image: CGImage) -> CGImage? {
        let width = Int(RadialLayout.size.width)
        let height = Int(RadialLayout.size.height)
        guard image.width != width || image.height != height else { return image }
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Writes `<name>.gif`, holding the first and last frames, and `<name>.png`, up to six labelled stills in a row.
    private func save(_ moment: Moment, _ frames: [Still], delay: Double) throws {
        guard !frames.isEmpty else { throw Failure("No frames for \(moment.name).") }
        let gif = folder.appendingPathComponent("\(moment.name).gif")
        guard let destination = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw Failure("Couldn’t create \(gif.lastPathComponent).")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (index, frame) in frames.enumerated() {
            let hold = index == frames.count - 1 ? max(delay, 1.5) : index == 0 ? max(delay, 0.5) : delay
            let timing = [kCGImagePropertyGIFDelayTime: hold, kCGImagePropertyGIFUnclampedDelayTime: hold]
            CGImageDestinationAddImage(destination, frame.image, [kCGImagePropertyGIFDictionary: timing] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw Failure("Couldn’t save \(gif.lastPathComponent).") }

        let count = min(frames.count, 6)
        let picks = count == 1 ? [0] : (0..<count).map { $0 * (frames.count - 1) / (count - 1) }
        try writePNG(strip(picks.map { frames[$0] }), to: folder.appendingPathComponent("\(moment.name).png"))
        moments.append(moment)
    }

    private func strip(_ stills: [Still]) throws -> CGImage {
        let width = stills[0].image.width
        let height = stills[0].image.height
        let band = 28
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: width * stills.count,
                height: height + band,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw Failure("Couldn’t draw the stills.") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor(white: 0.08, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: context.width, height: context.height).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        for (slot, still) in stills.enumerated() {
            let x = CGFloat(slot * width)
            context.draw(still.image, in: CGRect(x: x, y: CGFloat(band), width: CGFloat(width), height: CGFloat(height)))
            (still.label as NSString).draw(at: NSPoint(x: x + 10, y: 7), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { throw Failure("Couldn’t draw the stills.") }
        return image
    }

    /// `preview.md`: the GIFs two to a row with links to the stills. Paths are relative; the workflow points them at the previews branch.
    private func writeIndex() throws {
        var rows: [String] = []
        for start in stride(from: 0, to: moments.count, by: 2) {
            let cells = moments[start..<min(start + 2, moments.count)].map { moment in
                "<td><b>\(moment.title)</b><br><img src=\"\(moment.name).gif\" width=\"340\"></td>"
            }
            rows.append("<tr>\(cells.joined())</tr>")
        }
        let stills = moments.map { "[\($0.title)](\($0.name).png)" }.joined(separator: " · ")
        let motion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? "on" : "off"
        let transparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? "on" : "off"
        let settings = "Reduce Motion \(motion), Reduce Transparency \(transparency)"
        print("Rendered with \(settings).")
        let icon = "**Menu bar icon** on a light and a dark menu bar, then close up:\n\n<img src=\"menu-bar-icon.png\" width=\"360\">"
        let text = "<table>\n\(rows.joined(separator: "\n"))\n</table>\n\nStills: \(stills)\n\n\(icon)\n\nRendered with \(settings).\n"
        try text.write(to: folder.appendingPathComponent("preview.md"), atomically: true, encoding: .utf8)
    }

    /// `menu-bar-icon.png`: each state of the menu bar icon, at two pixels per point as on a Retina display.
    private func writeMenuBarIcon() throws {
        let states: [(state: MenuBarIcon.State, lead: Int?, label: String)] = [
            (.resting, nil, "Resting"),
            (.open, nil, "Dragging"),
            (.working, 0, "Working 1"),
            (.working, 2, "Working 2"),
            (.working, 4, "Working 3"),
            (.saved, nil, "Saved"),
        ]
        // A 24-point light menu bar, a dark one, then a close-up.
        let rows: [(background: NSColor, glyph: NSColor, height: Int, side: CGFloat)] = [
            (NSColor(white: 0.93, alpha: 1), .black, 48, MenuBarGlyph.side * 2),
            (NSColor(white: 0.17, alpha: 1), .white, 48, MenuBarGlyph.side * 2),
            (.white, .black, 150, 128),
        ]
        let cell = 120
        let band = 34
        let width = cell * states.count
        let height = band + rows.reduce(0) { $0 + $1.height }
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw Failure("Couldn’t draw the menu bar icon.") }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSColor(white: 0.08, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: band).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        for (slot, item) in states.enumerated() {
            (item.label as NSString).draw(at: NSPoint(x: slot * cell + 8, y: 4), withAttributes: attributes)
        }
        var top = band
        for row in rows {
            row.background.setFill()
            NSRect(x: 0, y: top, width: width, height: row.height).fill()
            for (slot, item) in states.enumerated() {
                context.saveGState()
                let inset = (CGFloat(cell) - row.side) / 2
                context.translateBy(x: CGFloat(slot * cell) + inset, y: CGFloat(top) + (CGFloat(row.height) - row.side) / 2)
                MenuBarGlyph.paint(item.state, lead: item.lead, in: context, side: row.side, color: row.glyph)
                context.restoreGState()
            }
            top += row.height
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { throw Failure("Couldn’t draw the menu bar icon.") }
        try writePNG(image, to: folder.appendingPathComponent("menu-bar-icon.png"))
    }

    private func samplePhoto() throws -> URL {
        let photo = scratch.appendingPathComponent("photo.jpg")
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: 640,
                height: 480,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { throw Failure("Couldn’t draw the sample photo.") }
        context.setFillColor(CGColor(red: 0.95, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        guard let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(photo as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw Failure("Couldn’t create the sample photo.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure("Couldn’t save the sample photo.") }
        return photo
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure("Couldn’t create \(url.lastPathComponent).")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure("Couldn’t save \(url.lastPathComponent).") }
    }
}

/// A dark desktop with two soft colour glows, so the frosted glass has something to blur.
private struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.13, blue: 0.2)
            Circle()
                .fill(Color(red: 0.35, green: 0.4, blue: 0.95))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: -110, y: -150)
            Circle()
                .fill(Color(red: 1.0, green: 0.48, blue: 0.35))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 120, y: 140)
        }
    }
}
