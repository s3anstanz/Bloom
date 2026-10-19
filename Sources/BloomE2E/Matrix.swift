import AppKit
import BloomCore
import BloomFixtures

/// How one petal did with one sample.
struct Outcome {
    enum Verdict {
        case worked, nothingToDo, unavailable, failed
    }

    let sample: String
    let mode: Mode
    let petal: String
    let verdict: Verdict
    let detail: String
    let screenshot: String?
    /// The flower opened only on a second tap of its key.
    var tappedTwice = false
    /// Finder didn't start the first drag, so the files were picked up again.
    var pickedUpTwice = false
    /// The flower didn't open for two taps, so the files were dragged again.
    var draggedTwice = false
}

/// Drags each sample out of Finder onto every petal of every flower, one drop at a time, and checks what each one does.
@MainActor
enum Matrix {
    static func run(_ sample: Sample, number: Int, output: URL) async -> [Outcome] {
        let session = Session(journey: "matrix-\(number)", output: output)
        session.stepShots = false
        var files: [URL]
        var originals: Originals
        do {
            try session.start()
            files = try await sample.make(session.folder)
            originals = Originals(files)
            try await session.openInFinder()
        } catch {
            let detail = "Couldn’t set up the sample: \(error.localizedDescription)"
            return [Outcome(sample: sample.name, mode: .convert, petal: "–", verdict: .failed, detail: detail, screenshot: nil)]
        }
        var outcomes: [Outcome] = []
        let modes: [Mode] = sample.actions ? [.convert, .tools, .actions] : [.convert, .tools]
        for mode in modes {
            for petal in await petals(for: files, mode: mode) {
                print("▶︎ \(sample.name) · \(petal.label)")
                let shots = session.screenshots.count
                var outcome: (Outcome.Verdict, String)
                do {
                    outcome = try await drop(files, on: petal, in: mode, session: session)
                } catch {
                    outcome = (.failed, error.localizedDescription)
                    await session.screenshotAfterFailure()
                }
                await session.finish()
                if let problem = originals.change(in: files) {
                    outcome = (.failed, outcome.0 == .failed ? "\(outcome.1) \(problem)" : problem)
                }
                clearResults(besides: files, in: session.folder)
                // Bring a sample back if a failure took it away, so one failure doesn't fail every petal after it.
                if originals.change(in: files) != nil {
                    try? FileManager.default.removeItem(at: session.folder)
                    try? FileManager.default.createDirectory(at: session.folder, withIntermediateDirectories: true)
                    if let remade = try? await sample.make(session.folder) {
                        files = remade
                        originals = Originals(remade)
                    }
                }
                print("\(outcome.0 == .failed ? "FAIL" : "PASS") \(sample.name) · \(petal.label): \(outcome.1)")
                if outcome.0 == .failed || session.draggedTwice {
                    print("  Bloom's log:")
                    Session.bloomLog().forEach { print("    \($0)") }
                }
                let shot = session.screenshots.count > shots ? session.screenshots.last?.file : nil
                var row = Outcome(
                    sample: sample.name, mode: mode, petal: petal.label, verdict: outcome.0, detail: outcome.1, screenshot: shot)
                row.tappedTwice = session.tappedTwice
                row.pickedUpTwice = session.pickedUpTwice
                row.draggedTwice = session.draggedTwice
                outcomes.append(row)
            }
        }
        return outcomes
    }

    /// One drop target: a petal, or one of its choices.
    private struct Petal {
        let item: WheelItem
        let parent: String
        let choice: String?

        var label: String { choice.map { "\(parent) (\($0))" } ?? parent }
    }

    /// Each petal once, in the flower's order, with a petal's choices in its place. Move comes last, because it takes
    /// the sample away until the matrix puts it back.
    private static func petals(for files: [URL], mode: Mode) async -> [Petal] {
        let petals = await WheelCatalog.items(for: files, mode: mode).flatMap { item in
            item.choices.isEmpty
                ? [Petal(item: item, parent: item.title, choice: nil)]
                : item.choices.map { Petal(item: $0, parent: item.title, choice: $0.title) }
        }
        return petals.filter { !isMove($0) } + petals.filter(isMove)
    }

    private static func isMove(_ petal: Petal) -> Bool {
        if case .action(.move) = petal.item.operation { return true }
        return false
    }

