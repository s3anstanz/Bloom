import AppKit
import BloomCore

/// Opens Bloom's GitHub issue forms in the browser, filled in by `IssueReport`.
@MainActor
enum IssueLink {
    /// The latest petal that failed, until it's reported.
    static var lastFailure: IssueReport.Failure?

    static func reportProblem() {
        open(IssueReport.problem(lastFailure, build: .current()))
        lastFailure = nil
    }

    static func sendFeedback() {
        open(IssueReport.feedback(build: .current()))
    }

    private static func open(_ report: IssueReport) {
        guard var components = URLComponents(string: "https://github.com/s3anstanz/Bloom/issues/new") else { return }
        components.queryItems = report.queryItems
        // URLComponents leaves "+" alone, and GitHub reads it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
