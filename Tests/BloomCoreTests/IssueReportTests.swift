import BloomCore
import XCTest

final class IssueReportTests: XCTestCase {
    private let build = BuildInfo(version: "0.3.0", commit: "a554c98", macOS: "15.1 (24B83)", chip: "Apple M2")

    private func value(_ id: String, in report: IssueReport) -> String? {
        report.queryItems.first { $0.name == id }?.value
    }

    func testProblemReportSaysWhatFailedWithoutNamingTheFileOrItsFolder() {
        let file = URL(fileURLWithPath: "/Users/someone/Taxes 2025/Payslip March.pdf")
        let failure = IssueReport.Failure(
            petal: "Compress",
            mode: .tools,
            files: [file],
            message: "Payslip March.pdf: couldn’t write /Users/someone/Taxes 2025/Payslip March (compressed).pdf"
        )
        let report = IssueReport.problem(failure, build: build)

        XCTAssertEqual(report.template, "bug_report.yml")
        XCTAssertEqual(value("title", in: report), "Compress failed on PDF")
        XCTAssertEqual(value("file-type", in: report), "PDF")
        XCTAssertEqual(value("output", in: report), "[file]: couldn’t write [folder]/[file] (compressed).pdf")
        XCTAssertEqual(
            value("what-happened", in: report),
            "I dropped a file (PDF) on Compress in the ⌘ Tools flower, and it failed.\n\nWhat I expected:\n"
        )
        XCTAssertEqual(value("bloom", in: report), "0.3.0 (a554c98)")
        XCTAssertEqual(value("macos", in: report), "15.1 (24B83)")
        XCTAssertEqual(value("mac", in: report), "Apple M2")
        let everything = report.queryItems.compactMap(\.value).joined(separator: "\n")
        XCTAssertFalse(everything.contains("Payslip"))
        XCTAssertFalse(everything.contains("Taxes"))
    }

    func testProblemReportLeavesOutAFolderNamedOnItsOwn() {
        let file = URL(fileURLWithPath: "/Users/someone/Taxes 2025/Payslip March.pdf")
        let failure = IssueReport.Failure(
            petal: "Compress",
            mode: .tools,
            files: [file],
            message: "The file “Payslip March (compressed).pdf” couldn’t be saved in the folder “Taxes 2025” of “someone”."
        )
        let report = IssueReport.problem(failure, build: build)

        XCTAssertEqual(
            value("output", in: report),
            "The file “[file] (compressed).pdf” couldn’t be saved in the folder “[folder]” of “[folder]”."
        )
    }

    func testProblemReportListsEachFileTypeOnceForASelection() {
        let files = ["a.jpg", "b.png", "c.jpg"].map { URL(fileURLWithPath: "/tmp/\($0)") }
        let failure = IssueReport.Failure(petal: "PDF", mode: .convert, files: files, message: "Couldn’t save the PDF.")
        let report = IssueReport.problem(failure, build: build)

        XCTAssertEqual(value("file-type", in: report), "JPG, PNG")
        XCTAssertEqual(value("title", in: report), "PDF failed on JPG, PNG")
        XCTAssertEqual(
            value("what-happened", in: report),
            "I dropped 3 files (JPG, PNG) on PDF in the ⇧ Convert flower, and it failed.\n\nWhat I expected:\n"
        )
        XCTAssertEqual(value("output", in: report), "Couldn’t save the PDF.")
    }

    func testProblemReportWithoutAFailureCarriesOnlyTheBuild() {
        let report = IssueReport.problem(nil, build: build)

        XCTAssertEqual(report.queryItems.map(\.name), ["template", "bloom", "macos", "mac"])
        XCTAssertEqual(value("template", in: report), "bug_report.yml")
    }

    func testFeedbackOpensTheIdeaFormWithTheVersion() {
        let report = IssueReport.feedback(build: build)

        XCTAssertEqual(report.queryItems.map(\.name), ["template", "bloom"])
        XCTAssertEqual(value("template", in: report), "idea.yml")
        XCTAssertEqual(value("bloom", in: report), "0.3.0 (a554c98)")
    }

    func testBuildRunFromSourceSaysSoInsteadOfAVersion() {
        let source = BuildInfo(version: nil, commit: nil, macOS: "15.1 (24B83)", chip: "Apple M2")

        XCTAssertEqual(value("bloom", in: IssueReport.feedback(build: source)), "Run from source with swift run")
    }

    func testCurrentBuildDescribesThisMac() {
        let current = BuildInfo.current()

        XCTAssertFalse(current.macOS.isEmpty)
        XCTAssertFalse(current.macOS.contains("Version"))
        XCTAssertNotEqual(current.chip, "Unknown")
    }
}