    private static func drop(_ files: [URL], on petal: Petal, in mode: Mode, session: Session) async throws -> (Outcome.Verdict, String) {
        try await session.pickUp(files.map(\.lastPathComponent))
        try await session.tap(key(for: mode))
        try await session.point(at: petal.parent, in: mode, files: files)
        if let choice = petal.choice {
            try await session.point(atChoice: choice, of: petal.parent, in: mode, files: files)
        }
        if let caption = Session.caption(), caption != petal.item.detail {
            // A dimmed Actions petal says why it can't work instead of what it does. Any other caption means the pointer
            // is on another petal, or the flower has other petals than expected, so the drag goes back unfinished.
            let items = await WheelCatalog.items(for: files, mode: mode)
            let details = Set(items.flatMap { [$0.detail] + $0.choices.map(\.detail) })
            guard case .action = petal.item.operation, !details.contains(caption) else {
                try await session.screenshot("pointing elsewhere", step: false)
                try await session.cancelDrag()
                return (.failed, "The flower says “\(caption)” instead of “\(petal.item.detail)”.")
            }
            try await session.screenshot("dimmed", step: false)
            try await session.drop()
            try await session.expectFlowerClosed()
            return (.unavailable, caption)
        }
        if case .action(let action) = petal.item.operation {
            if action == .copy || action == .copyPath { NSPasteboard.general.clearContents() }
            let wasRunning = Session.terminalIsRunning
            let windows = Session.screenWindows()
            try await session.drop()
            return try await check(action, on: files, session: session, terminalWasRunning: wasRunning, windowsBefore: windows)
        }
        try await session.drop()
        let said = try await session.result(after: petal.item.progress, detail: petal.item.detail)
        let added = results(besides: files, in: session.folder)
        let names = added.map(\.lastPathComponent).joined(separator: ", ")
        guard let said, said.hasPrefix("Saved") else {
            if let said, said.hasSuffix("so nothing was saved."), added.isEmpty { return (.nothingToDo, said) }
            let left = added.isEmpty ? "" : " It left \(names) behind."
            return (.failed, (said ?? "The flower closed without saying how it went.") + left)
        }
        guard !added.isEmpty else { return (.failed, "Bloom said “\(said)” but nothing new is in the folder.") }
        for result in added {
            if let problem = await defect(in: result) { return (.failed, problem) }
        }
        return (.worked, said)
    }

    private static func check(
        _ action: QuickAction,
        on files: [URL],
        session: Session,
        terminalWasRunning: Bool,
        windowsBefore: [(owner: String, frame: CGRect)]
    ) async throws -> (Outcome.Verdict, String) {
        switch action {
        case .airDrop:
            let owner = try await session.expectNewWindow(besides: windowsBefore)
            try await session.type(key: 53)
            return (.worked, "AirDrop opened its window, shown by \(owner)")
        case .float:
            let card = try await session.expectFloatCard()
            try await session.closeFloatCard(card)
            return (.worked, "The card floated on screen")
        case .copy:
            try await session.expectFilesOnPasteboard(files)
            return (.worked, "The pasteboard holds the files")
        case .copyPath:
            let wanted = files.map { $0.resolvingSymlinksInPath().path }
            try await Session.waitUntil("the paths on the pasteboard", timeout: 5) {
                let lines = NSPasteboard.general.string(forType: .string)?.components(separatedBy: "\n") ?? []
                return lines.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == wanted
            }
            return (.worked, "The pasteboard holds the paths")
        case .move:
            let destination = try session.destination()
            try await session.chooseInMovePanel(destination)
            for file in files {
                let moved = try await session.expectFile(file.lastPathComponent, in: destination)
                try FileManager.default.moveItem(at: moved, to: file)
            }
            return (.worked, "Moved, then put back")
        case .terminal:
            let isFolder = (try? files[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            try await session.expectTerminal(at: isFolder ? files[0] : session.folder, wasRunning: terminalWasRunning)
            return (.worked, "Terminal opened the folder")
        }
    }

    private static func key(for mode: Mode) -> Session.Key {
        switch mode {
        case .convert: return .shift
        case .tools: return .command
        case .actions: return .control
        }
    }

    /// What's in the sample's folder besides the sample itself.
    private static func results(besides files: [URL], in folder: URL) -> [URL] {
        let sources = Set(files.map(\.lastPathComponent))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && !sources.contains($0) }.sorted().map { folder.appendingPathComponent($0) }
    }

    private static func clearResults(besides files: [URL], in folder: URL) {
        for result in results(besides: files, in: folder) {
            try? FileManager.default.removeItem(at: result)
        }
    }
}
