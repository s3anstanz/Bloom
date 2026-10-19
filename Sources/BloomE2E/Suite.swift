import BloomCore
import Foundation

/// One thing someone does with Bloom, played on the real app with Finder as the drag source.
struct Journey {
    let name: String
    let title: String
    let run: @MainActor (Session) async throws -> Void
}

struct Failure: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

@MainActor
final class Suite {
    private let output: URL

    init(output: URL) {
        self.output = output
    }

    /// Plays every journey, or only the named ones, then with `matrix` drops each sample on every petal, and writes
    /// `summary.md` with each result and its screenshots.
    func run(only names: Set<String>, matrix: Bool) async -> Bool {
        let known = Set(Journeys.all.map(\.name))
        let journeys = Journeys.all.filter { names.isEmpty || names.contains($0.name) }
        let filters = names.subtracting(known)
        let samples = matrix && (names.isEmpty || !filters.isEmpty) ? Matrix.samples(matching: filters) : []
        guard !journeys.isEmpty || !samples.isEmpty else {
            print("Nothing matches \(names.sorted().joined(separator: ", ")).")
            print("Journeys: \(Journeys.all.map(\.name).joined(separator: ", ")).")
            print("Matrix samples (with --matrix): \(Matrix.samples.map(\.name).joined(separator: ", ")).")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try await Session.waitForBloom()
        } catch {
            print("FAIL setup: \(error.localizedDescription)")
            return false
        }
        var sections: [String] = []
        var passed = true
        if !journeys.isEmpty {
            let (section, ok) = await play(journeys)
            sections.append(section)
            passed = passed && ok
        }
        if !samples.isEmpty {
            var outcomes: [Outcome] = []
            for (number, sample) in samples.enumerated() {
                outcomes += await Matrix.run(sample, number: number + 1, output: output)
            }
            sections.append(Self.table(outcomes))
            passed = passed && !outcomes.contains { $0.verdict == .failed }
        }
        do {
            try sections.joined(separator: "\n").write(to: output.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
        } catch {
            print("Couldn’t write the summary: \(error.localizedDescription)")
        }
        return passed
    }

    private func play(_ journeys: [Journey]) async -> (String, Bool) {
        var rows: [String] = []
        var failures = 0
        for journey in journeys {
            print("▶︎ \(journey.name): \(journey.title)")
            let session = Session(journey: journey.name, output: output)
            var result: String
            do {
                try session.start()
                try await journey.run(session)
                result = "✅ Passed"
                print("PASS \(journey.name)")
            } catch {
                failures += 1
                result = "❌ \(error.localizedDescription)"
                print("FAIL \(journey.name): \(error.localizedDescription)")
                await session.screenshotAfterFailure()
            }
            if let note = session.note {
                result += "<br>\(note)"
                print("  \(note)")
            }
            await session.finish()
            let shots = session.screenshots.map { "<img src=\"\($0.file)\" width=\"300\" alt=\"\($0.label)\">" }.joined()
            let labels = session.screenshots.map(\.label).joined(separator: " · ")
            rows.append("<tr><td><b>\(journey.title)</b><br>\(result)<br><sub>\(labels)</sub></td><td>\(shots)</td></tr>")
        }
        let heading = "### End-to-end: \(journeys.count - failures) of \(journeys.count) journeys passed"
        return ("\(heading)\n\n<table>\n\(rows.joined(separator: "\n"))\n</table>\n", failures == 0)
    }

    /// One row per petal per sample: ✅ it worked, ⚪ it had nothing to do or can't work on this Mac and says why,
    /// ❌ it failed, with what went wrong.
    private static func table(_ outcomes: [Outcome]) -> String {
        func count(_ verdict: Outcome.Verdict) -> Int { outcomes.filter { $0.verdict == verdict }.count }
        let failed = count(.failed)
        var heading = "### Every petal: \(count(.worked)) of \(outcomes.count) worked"
        if count(.nothingToDo) > 0 { heading += " · \(count(.nothingToDo)) had nothing to do" }
        if count(.unavailable) > 0 { heading += " · \(count(.unavailable)) can’t work on this Mac" }
        heading += failed == 0 ? " · none failed" : " · **\(failed) failed**"
        let rows = outcomes.map { outcome -> String in
            let mark: String
            switch outcome.verdict {
            case .worked: mark = "✅"
            case .nothingToDo, .unavailable: mark = "⚪"
            case .failed: mark = "❌"
            }
            let detail = outcome.detail.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
            let shot = outcome.screenshot.map { "[screenshot](\($0))" } ?? ""
            return "| \(outcome.sample) | \(flower(outcome.mode)) | \(outcome.petal) | \(mark) \(detail) | \(shot) |"
        }
        return "\(heading)\n\n| File | Flower | Petal | Result | |\n|---|---|---|---|---|\n\(rows.joined(separator: "\n"))\n"
    }

    private static func flower(_ mode: Mode) -> String {
        switch mode {
        case .convert: return "⇧ Convert"
        case .tools: return "⌘ Tools"
        case .actions: return "⌃ Actions"
        }
    }
}
