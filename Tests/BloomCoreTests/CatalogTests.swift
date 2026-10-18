import BloomCore
import XCTest

final class CatalogTests: XCTestCase {
    private func titles(_ paths: [String], _ mode: Mode) -> [String] {
        WheelCatalog.items(for: paths.map { URL(fileURLWithPath: "/tmp/\($0)") }, mode: mode).map(\.title)
    }

    func testImageOffersOtherFormatsButNotItsOwn() {
        let titles = titles(["photo.png"], .convert)
        XCTAssertFalse(titles.contains("PNG"))
        XCTAssertTrue(titles.contains("JPG"))
        XCTAssertTrue(titles.contains("PDF"))
    }

    func testPDFConvertsToImagesAndText() {
        XCTAssertEqual(titles(["report.pdf"], .convert), ["PNG", "JPG", "TXT"])
    }

    func testVideoOffersAudioExtractionAndGIF() {
        let items = WheelCatalog.items(for: [URL(fileURLWithPath: "/tmp/clip.mov")], mode: .convert)
        XCTAssertEqual(items.map(\.title), ["MP4", "M4V", "GIF", "M4A"])
        XCTAssertEqual(items.first { $0.title == "M4A" }?.detail, "Extract the audio as M4A")
    }

    func testSelectionOffersOnlyConversionsEveryFileSupports() {
        XCTAssertEqual(titles(["photo.png", "clip.mov"], .convert), ["GIF"])
    }

    func testSubtitlesConvertToTheOtherSubtitleFormat() {
        XCTAssertEqual(titles(["captions.srt"], .convert), ["VTT"])
        XCTAssertEqual(titles(["captions.vtt"], .convert), ["SRT"])
    }

    func testArchiveOffersExtractButNoConversions() {
        XCTAssertEqual(titles(["bundle.tar.gz"], .convert), [])
        XCTAssertEqual(titles(["bundle.tar.gz"], .tools), ["Extract", "Zip"])
    }

    func testFolderCanOnlyBeZipped() throws {
        let folder = try Fixtures.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(WheelCatalog.items(for: [folder], mode: .convert).count, 0)
        XCTAssertEqual(WheelCatalog.items(for: [folder], mode: .tools).map(\.title), ["Zip"])
    }

    func testMergePDFNeedsTwoOrMorePDFsOrImages() {
        XCTAssertFalse(titles(["report.pdf"], .tools).contains("Merge PDF"))
        XCTAssertTrue(titles(["report.pdf", "photo.png"], .tools).contains("Merge PDF"))
        XCTAssertFalse(titles(["report.pdf", "notes.txt"], .tools).contains("Merge PDF"))
    }

    func testPDFCompressionNamesTheFilterItUses() {
        let compress = WheelCatalog.items(for: [URL(fileURLWithPath: "/tmp/report.pdf")], mode: .tools).first { $0.title == "Compress" }
        XCTAssertEqual(compress?.detail, "Shrink with macOS’s Reduce File Size filter")
    }

    func testActionsFlowerOffersTheSameSixPetalsForAnyFile() {
        let expected = ["AirDrop", "Float", "Copy", "Move", "Copy Path", "Terminal"]
        XCTAssertEqual(titles(["photo.png"], .actions), expected)
        XCTAssertEqual(titles(["notes.txt", "clip.mov"], .actions), expected)
    }
}
