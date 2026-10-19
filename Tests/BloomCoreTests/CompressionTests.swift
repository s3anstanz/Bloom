import BloomCore
import BloomFixtures
import ImageIO
import XCTest

final class CompressionTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try Fixtures.makeFolder()
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func size(_ url: URL) throws -> Int {
        try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    private func pixels(_ url: URL) throws -> (Int, Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }

    func testEachSizeShrinksAPhotoToItsLongestSide() async throws {
        let photo = try Fixtures.photo(in: folder, width: 3200, height: 2000, quality: 1)
        let expected: [CompressionLevel: (Int, Int)] = [.smaller: (1600, 1000), .balanced: (2400, 1500), .sharper: (3200, 2000)]
        for level in CompressionLevel.allCases {
            let outputs = try await Engine.compress([photo], level: level)
            XCTAssertEqual(outputs.count, 1, level.title)
            let output = try XCTUnwrap(outputs.first)
            XCTAssertEqual(output.pathExtension, "jpg", level.title)
            let (width, height) = try pixels(output)
            XCTAssertEqual(width, expected[level]?.0, level.title)
            XCTAssertEqual(height, expected[level]?.1, level.title)
            XCTAssertLessThan(try size(output), try size(photo), level.title)
        }
    }

    func testSmallerSizesMakeSmallerFiles() async throws {
        let photo = try Fixtures.photo(in: folder, width: 3200, height: 2000, quality: 1)
        var sizes: [Int] = []
        for level in CompressionLevel.allCases {
            let outputs = try await Engine.compress([photo], level: level)
            sizes.append(try size(try XCTUnwrap(outputs.first)))
        }
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertEqual(Set(sizes).count, sizes.count)
    }

    func testEachAudioSizeMakesASmallerFileThanTheNext() async throws {
        let hiss = try Fixtures.audio(in: folder, name: "hiss.wav", seconds: 4, noise: true)
        var sizes: [Int] = []
        for level in CompressionLevel.allCases {
            let outputs = try await Engine.compress([hiss], level: level)
            sizes.append(try size(try XCTUnwrap(outputs.first)))
        }
        XCTAssertEqual(sizes, sizes.sorted())
        XCTAssertEqual(Set(sizes).count, sizes.count, "Each size should make a different file: \(sizes)")
    }

    func testEachVideoSizeMakesAPlayableMP4SmallerThanTheOriginal() async throws {
        let clip = try await Fixtures.video(in: folder, detailed: true)
        let original = try size(clip)
        for level in CompressionLevel.allCases {
            let output = try XCTUnwrap(try await Engine.compress([clip], level: level).first)
            XCTAssertEqual(output.lastPathComponent, "clip (compressed).mp4")
            XCTAssertLessThan(try size(output), original, level.title)
            let problem = await defect(in: output)
            XCTAssertNil(problem, level.title)
            try FileManager.default.removeItem(at: output)
        }
    }

    func testCompressingWhatWouldNotShrinkSavesNothing() async throws {
        let tiny = try Fixtures.photo(in: folder, name: "tiny.jpg", width: 256, height: 256, quality: 0.05)
        do {
            _ = try await Engine.compress([tiny], level: .sharper)
            XCTFail("A result bigger than the original should not be saved")
        } catch {
            XCTAssertTrue(error is AlreadySmall)
            XCTAssertEqual(error.localizedDescription, "Sharper wouldn’t make it any smaller, so nothing was saved.")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["tiny.jpg"])
    }

    func testASelectionKeepsOnlyTheResultsThatShrank() async throws {
        let photo = try Fixtures.photo(in: folder, width: 3200, height: 2000, quality: 1)
        let tiny = try Fixtures.photo(in: folder, name: "tiny.jpg", width: 256, height: 256, quality: 0.05)
        let outputs = try await Engine.compress([photo, tiny], level: .sharper)
        XCTAssertEqual(outputs.map(\.lastPathComponent), ["photo (compressed).jpg"])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
            ["photo (compressed).jpg", "photo.jpg", "tiny.jpg"]
        )
    }

    func testDroppingOnCompressMakesTheBalancedSize() async throws {
        let photo = try Fixtures.photo(in: folder, width: 3200, height: 2000, quality: 1)
        let outputs = try await Engine.apply(.compress, to: [photo])
        let (width, height) = try pixels(try XCTUnwrap(outputs.first))
        XCTAssertEqual(width, 2400)
        XCTAssertEqual(height, 1500)
    }
}
