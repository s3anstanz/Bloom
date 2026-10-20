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
            // The flower gets a plain sentence; the tool's own message is kept for a problem report.
            XCTAssertEqual(error.localizedDescription, "broken.tar.gz: Couldn’t unpack this archive. It may be damaged.")
            XCTAssertNotNil((error as? ConversionError)?.detail)
        }

        XCTAssertEqual(try contents(), ["broken.tar.gz"])
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
