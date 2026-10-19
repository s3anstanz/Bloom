import AppKit
import ApplicationServices
import BloomCore
import BloomFixtures
import UniformTypeIdentifiers

/// Drives Finder and Bloom for one journey with real mouse and key events, the way a person would, and keeps
/// screenshots of each step. Points are in screen coordinates measured from the top-left of the main display.
@MainActor
final class Session {
    enum Key: CaseIterable {
        case shift, command, control

        var code: CGKeyCode {
            switch self {
            case .shift: return 56
            case .command: return 55
            case .control: return 59
            }
        }

        var flag: CGEventFlags {
            switch self {
            case .shift: return .maskShift
            case .command: return .maskCommand
            case .control: return .maskControl
            }
        }
    }

    /// Where the flower's parts sit in its window, matching `RadialLayout` in the app.
    private enum Layout {
        static let size = CGSize(width: 340, height: 490)
        static let center = CGPoint(x: 170, y: 240)
        /// Midway between the hub (50 pt) and the ring (150 pt).
        static let petalRadius = 100.0
        static let choiceRadius = Double(ChoiceLayout.innerRadius + ChoiceLayout.outerRadius) / 2
        static let tabsDrop = 182.0
        static let tabWidth = 96.0
    }

    static let bloomID = "com.westfalllabs.bloom"

    let folder: URL
    /// Off for the petal matrix, which keeps only the screenshot of how each drop went.
    var stepShots = true
    /// What a passing journey found worth saying, like an action this Mac can't do.
    var note: String?
    private(set) var screenshots: [(file: String, label: String)] = []
    private let name: String
    private let output: URL
    private let events = CGEventSource(stateID: .hidSystemState)
    private var held: CGEventFlags = []
    private var cursor = CGPoint.zero
    private var mouseIsDown = false
    private var flower: CGRect?

    init(journey: String, output: URL) {
        name = journey
        self.output = output
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("BloomE2E").appendingPathComponent(journey)
    }

    static var screen: CGRect {
        CGDisplayBounds(CGMainDisplayID())
    }

    /// Where the drag carries the file before a key opens the flower around the pointer.
    private static var openingPoint: CGPoint {
        CGPoint(x: screen.minX + screen.width * 0.66, y: screen.minY + screen.height * 0.45)
    }

    static func waitForBloom() async throws {
        print("Accessibility access: \(AXIsProcessTrusted()), event posting: \(CGPreflightPostEventAccess())")
        try await waitUntil("Bloom to launch", timeout: 20) {
            NSRunningApplication.runningApplications(withBundleIdentifier: bloomID).contains { $0.isFinishedLaunching }
        }
        try await pause(1)
    }

