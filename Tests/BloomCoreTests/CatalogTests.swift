import BloomCore
import BloomFixtures
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
        XCTAssertEqual(items.first { $0.title == "M4A" }?.detail, "Just the soundtrack, as M4A")
    }

    func testConvertCaptionsSayWhatEachFormatIsFor() async {
        let photo = await WheelCatalog.items(for: [URL(fileURLWithPath: "/tmp/photo.png")], mode: .convert)
        XCTAssertEqual(photo.first { $0.title == "JPG" }?.detail, "Small, and opens anywhere")
        XCTAssertEqual(photo.first { $0.title == "TIFF" }?.detail, "Convert to TIFF")
        let report = await WheelCatalog.items(for: [URL(fileURLWithPath: "/tmp/report.pdf")], mode: .convert)
        XCTAssertEqual(report.map(\.detail), ["One PNG per page", "One JPG per page", "Pull out the text"])
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

    func testOnlyTarballsAmongCompressedFilesOfferExtract() async {
        let tarball = await titles(["bundle.tar.xz"], .tools)
        let compressedFile = await titles(["notes.txt.gz"], .tools)
        XCTAssertTrue(tarball.contains("Extract"))
        XCTAssertFalse(compressedFile.contains("Extract"))
    }

    func testFolderCanOnlyBeZipped() async throws {
        let folder = try Fixtures.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let conversions = await WheelCatalog.items(for: [folder], mode: .convert)
        let tools = await WheelCatalog.items(for: [folder], mode: .tools).map(\.title)
        XCTAssertEqual(conversions.count, 0)
        XCTAssertEqual(tools, ["Zip"])
    }

    func testFolderNamedLikeAnArchiveOrSubtitleCanOnlyBeZipped() async throws {
        let parent = try Fixtures.makeFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        for name in ["backup.zip", "bundle.tar.gz", "captions.srt"] {
            let folder = parent.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let conversions = await WheelCatalog.items(for: [folder], mode: .convert)
            let tools = await WheelCatalog.items(for: [folder], mode: .tools).map(\.title)
            XCTAssertEqual(conversions.count, 0, name)
            XCTAssertEqual(tools, ["Zip"], name)
        }
    }

    func testZipNeedsEverythingInOneFolder() async {
        let oneFolder = await titles(["notes.txt", "photo.png"], .tools)
        let twoFolders = await titles(["notes.txt", "Desktop/photo.png"], .tools)
        XCTAssertTrue(oneFolder.contains("Zip"))
        XCTAssertFalse(twoFolders.contains("Zip"))
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
        let compress = items.first { $0.title == "Compress" }
        XCTAssertEqual(compress?.detail, "Shrink with macOS’s Reduce File Size filter")
        XCTAssertEqual(compress?.choices.count, 0, "The filter has one size")
    }

    private func compress(_ paths: [String]) async -> WheelItem? {
        await WheelCatalog.items(for: paths.map { URL(fileURLWithPath: "/tmp/\($0)") }, mode: .tools).first { $0.title == "Compress" }
    }

    func testCompressOpensThreeSizesThatSayWhatTheyMakeOfAPhoto() async throws {
        let found = await compress(["photo.png"])
        let item = try XCTUnwrap(found)
        XCTAssertEqual(item.detail, "Compress to JPG, up to 2400 px")
        XCTAssertEqual(item.choices.map(\.title), ["Smaller", "Balanced", "Sharper"])
        XCTAssertEqual(item.choices.map(\.badge), ["1600 px", "2400 px", "3200 px"])
        XCTAssertEqual(item.choices.map(\.detail), ["Compress to JPG, up to 1600 px", item.detail, "Compress to JPG, up to 3200 px"])
    }

    func testCompressSaysTransparentPicturesStayPNG() async throws {
        let folder = try Fixtures.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transparent = try Fixtures.image(in: folder)
        let opaque = try Fixtures.image(in: folder, name: "opaque.png", transparent: false)
        let clear = await WheelCatalog.items(for: [transparent], mode: .tools).first { $0.title == "Compress" }
        XCTAssertEqual(clear?.detail, "Compress to PNG, up to 2400 px")
        XCTAssertEqual(clear?.choices.map(\.badge), ["1600 px", "2400 px", "3200 px"])
        let solid = await WheelCatalog.items(for: [opaque], mode: .tools).first { $0.title == "Compress" }
        XCTAssertEqual(solid?.detail, "Compress to JPG, up to 2400 px")
        let both = await WheelCatalog.items(for: [transparent, opaque], mode: .tools).first { $0.title == "Compress" }
        XCTAssertEqual(both?.detail, "Compress at the Balanced size")
    }

    func testOneClearPixelInAHugePictureKeepsItPNG() async throws {
        let folder = try Fixtures.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let picture = try Fixtures.image(in: folder, transparent: false, width: 8000, height: 500, clearPixel: true)
        let item = await WheelCatalog.items(for: [picture], mode: .tools).first { $0.title == "Compress" }
        XCTAssertEqual(item?.detail, "Compress to PNG, up to 2400 px")
    }

    func testCompressSizesForVideoAndAudio() async throws {
        let found = await compress(["clip.mov"])
        let video = try XCTUnwrap(found)
        XCTAssertEqual(video.detail, "Compress to MP4, up to 720p")
        XCTAssertEqual(video.choices.map(\.badge), ["540p", "720p", "1080p"])

        let monoVoice = try Fixtures.audio(in: try Fixtures.makeFolder(), name: "voice.wav", channels: 1)
        defer { try? FileManager.default.removeItem(at: monoVoice.deletingLastPathComponent()) }
        let mono = await WheelCatalog.items(for: [monoVoice], mode: .tools).first { $0.title == "Compress" }
        XCTAssertEqual(mono?.choices.map(\.badge), ["32 kbps", "64 kbps", "96 kbps"])
        XCTAssertEqual(mono?.detail, "Compress to AAC, 64 kbps")
    }

    func testCompressSizesForMixedFilesSayOnlyTheirNames() async throws {
        let found = await compress(["photo.png", "clip.mov"])
        let item = try XCTUnwrap(found)
        XCTAssertEqual(item.detail, "Compress at the Balanced size")
        XCTAssertEqual(item.choices.map(\.badge), [nil, nil, nil])
    }

    func testOnlyTheFirstPetalHasChoicesSoTheyOpenAboveTheFlower() async {
        for paths in [["photo.png"], ["clip.mov"], ["song.wav"], ["photo.png", "clip.mov"]] {
            let items = await WheelCatalog.items(for: paths.map { URL(fileURLWithPath: "/tmp/\($0)") }, mode: .tools)
            XCTAssertFalse(items.first?.choices.isEmpty ?? true, "\(paths)")
            XCTAssertTrue(items.dropFirst().allSatisfy { $0.choices.isEmpty }, "\(paths)")
        }
    }

    func testActionsFlowerOffersTheSameSixPetalsForAnyFile() async {
        let expected = ["AirDrop", "Float", "Copy", "Move", "Copy Path", "Terminal"]
        let forImage = await titles(["photo.png"], .actions)
        let forSelection = await titles(["notes.txt", "clip.mov"], .actions)
        XCTAssertEqual(forImage, expected)
        XCTAssertEqual(forSelection, expected)
    }
}
