import BloomCore
import BloomFixtures
import XCTest

final class FileSafetyTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try Fixtures.makeFolder()
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    func testNamesFollowFinderNumbering() {
        XCTAssertEqual(Engine.uniqueURL(in: folder, base: "photo", ext: "jpg").lastPathComponent, "photo.jpg")
        FileManager.default.createFile(atPath: folder.appendingPathComponent("photo.jpg").path, contents: Data())
        XCTAssertEqual(Engine.uniqueURL(in: folder, base: "photo", ext: "jpg").lastPathComponent, "photo 2.jpg")
        FileManager.default.createFile(atPath: folder.appendingPathComponent("photo 2.jpg").path, contents: Data())
        XCTAssertEqual(Engine.uniqueURL(in: folder, base: "photo", ext: "jpg").lastPathComponent, "photo 3.jpg")
    }

    func testDanglingSymlinkIsNeverChosenAsAnOutput() throws {
        let missing = folder.appendingPathComponent("missing.jpg")
        let link = folder.appendingPathComponent("photo.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missing)

        XCTAssertEqual(Engine.uniqueURL(in: folder, base: "photo", ext: "jpg").lastPathComponent, "photo 2.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), missing.path)
    }

    func testConversionDoesNotFollowADanglingOutputSymlink() async throws {
        let original = try Fixtures.image(in: folder)
        let missing = folder.appendingPathComponent("private.jpg")
        let link = folder.appendingPathComponent("image.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missing)

        let outputs = try await Engine.convert([original], to: .jpg)

        XCTAssertEqual(outputs.map(\.lastPathComponent), ["image 2.jpg"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), missing.path)
        XCTAssertEqual(try contents(), ["image 2.jpg", "image.jpg", "image.png"])
    }

    func testFoldersGetNoExtension() {
        XCTAssertEqual(Engine.uniqueURL(in: folder, base: "Report (pages)", ext: nil).lastPathComponent, "Report (pages)")
    }

    func testConvertingNeverChangesTheOriginalOrOverwritesEarlierResults() async throws {
        let original = try Fixtures.image(in: folder)
        let before = try Data(contentsOf: original)

        let first = try await Engine.convert([original], to: .jpg)
        let firstBytes = try Data(contentsOf: first[0])
        let second = try await Engine.convert([original], to: .jpg)

        XCTAssertEqual(first.map(\.lastPathComponent), ["image.jpg"])
        XCTAssertEqual(second.map(\.lastPathComponent), ["image 2.jpg"])
        XCTAssertEqual(try Data(contentsOf: original), before)
        XCTAssertEqual(try Data(contentsOf: first[0]), firstBytes)
    }

    func testFilesAlreadyInTheTargetFormatAreLeftAlone() async throws {
        let jpg = try Fixtures.image(in: folder, name: "photo.jpg", type: .jpeg, transparent: false)
        let outputs = try await Engine.convert([jpg], to: .jpg)
        XCTAssertEqual(outputs, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["photo.jpg"])
    }

    func testAFailedBatchLeavesNoResultsBehind() async throws {
        let good = try Fixtures.image(in: folder)
        let broken = folder.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: broken)

        let outputs = try? await Engine.convert([good, broken], to: .jpg)
        XCTAssertNil(outputs, "Converting a broken image should fail")

        XCTAssertEqual(try contents(), ["broken.png", "image.png"])
    }

    func testAFailedExtractLeavesNoFolderBehind() async throws {
        let archive = folder.appendingPathComponent("broken.tar.gz")
        try Data("not an archive".utf8).write(to: archive)

        do {
            _ = try await Engine.apply(.extract, to: [archive])
            XCTFail("Extracting a broken archive should fail")
        } catch {
            // The flower gets a plain sentence; tool diagnostics remain local and are omitted from browser reports.
            XCTAssertEqual(error.localizedDescription, "broken.tar.gz: Couldn’t unpack this archive. It may be damaged.")
            XCTAssertNotNil((error as? ConversionError)?.detail)
        }

        XCTAssertEqual(try contents(), ["broken.tar.gz"])
    }

    func testExtractDoesNotWriteThroughAnArchiveSymlinkOutsideItsFolder() async throws {
        let victim = folder.appendingPathComponent("private.txt")
        try Data("keep this".utf8).write(to: victim)
        let archive = folder.appendingPathComponent("escape.tar")
        // The extraction folder is inside a private sibling staging directory; two parents reach the input folder.
        var bytes = tarEntry("pivot", type: "2", link: "../..")
        bytes += tarEntry("pivot/private.txt", contents: "overwrite")
        bytes += Data(repeating: 0, count: 1024)
        try bytes.write(to: archive)

        _ = try? await Engine.apply(.extract, to: [archive])

        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "keep this")
    }

    func testExtractDoesNotWriteAnAbsoluteArchivePathOutsideItsFolder() async throws {
        let victim = folder.appendingPathComponent("private.txt")
        try Data("keep this".utf8).write(to: victim)
        let archive = folder.appendingPathComponent("absolute.tar")
        var bytes = tarEntry(victim.path, contents: "overwrite")
        bytes += Data(repeating: 0, count: 1024)
        try bytes.write(to: archive)

        _ = try? await Engine.apply(.extract, to: [archive])

        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "keep this")
    }

    // Minimal ustar records let the tests express malicious paths without trusting a tool to create them.
    private func tarEntry(_ name: String, type: String = "0", link: String = "", contents: String = "") -> Data {
        var header = [UInt8](repeating: 0, count: 512)
        func field(_ text: String, at offset: Int, length: Int) {
            let bytes = Array(text.utf8)
            precondition(bytes.count < length)
            header.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }
        let body = Data(contents.utf8)
        if name.utf8.count >= 100, let slash = name.lastIndex(of: "/") {
            field(String(name[name.index(after: slash)...]), at: 0, length: 100)
            field(String(name[..<slash]), at: 345, length: 155)
        } else {
            field(name, at: 0, length: 100)
        }
        field("0000644", at: 100, length: 8)
        field("0000000", at: 108, length: 8)
        field("0000000", at: 116, length: 8)
        field(String(format: "%011o", body.count), at: 124, length: 12)
        field("00000000000", at: 136, length: 12)
        header.replaceSubrange(148..<156, with: Array(repeating: UInt8(32), count: 8))
        header[156] = type.utf8.first!
        field(link, at: 157, length: 100)
        field("ustar", at: 257, length: 6)
        header[263] = 48
        header[264] = 48
        let checksum = header.reduce(0) { $0 + Int($1) }
        field(String(format: "%06o", checksum), at: 148, length: 7)
        header[154] = 0
        header[155] = 32
        return Data(header) + body + Data(repeating: 0, count: (512 - body.count % 512) % 512)
    }

    func testAFailedZipLeavesNoArchiveBehind() async throws {
        let directory = try Fixtures.directory(in: folder)
        let locked = try Fixtures.textFile(in: directory, name: "locked.txt", contents: Fixtures.text)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)

        let outputs = try? await Engine.apply(.zip, to: [directory])
        XCTAssertNil(outputs, "Zipping a folder with an unreadable file should fail")

        XCTAssertEqual(try contents(), ["Sample Folder"])
    }

    func testZipTreatsOptionLikeAndWildcardNamesAsFiles() async throws {
        let names = ["-m", "*.txt", "notes.txt"]
        let files = try names.map { try Fixtures.textFile(in: folder, name: $0, contents: Fixtures.text) }

        let archive = try await Engine.apply(.zip, to: files)

        for file in files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "\(file.lastPathComponent) must still exist")
        }
        XCTAssertEqual(try zipEntries(archive[0]).sorted(), names.sorted())
    }

    private func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    private func zipEntries(_ archive: URL) throws -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", archive.path]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }
}