    func start() throws {
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Lets go of anything still held and waits for the flower to close, so the next journey starts clean.
    func finish() async {
        if mouseIsDown {
            post(.leftMouseUp, at: cursor)
            mouseIsDown = false
        }
        for key in Key.allCases where held.contains(key.flag) {
            held.remove(key.flag)
            postFlags(key)
        }
        do {
            if Self.focusedBloomWindow() != nil {
                try await type(key: 53)
            }
            for card in Self.bloomWindows(sized: Self.cardSize) {
                try await closeFloatCard(card)
            }
            try await Self.waitUntil("the flower to close", timeout: 8) { Self.flowerWindow() == nil }
        } catch {
            print("  \(error.localizedDescription)")
        }
    }

    // MARK: Files

    /// A 1200 × 800 picture of a circle and a box in the journey's folder.
    @discardableResult
    func image(_ fileName: String, type: UTType = .jpeg) throws -> URL {
        try Fixtures.image(in: folder, name: fileName, type: type, transparent: false)
    }

    /// A photo-sized JPEG full of small tiles in varied colours, saved at full quality so Compress has plenty to shrink.
    func photo(_ fileName: String, width: Int, height: Int) throws -> URL {
        try Fixtures.photo(in: folder, name: fileName, width: width, height: height, quality: 1)
    }

    @discardableResult
    func file(_ fileName: String, contents: String) throws -> URL {
        let url = folder.appendingPathComponent(fileName)
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// An empty folder beside the journey's, for files that move or are dragged out of Bloom.
    func destination() throws -> URL {
        let url = folder.deletingLastPathComponent().appendingPathComponent("\(name) destination")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Finder

    /// Opens the journey's folder in a Finder window on the left of the screen, in icon view, and `destination` in a
    /// second window below it.
    func openInFinder(alongside destination: URL? = nil) async throws {
        let right = Int(Self.screen.minX + min(560, Self.screen.width * 0.42))
        let bottom = Int(min(Self.screen.maxY - 30, 820))
        let second =
            destination.map {
                """
                set d to make new Finder window
                set target of d to (POSIX file "\($0.path)" as alias)
                set current view of d to icon view
                set bounds of d to {40, 480, \(right), \(bottom)}
                """
            } ?? ""
        let script = """
            tell application "Finder"
                activate
                close every window
                set w to make new Finder window
                set target of w to (POSIX file "\(folder.path)" as alias)
                set current view of w to icon view
                set bounds of w to {40, 80, \(right), 460}
                \(second)
            end tell
            """
        var error: NSDictionary?
        _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            throw Failure("Finder didn’t open the folder: \(error)")
        }
        try await Self.pause(1)
    }

    /// Presses on the first of `fileNames` in Finder, after ⌘-clicking the rest to select them too, and drags to where
    /// the flower will open.
    func pickUp(_ fileNames: String...) async throws {
        try await pickUp(fileNames)
    }

    func pickUp(_ fileNames: [String]) async throws {
        guard let first = fileNames.first else { throw Failure("Nothing to pick up.") }
        let icon = try await iconCenter(first)
        if fileNames.count > 1 {
            try await click(at: icon)
            for other in fileNames.dropFirst() {
                let point = try await iconCenter(other)
                try await click(at: point, flags: .maskCommand)
            }
            // Longer than a double-click, so pressing on the first file again starts a drag of the whole selection.
            try await Self.pause(0.8)
        }
        log("picking up \(fileNames.joined(separator: ", ")) at \(Int(icon.x)), \(Int(icon.y))")
        post(.mouseMoved, at: icon)
        try await Self.pause(0.3)
        post(.leftMouseDown, at: icon)
        mouseIsDown = true
        try await Self.pause(0.25)
        try await move(to: CGPoint(x: icon.x + 12, y: icon.y + 12), steps: 6)
        try await move(to: Self.openingPoint, steps: 40)
        try await Self.pause(0.3)
    }

    /// Where Finder shows the window for `folder`, through the Accessibility API.
    func finderWindow(showing folder: URL) throws -> CGRect {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            throw Failure("Finder isn’t running.")
        }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        let windows = Self.elements(app, kAXWindowsAttribute)
        guard let window = windows.first(where: { Self.string($0, kAXTitleAttribute) == folder.lastPathComponent }),
            let box = Self.frame(window)
        else { throw Failure("Finder has no window showing \(folder.lastPathComponent).") }
        return box
    }

    /// Where Finder shows `fileName`, found through the Accessibility API.
    private func iconCenter(_ fileName: String) async throws -> CGPoint {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            throw Failure("Finder isn’t running.")
        }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        // Finder may hide the extension, so the bare name is the fallback.
        let stem = (fileName as NSString).deletingPathExtension
        do {
            return try await Self.waitFor("\(fileName) in Finder", timeout: 6) {
                Self.icon(in: app, names: [fileName], depth: 0) ?? Self.icon(in: app, names: [stem], depth: 0)
            }
        } catch {
            print("  Finder's windows as Accessibility sees them:")
            Self.dump(app, depth: 0)
            throw error
        }
    }

