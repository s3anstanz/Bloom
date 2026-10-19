import AppKit
import BloomCore
import BloomFixtures

/// A file, or a selection of files, that the matrix drops on every petal Bloom offers for it.
struct Sample {
    let name: String
    /// Also tries each petal in the Actions flower, which offers the same six for any file.
    var actions = false
    let make: @MainActor (URL) async throws -> [URL]
}

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
}

/// Drags each sample out of Finder onto every petal of every flower, one drop at a time, and checks what each one does.
@MainActor
enum Matrix {
    static let samples: [Sample] = [
        // A circle and a box, so Remove BG has a subject to cut out; the journeys compress a detailed photo.
        Sample(name: "JPEG picture", actions: true) { [try Fixtures.image(in: $0, name: "picture.jpg", type: .jpeg, transparent: false)] },
        Sample(name: "PNG with transparency") { [try Fixtures.image(in: $0)] },
        Sample(name: "PDF") { [try Fixtures.pdf(in: $0)] },
        Sample(name: "Video with sound") { [try await Fixtures.video(in: $0, detailed: true)] },
        Sample(name: "Screen recording without sound") { [try await Fixtures.silentVideo(in: $0)] },
        Sample(name: "WAV audio") { [try Fixtures.audio(in: $0, seconds: 2, noise: true)] },
        Sample(name: "Plain text") { [try Fixtures.textFile(in: $0, name: "notes.txt", contents: Fixtures.text)] },
        Sample(name: "RTF") { [try Fixtures.rtf(in: $0)] },
        Sample(name: "HTML") {
            [try Fixtures.textFile(in: $0, name: "page.html", contents: "<html><body><h1>Bloom</h1><p>\(Fixtures.text)</p></body></html>")]
        },
        Sample(name: "Word") { [try Fixtures.document(in: $0, name: "letter.docx", type: .officeOpenXML)] },
        Sample(name: "OpenDocument") { [try Fixtures.document(in: $0, name: "letter.odt", type: .openDocument)] },
        Sample(name: "SRT subtitles") { [try Fixtures.textFile(in: $0, name: "captions.srt", contents: Fixtures.srt)] },
        Sample(name: "WebVTT subtitles") { [try Fixtures.textFile(in: $0, name: "captions.vtt", contents: Fixtures.vtt)] },
        Sample(name: "Tarball") { folder in
            let notes = try Fixtures.textFile(in: folder, name: "notes.txt", contents: Fixtures.text)
            let tarball = try Fixtures.tarball(in: folder, containing: notes)
            try FileManager.default.removeItem(at: notes)
            return [tarball]
        },
        Sample(name: "Folder", actions: true) { [try Fixtures.directory(in: $0)] },
        Sample(name: "PDF and PNG", actions: true) { [try Fixtures.pdf(in: $0), try Fixtures.image(in: $0)] },
        Sample(name: "Text and photo") {
            [
                try Fixtures.textFile(in: $0, name: "notes.txt", contents: Fixtures.text),
                try Fixtures.image(in: $0, name: "photo.jpg", type: .jpeg, transparent: false),
            ]
        },
    ]

    /// Every sample, or those whose name contains one of `filters`, ignoring case.
    static func samples(matching filters: Set<String>) -> [Sample] {
        guard !filters.isEmpty else { return samples }
        return samples.filter { sample in filters.contains { sample.name.localizedCaseInsensitiveContains($0) } }
    }

    static func run(_ sample: Sample, number: Int, output: URL) async -> [Outcome] {
        let session = Session(journey: "matrix-\(number)", output: output)
        session.stepShots = false
        var files: [URL]
        var originals: [URL: Data]
        do {
            try session.start()
            files = try await sample.make(session.folder)
            originals = Dictionary(uniqueKeysWithValues: files.compactMap { file in (try? Data(contentsOf: file)).map { (file, $0) } })
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
                if let problem = changed(files, from: originals) {
                    outcome = (.failed, outcome.0 == .failed ? "\(outcome.1) \(problem)" : problem)
                }
                clearResults(besides: files, in: session.folder)
                // Bring a sample back if a failure took it away, so one failure doesn't fail every petal after it.
                if changed(files, from: originals) != nil {
                    try? FileManager.default.removeItem(at: session.folder)
                    try? FileManager.default.createDirectory(at: session.folder, withIntermediateDirectories: true)
                    if let remade = try? await sample.make(session.folder) {
                        files = remade
                        originals = Dictionary(
                            uniqueKeysWithValues: remade.compactMap { file in (try? Data(contentsOf: file)).map { (file, $0) } })
                    }
                }
                print("\(outcome.0 == .failed ? "FAIL" : "PASS") \(sample.name) · \(petal.label): \(outcome.1)")
                let shot = session.screenshots.count > shots ? session.screenshots.last?.file : nil
                var row = Outcome(
                    sample: sample.name, mode: mode, petal: petal.label, verdict: outcome.0, detail: outcome.1, screenshot: shot)
                row.tappedTwice = session.tappedTwice
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
            try await session.drop()
            return try await check(action, on: files, session: session, terminalWasRunning: wasRunning)
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
        terminalWasRunning: Bool
    ) async throws -> (Outcome.Verdict, String) {
        switch action {
        case .airDrop:
            let said = try await session.result(after: action.progress, detail: action.detail)
            guard said == "AirDrop opened" else { return (.failed, said ?? "AirDrop didn’t open.") }
            try await Session.pause(1)
            try await session.screenshotOfScreen("AirDrop")
            try await session.type(key: 53)
            return (.worked, "AirDrop opened")
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

    /// Why the sample isn't as it was, or nil when every file is still there and unchanged.
    private static func changed(_ files: [URL], from originals: [URL: Data]) -> String? {
        for file in files {
            guard FileManager.default.fileExists(atPath: file.path) else { return "\(file.lastPathComponent) is gone." }
            if let original = originals[file], (try? Data(contentsOf: file)) != original {
                return "\(file.lastPathComponent) was changed."
            }
        }
        return nil
    }
}
