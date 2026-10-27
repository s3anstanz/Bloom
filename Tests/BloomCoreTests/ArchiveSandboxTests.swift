import BloomFixtures
import XCTest

@testable import BloomCore

final class ArchiveSandboxTests: XCTestCase {
    func testSandboxAllowsOutputButRejectsWritesOutsideIt() throws {
        try checkBoundary(script: #"printf safe > "$1/inside.txt"; printf bad > "$2""#)
    }

    func testSandboxRejectsWritesThroughASymlinkInsideOutput() throws {
        try checkBoundary(script: #"printf safe > "$1/inside.txt"; ln -s "$2" "$1/pivot"; printf bad > "$1/pivot""#)
    }

    private func checkBoundary(script: String) throws {
        let root = try Fixtures.makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("output with \"quotes\" and \\backslash", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let victim = root.appendingPathComponent("private.txt")
        try Data("keep this".utf8).write(to: victim)
        let log = root.appendingPathComponent("diagnostics.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let errors = try FileHandle(forWritingTo: log)
        defer { try? errors.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "test", output.path, victim.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try ArchiveSandbox.confine(process, to: output, diagnostics: log)

        try process.run()
        process.waitUntilExit()
        try errors.synchronize()
        let diagnostics = (try? String(contentsOf: log, encoding: .utf8)) ?? ""

        XCTAssertNotEqual(process.terminationStatus, 0, "An escape attempt must fail; diagnostics: \(diagnostics)")
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("inside.txt"), encoding: .utf8), "safe")
        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "keep this")
    }
}