    /// The center of the icon named one of `names`. Finder labels the icon itself or only the text under it,
    /// depending on the view, so a label match aims at the icon above it.
    private static func icon(in element: AXUIElement, names: [String], depth: Int) -> CGPoint? {
        let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXFilenameAttribute].compactMap {
            string(element, $0)
        }
        if labels.contains(where: { names.contains($0) }), let box = Self.frame(element) {
            switch string(element, kAXRoleAttribute) ?? "" {
            case kAXImageRole:
                return CGPoint(x: box.midX, y: box.midY)
            case kAXTextFieldRole, kAXStaticTextRole:
                return CGPoint(x: box.midX, y: box.minY - 32)
            default:
                break
            }
        }
        guard depth < 14 else { return nil }
        for child in children(element) {
            if let found = icon(in: child, names: names, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        elements(element, kAXChildrenAttribute)
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func find(in element: AXUIElement, depth: Int = 0, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
        if matches(element) { return element }
        guard depth < 20 else { return nil }
        for child in children(element) {
            if let found = find(in: child, depth: depth + 1, where: matches) {
                return found
            }
        }
        return nil
    }

    private static func press(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return false }
        return AXUIElementPerformAction(value as! AXUIElement, kAXPressAction as CFString) == .success
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
            let position, let size,
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else {
            return nil
        }
        return CGRect(origin: origin, size: extent)
    }

    private static func dump(_ element: AXUIElement, depth: Int) {
        guard depth < 9 else { return }
        let role = string(element, kAXRoleAttribute) ?? "?"
        let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { string(element, $0) }
        let place = Self.frame(element).map { " @ \(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height))" } ?? ""
        print(String(repeating: "  ", count: depth + 2) + role + (labels.isEmpty ? "" : " “\(labels.joined(separator: "” “"))”") + place)
        for child in children(element) {
            dump(child, depth: depth + 1)
        }
    }

    // MARK: Pointer and keys

    /// Taps `key` mid-drag and waits for its flower to open around the pointer.
    func tap(_ key: Key) async throws {
        try await press(key)
        try await release(key)
        try await waitForFlower()
    }

    /// Presses `key` and keeps holding it through the drop, as someone does when they hold ⌘ to reach Tools.
    func hold(_ key: Key) async throws {
        try await press(key)
        try await waitForFlower()
    }

    func press(_ key: Key) async throws {
        log("pressing \(key)")
        held.insert(key.flag)
        postFlags(key)
        try await Self.pause(0.1)
    }

    func release(_ key: Key) async throws {
        log("releasing \(key)")
        held.remove(key.flag)
        postFlags(key)
        try await Self.pause(0.1)
    }

    /// Presses and lets go of the key with `code`, like Return (36) or Escape (53), for whichever app is in front.
    func type(key code: CGKeyCode, flags: CGEventFlags = []) async throws {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: events, virtualKey: code, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            try await Self.pause(0.05)
        }
        try await Self.pause(0.2)
    }

