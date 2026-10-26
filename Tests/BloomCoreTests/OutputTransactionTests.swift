import XCTest

@testable import BloomCore

final class OutputTransactionTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    func testFileCreatedWhileConversionRunsIsPreserved() async throws {
        let destination = folder.appendingPathComponent("photo.jpg")
        let results = try await OutputTransaction.perform {
            let staged = try XCTUnwrap(OutputTransaction.current).stage(in: folder, base: "photo", ext: "jpg")
            try Data("converted".utf8).write(to: staged)
            try Data("existing".utf8).write(to: destination)
            return [staged]
        }

        XCTAssertEqual(results.map(\.lastPathComponent), ["photo 2.jpg"])
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "existing")
        XCTAssertEqual(try String(contentsOf: results[0], encoding: .utf8), "converted")
        XCTAssertEqual(try contents(), ["photo 2.jpg", "photo.jpg"])
    }

    func testSharedNonStickyParentIsRejectedBeforeWriting() throws {
        let shared = folder.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: shared.path)
        let transaction = OutputTransaction()
        defer { transaction.cleanUp() }

        XCTAssertThrowsError(try transaction.stage(in: shared, base: "photo", ext: "jpg"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: shared.path), [])
    }

    func testSharedNonStickyAncestorIsRejectedEvenWhenParentIsPrivate() throws {
        let shared = folder.appendingPathComponent("shared", isDirectory: true)
        let privateFolder = shared.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: privateFolder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: shared.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: privateFolder.path)
        let transaction = OutputTransaction()
        defer { transaction.cleanUp() }

        XCTAssertThrowsError(try transaction.stage(in: privateFolder, base: "photo", ext: "jpg"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: privateFolder.path), [])
    }

    func testACLGrantsAreRejectedEvenWithPrivatePOSIXPermissions() throws {
        let shared = folder.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shared.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", "everyone allow add_subdirectory,delete_child,file_inherit,directory_inherit", shared.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let transaction = OutputTransaction()
        defer { transaction.cleanUp() }

        XCTAssertThrowsError(try transaction.stage(in: shared, base: "photo", ext: "jpg"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: shared.path), [])
    }

    func testConcurrentPublicationsNeverOverwriteEachOther() async throws {
        let root = try XCTUnwrap(folder)
        let results = try await withThrowingTaskGroup(of: URL.self) { group in
            for number in 0..<12 {
                group.addTask {
                    let outputs = try await OutputTransaction.perform {
                        let staged = try XCTUnwrap(OutputTransaction.current).stage(in: root, base: "result", ext: "txt")
                        try Data("result \(number)".utf8).write(to: staged)
                        return [staged]
                    }
                    return try XCTUnwrap(outputs.first)
                }
            }
            var outputs: [URL] = []
            for try await output in group { outputs.append(output) }
            return outputs
        }

        XCTAssertEqual(Set(results).count, 12)
        let saved = try results.map { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertEqual(Set(saved), Set((0..<12).map { "result \($0)" }))
        XCTAssertEqual(try contents().count, 12, "No staging directories should remain")
    }

    func testStagingIsPrivateAndFailuresLeaveNoResults() async throws {
        do {
            _ = try await OutputTransaction.perform {
                let staged = try XCTUnwrap(OutputTransaction.current).stage(in: folder, base: "photo", ext: "jpg")
                let attributes = try FileManager.default.attributesOfItem(atPath: staged.deletingLastPathComponent().path)
                let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
                XCTAssertEqual(permissions.intValue & 0o777, 0o700)
                try Data("partial".utf8).write(to: staged)
                throw ConversionError("Conversion failed.")
            }
            XCTFail("The conversion should fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Conversion failed.")
        }
        XCTAssertEqual(try contents(), [])
    }

    func testDirectoryResultsArePublishedWithoutReplacingSymlinks() async throws {
        let missing = folder.appendingPathComponent("missing", isDirectory: true)
        let link = folder.appendingPathComponent("pages")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missing)
        let results = try await OutputTransaction.perform {
            let staged = try XCTUnwrap(OutputTransaction.current).stage(in: folder, base: "pages", ext: nil)
            try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: false)
            try Data("page".utf8).write(to: staged.appendingPathComponent("Page 1.txt"))
            return [staged]
        }

        XCTAssertEqual(results.map(\.lastPathComponent), ["pages 2"])
        XCTAssertEqual(try String(contentsOf: results[0].appendingPathComponent("Page 1.txt"), encoding: .utf8), "page")
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), missing.path)
        XCTAssertEqual(try contents(), ["pages", "pages 2"])
    }

    func testPublicationFailureKeepsAlreadyPublishedFiles() async throws {
        do {
            _ = try await OutputTransaction.perform {
                let transaction = try XCTUnwrap(OutputTransaction.current)
                let first = try transaction.stage(in: folder, base: "first", ext: "txt")
                let missing = try transaction.stage(in: folder, base: "missing", ext: "txt")
                try Data("saved".utf8).write(to: first)
                return [first, missing]
            }
            XCTFail("Publishing a missing result should fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Earlier results were kept"))
        }
        XCTAssertEqual(try contents(), ["first.txt"])
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("first.txt"), encoding: .utf8), "saved")
    }

    private func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }
}
