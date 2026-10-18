import BloomCore
import XCTest

final class CatalogTests: XCTestCase {
    private func titles(_ paths: [String], _ mode: Mode) async -> [String] {
        await WheelCatalog.items(for: paths.map { URL(fileURLWithPath: "/tmp/\($0)") }, mode: mode).map(\.title)
    }

    func testImageOffersOtherFormatsButNotItsOwn() async {
        let offered = await titles(["photo.png"], .convert)
        XCTAssertFalse(offered.contains("PNG"))
        XCTAssertTrue(offered.contains("JPG"))
        XCTAssertTrue(offered.contains("PDF"))
    }

    func testPDFConvertsToImagesAndText() async {
        let offered = await titles(["report.pdf"], .convert)
        XCTAssertEqual(offered, ["PNG", "JPG", "TXT"])
    }

    func testVideoWithSoundOffersAudioExtractionAndGIF() async throws {
        let folder = try Fixtures.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = try await Fixtures.video(in: folder)
        let items = await WheelCatalog.items(for: [clip], mode: .convert)
        XCTAssertEqual(items.map(\.title), ["MP4", "M4V", "GIF", "M4A"])
        XCTAssertEqual(items.first { $0.title == "M4A" }?.detail, "Extract the audio as M4A")
    }

    func testVideoWithoutSoundIsNotOfferedM4A() async throws {
        let folder = try Fixtures.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let recording = try await Fixtures.silentVideo(in: folder)
        let offered = await WheelCatalog.items(for: [recording], mode: .convert).map(\.title)
        XCTAssertEqual(offered, ["MP4", "M4V", "GIF"])
    }

    func testSelectionOffersOnlyConversionsEveryFileSupports() async {
        let offered = await titles(["photo.png", "clip.mov"], .convert)
        XCTAssertEqual(offered, ["GIF"])
    }

    func testSubtitlesConvertToTheOtherSubtitleFormat() async {
        let fromSRT = await titles(["captions.srt"], .convert)
        let fromVTT = await titles(["captions.vtt"], .convert)
        XCTAssertEqual(fromSRT, ["VTT"])
        XCTAssertEqual(fromVTT, ["SRT"])
    }

    func testArchiveOffersExtractButNoConversions() async {
        let conversions = await titles(["bundle.tar.gz"], .convert)
        let tools = await titles(["bundle.tar.gz"], .tools)
        XCTAssertEqual(conversions, [])
        XCTAssertEqual(tools, ["Extract", "Zip"])
    }

    func testFolderCanOnlyBeZipped() async throws {
        let folder = try Fixtures.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let conversions = await WheelCatalog.items(for: [folder], mode: .convert)
        let tools = await WheelCatalog.items(for: [folder], mode: .tools).map(\.title)
        XCTAssertEqual(conversions.count, 0)
        XCTAssertEqual(tools, ["Zip"])
    }

    func testMergePDFNeedsTwoOrMorePDFsOrImages() async {
        let single = await titles(["report.pdf"], .tools)
        let withImage = await titles(["report.pdf", "photo.png"], .tools)
        let withText = await titles(["report.pdf", "notes.txt"], .tools)
        XCTAssertFalse(single.contains("Merge PDF"))
        XCTAssertTrue(withImage.contains("Merge PDF"))
        XCTAssertFalse(withText.contains("Merge PDF"))
    }

    func testPDFCompressionNamesTheFilterItUses() async {
        let items = await WheelCatalog.items(for: [URL(fileURLWithPath: "/tmp/report.pdf")], mode: .tools)
        XCTAssertEqual(items.first { $0.title == "Compress" }?.detail, "Shrink with macOS’s Reduce File Size filter")
    }

    func testActionsFlowerOffersTheSameSixPetalsForAnyFile() async {
        let expected = ["AirDrop", "Float", "Copy", "Move", "Copy Path", "Terminal"]
        let forImage = await titles(["photo.png"], .actions)
        let forSelection = await titles(["notes.txt", "clip.mov"], .actions)
        XCTAssertEqual(forImage, expected)
        XCTAssertEqual(forSelection, expected)
    }
}
