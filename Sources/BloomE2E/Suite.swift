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

    /// Plays every journey, or only the named ones, and writes `summary.md` with each journey's result and screenshots.
    func run(only names: Set<String>) async -> Bool {
        let journeys = Journeys.all.filter { names.isEmpty || names.contains($0.name) }
        guard !journeys.isEmpty else {
            print("No journey is called \(names.sorted().joined(separator: ", ")).")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try await Session.waitForBloom()
        } catch {
            print("FAIL setup: \(error.localizedDescription)")
            return false
        }
        var rows: [String] = []
        var failures = 0
        for journey in journeys {
            print("▶︎ \(journey.name): \(journey.title)")
            let session = Session(journey: journey.name, output: output)
            let result: String
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
            await session.finish()
            let shots = session.screenshots.map { "<img src=\"\($0.file)\" width=\"300\" alt=\"\($0.label)\">" }.joined()
            let labels = session.screenshots.map(\.label).joined(separator: " · ")
            rows.append("<tr><td><b>\(journey.title)</b><br>\(result)<br><sub>\(labels)</sub></td><td>\(shots)</td></tr>")
        }
        let heading = "### End-to-end: \(journeys.count - failures) of \(journeys.count) journeys passed"
        let summary = "\(heading)\n\n<table>\n\(rows.joined(separator: "\n"))\n</table>\n"
        do {
            try summary.write(to: output.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
        } catch {
            print("Couldn’t write the summary: \(error.localizedDescription)")
        }
        return failures == 0
    }
}
