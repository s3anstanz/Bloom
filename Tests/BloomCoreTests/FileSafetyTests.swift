import BloomCore
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
}