    /// Types `text` into whichever app is in front.
    func type(_ text: String) async throws {
        for unit in text.utf16 {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: events, virtualKey: 0, keyDown: down) else { continue }
                var character = unit
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
                event.post(tap: .cghidEventTap)
            }
            try await Self.pause(0.02)
        }
        try await Self.pause(0.3)
    }

    /// Clicks at `point` without dragging, holding `flags`, such as ⌘ to add a Finder icon to the selection.
    func click(at point: CGPoint, flags: CGEventFlags = []) async throws {
        try await move(to: point, steps: 12)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: events, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            else { continue }
            event.flags = flags
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cghidEventTap)
            try await Self.pause(0.08)
        }
        try await Self.pause(0.3)
    }

    /// Drags from `start` to `end` with the button held, as when taking a file out of Float's card.
    func drag(from start: CGPoint, to end: CGPoint) async throws {
        try await move(to: start, steps: 12)
        post(.leftMouseDown, at: start)
        mouseIsDown = true
        try await Self.pause(0.3)
        try await move(to: CGPoint(x: start.x + 10, y: start.y + 10), steps: 6)
        try await move(to: end, steps: 40)
        try await Self.pause(0.5)
        post(.leftMouseUp, at: end)
        mouseIsDown = false
        try await Self.pause(0.5)
    }

    /// Drags to the petal titled `title` in the flower for `mode` and rests there so the flower lights it.
    func point(at title: String, in mode: Mode, files: [URL]) async throws {
        let center = try flowerCenter()
        let items = await WheelCatalog.items(for: files, mode: mode)
        guard let index = items.firstIndex(where: { $0.title == title }) else {
            throw Failure("The \(mode) flower has no \(title) petal. It has \(items.map(\.title).joined(separator: ", ")).")
        }
        let angle = 2 * Double.pi * Double(index) / Double(items.count)
        log("moving to \(title)")
        try await move(to: CGPoint(x: center.x + Layout.petalRadius * sin(angle), y: center.y - Layout.petalRadius * cos(angle)))
        try await Self.pause(0.6)
        try await screenshot("on \(title)")
    }

    /// Drags out to the choice titled `title` past the petal titled `petal`, whose choices opened while the pointer
    /// rested on it.
    func point(atChoice title: String, of petal: String, in mode: Mode, files: [URL]) async throws {
        let center = try flowerCenter()
        let items = await WheelCatalog.items(for: files, mode: mode)
        guard let parent = items.firstIndex(where: { $0.title == petal }),
            let index = items[parent].choices.firstIndex(where: { $0.title == title })
        else { throw Failure("The \(mode) flower's \(petal) petal has no \(title) choice.") }
        let parentAngle = 2 * Double.pi * Double(parent) / Double(items.count)
        let angle = ChoiceLayout.angle(of: index, count: items[parent].choices.count, around: parentAngle)
        log("moving to \(title)")
        let radius = Layout.choiceRadius
        try await move(to: CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle)))
        try await Self.pause(0.6)
        try await screenshot("on \(title)")
    }

    /// Drags onto the tab for `mode` and rests there long enough for the flower to switch.
    func point(atTab mode: Mode) async throws {
        let center = try flowerCenter()
        guard let column = FlowerTabs.modes.firstIndex(of: mode) else { throw Failure("There's no \(mode) tab.") }
        log("moving to the \(mode) tab")
        try await move(to: CGPoint(x: center.x + Layout.tabWidth * Double(column - 1), y: center.y + Layout.tabsDrop))
        try await Self.pause(1.2)
        try await screenshot("on the \(mode) tab")
    }

    func pointAtCenter() async throws {
        log("moving to the center")
        let center = try flowerCenter()
        try await move(to: center)
        try await Self.pause(0.4)
    }

    /// Lets go of the mouse button where the pointer is, and shows what the flower does next.
    func drop() async throws {
        log("letting go")
        post(.leftMouseUp, at: cursor)
        mouseIsDown = false
        try await Self.pause(0.15)
        try await screenshot("just let go")
        try await Self.pause(0.45)
        try await screenshot("let go")
    }

    private func waitForFlower() async throws {
        flower = try await Self.waitFor("the flower to open", timeout: 5) { Self.flowerWindow() }
        try await Self.pause(0.8)
        try await screenshot("open")
    }

    private func flowerCenter() throws -> CGPoint {
        guard let flower else { throw Failure("The flower isn’t open.") }
        return CGPoint(x: flower.minX + Layout.center.x, y: flower.minY + Layout.center.y)
    }

    /// Bloom's flower window while it's on screen.
    private static func flowerWindow() -> CGRect? {
        bloomWindows(sized: Layout.size).first
    }

    /// Moves the pointer in small steps, dragging while the button is down, as a hand would.
    private func move(to point: CGPoint, steps: Int = 24) async throws {
        let start = cursor
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            let next = CGPoint(x: start.x + (point.x - start.x) * progress, y: start.y + (point.y - start.y) * progress)
            post(mouseIsDown ? .leftMouseDragged : .mouseMoved, at: next)
            try await Self.pause(0.012)
        }
    }

    private func post(_ type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: events, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.flags = held
        event.post(tap: .cghidEventTap)
        cursor = point
    }

    private func postFlags(_ key: Key) {
        guard let event = CGEvent(keyboardEventSource: events, virtualKey: key.code, keyDown: held.contains(key.flag)) else { return }
        event.type = .flagsChanged
        event.flags = held
        event.post(tap: .cghidEventTap)
    }

    // MARK: Expectations

    /// Waits for Bloom to save `fileName` beside the dragged file, or in `other`.
    @discardableResult
    func expectFile(_ fileName: String, in other: URL? = nil, timeout: Double = 20) async throws -> URL {
        let url = (other ?? folder).appendingPathComponent(fileName)
        try await Self.waitUntil("\(fileName) to be saved", timeout: timeout) { FileManager.default.fileExists(atPath: url.path) }
        try await Self.pause(0.8)
        try await screenshot("saved \(fileName)")
        return url
    }

    /// Waits `seconds`, then checks the folder holds exactly `fileNames`.
    func expectOnly(_ fileNames: [String], after seconds: Double) async throws {
        try await Self.pause(seconds)
        let found = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") }.sorted()
        guard found == fileNames.sorted() else {
            throw Failure("Expected only \(fileNames.sorted().joined(separator: ", ")) but found \(found.joined(separator: ", ")).")
        }
    }

    func expectImage(_ url: URL, type: UTType, width: Int, height: Int) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let found = CGImageSourceGetType(source).map({ $0 as String }),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let foundWidth = properties[kCGImagePropertyPixelWidth] as? Int,
            let foundHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw Failure("\(url.lastPathComponent) doesn’t open as an image.") }
        guard found == type.identifier, foundWidth == width, foundHeight == height else {
            throw Failure(
                "\(url.lastPathComponent) is \(found) at \(foundWidth) × \(foundHeight), not \(type.identifier) at \(width) × \(height)."
            )
        }
    }

    func expectUnchanged(_ url: URL, from original: Data) throws {
        guard (try? Data(contentsOf: url)) == original else { throw Failure("\(url.lastPathComponent) was changed.") }
    }

    /// Waits for the general pasteboard to hold `file`'s path. Finder names temporary folders under /private/var
    /// and FileManager under /var, so both sides are compared with symlinks resolved.
    func expectPathOnPasteboard(_ file: URL) async throws {
        let wanted = file.resolvingSymlinksInPath().path
        do {
            try await Self.waitUntil("the pasteboard to hold the path", timeout: 5) {
                NSPasteboard.general.string(forType: .string).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == wanted }
                    ?? false
            }
        } catch {
            throw Failure("The pasteboard holds “\(NSPasteboard.general.string(forType: .string) ?? "no text")”, not \(wanted).")
        }
    }

    func expectFlowerClosed() async throws {
        try await Self.waitUntil("the flower to close", timeout: 3) { Self.flowerWindow() == nil }
    }

    // MARK: Reading Bloom

    /// What the flower's caption says: the petal under the pointer, the progress of a drop or how it went.
    static func caption() -> String? {
        guard let bloom = NSRunningApplication.runningApplications(withBundleIdentifier: bloomID).first else { return nil }
        let app = AXUIElementCreateApplication(bloom.processIdentifier)
        guard let caption = find(in: app, where: { string($0, kAXIdentifierAttribute) == "bloom.caption" }) else { return nil }
        return [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].lazy.compactMap { string(caption, $0) }.first {
            !$0.isEmpty
        }
    }

    /// Waits until the caption stops showing `progress`, or the petal's `detail` from before the drop landed, and
    /// returns what Bloom said about the drop, or nil when the flower closed without saying anything.
    func result(after progress: String, detail: String? = nil, timeout: Double = 120) async throws -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let caption = Self.caption(), caption != progress, caption != detail {
                try await Self.pause(0.3)
                try await screenshot("result", step: false)
                return caption
            }
            if Self.flowerWindow() == nil { return nil }
            try await Self.pause(0.1)
        }
        throw Failure("Bloom still said “\(progress)” after \(Int(timeout)) s.")
    }

    /// Bloom's windows of `size` on screen, like Float's cards.
    static func bloomWindows(sized size: CGSize) -> [CGRect] {
        guard let bloom = NSRunningApplication.runningApplications(withBundleIdentifier: bloomID).first else { return [] }
        return windows(of: bloom.processIdentifier).filter { $0.size == size }
    }

    private static func windows(of pid: pid_t) -> [CGRect] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return windows.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
    }

    // MARK: Actions

    /// Waits for the general pasteboard to hold `files` themselves, as Finder's Copy leaves them.
    func expectFilesOnPasteboard(_ files: [URL]) async throws {
        let wanted = files.map { $0.resolvingSymlinksInPath().path }
        func found() -> [String] {
            let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
            return (urls ?? []).map { $0.resolvingSymlinksInPath().path }
        }
        do {
            try await Self.waitUntil("the pasteboard to hold the files", timeout: 5) { found() == wanted }
        } catch {
            throw Failure("The pasteboard holds \(found().map { ($0 as NSString).lastPathComponent }), not the dropped files.")
        }
    }

    /// Picks `folder` in the Move panel through Go to Folder, then presses Move Here.
    func chooseInMovePanel(_ folder: URL) async throws {
        try await Self.waitUntil("the Move panel", timeout: 5) { Self.focusedBloomWindow() != nil }
        try await Self.pause(0.8)
        try await screenshot("Move panel")
        try await type(key: 5, flags: [.maskCommand, .maskShift])
        try await Self.pause(0.8)
        try await type(folder.path)
        try await type(key: 36)
        try await Self.pause(1)
        try await screenshot("in \(folder.lastPathComponent)")
        try await type(key: 36)
        try await Self.waitUntil("the Move panel to close", timeout: 5) { Self.focusedBloomWindow() == nil }
    }

    /// The Bloom window with keyboard focus, like the Move panel; the flower and Float's cards never take it.
    private static func focusedBloomWindow() -> AXUIElement? {
        guard let bloom = NSRunningApplication.runningApplications(withBundleIdentifier: bloomID).first, bloom.isActive else {
            return nil
        }
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(bloom.processIdentifier)
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success, let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    /// Waits for Terminal to show a window for `folder`, then closes that window, and Terminal too if it wasn't open
    /// before.
    func expectTerminal(at folder: URL, wasRunning: Bool) async throws {
        let name = folder.lastPathComponent
        let window = try await Self.waitFor("Terminal to open \(name)", timeout: 15) { () -> AXUIElement? in
            guard let terminal = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first else {
                return nil
            }
            let app = AXUIElementCreateApplication(terminal.processIdentifier)
            return Self.elements(app, kAXWindowsAttribute).first { Self.string($0, kAXTitleAttribute)?.contains(name) == true }
        }
        flower = nil
        try await screenshot("Terminal", step: false)
        if !wasRunning {
            for terminal in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal") {
                terminal.terminate()
            }
        } else if !Self.press(window, kAXCloseButtonAttribute) {
            print("  Couldn’t close Terminal's window for \(name).")
        }
    }

    static var terminalIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").isEmpty
    }

    /// Waits for Float's card to appear and returns where it is.
    func expectFloatCard() async throws -> CGRect {
        let card = try await Self.waitFor("Float's card", timeout: 5) { Self.bloomWindows(sized: Self.cardSize).first }
        try await Self.pause(0.5)
        flower = card.insetBy(dx: -60, dy: -60)
        try await screenshot("Float card", step: false)
        flower = nil
        return card
    }

    func closeFloatCard(_ card: CGRect) async throws {
        try await click(at: CGPoint(x: card.minX + 17, y: card.minY + 17))
        try await Self.waitUntil("Float's card to close", timeout: 3) { Self.bloomWindows(sized: Self.cardSize).isEmpty }
    }

    /// `FloatCardView.size` in the app.
    static let cardSize = CGSize(width: 132, height: 140)

    // MARK: Screenshots

    /// Saves the screen around the flower, or the whole screen before it opens. A `step` is skipped while `stepShots`
    /// is off.
    func screenshot(_ label: String, step: Bool = true) async throws {
        if step, !stepShots { return }
        let area = flower.map { $0.insetBy(dx: -30, dy: -20).intersection(Self.screen) } ?? Self.screen
        let file = "\(name)-\(screenshots.count + 1).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = [
            "-x", "-R\(Int(area.minX)),\(Int(area.minY)),\(Int(area.width)),\(Int(area.height))",
            output.appendingPathComponent(file).path,
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure("Couldn’t capture the screen for “\(label)”.") }
        screenshots.append((file, label))
    }

    /// Saves the whole screen so a failure shows what was in the way.
    func screenshotAfterFailure() async {
        flower = nil
        do {
            try await screenshot("at the failure", step: false)
        } catch {
            print("  \(error.localizedDescription)")
        }
    }

    // MARK: Waiting

    static func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    static func waitUntil(_ what: String, timeout: Double, _ condition: () -> Bool) async throws {
        _ = try await waitFor(what, timeout: timeout) { condition() ? true : nil }
    }

    static func waitFor<Value>(_ what: String, timeout: Double, _ value: () -> Value?) async throws -> Value {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let found = value() {
                return found
            }
            guard Date() < deadline else { throw Failure("Timed out after \(Int(timeout)) s waiting for \(what).") }
            try await pause(0.1)
        }
    }

    private func log(_ message: String) {
        print("  \(name): \(message)")
    }
}
