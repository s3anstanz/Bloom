import BloomCore
import BloomFixtures
import XCTest

final class SubtitleTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try Fixtures.makeFolder()
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    func testSRTBecomesWebVTT() async throws {
        let srt = try Fixtures.textFile(in: folder, name: "captions.srt", contents: Fixtures.srt)
        let outputs = try await Engine.convert([srt], to: .vtt)
        let vtt = try String(contentsOf: outputs[0], encoding: .utf8)
        XCTAssertEqual(
            vtt,
            "WEBVTT\n\n1\n00:00:00.000 --> 00:00:02.000\nHello from Bloom\n\n2\n00:00:02.500 --> 00:00:04.000\nSecond caption\n"
        )
    }

    func testWebVTTBecomesNumberedSRTWithFullTimestamps() async throws {
        let vtt = try Fixtures.textFile(in: folder, name: "captions.vtt", contents: Fixtures.vtt)
        let outputs = try await Engine.convert([vtt], to: .srt)
        let srt = try String(contentsOf: outputs[0], encoding: .utf8)
        XCTAssertEqual(
            srt,
            "1\n00:00:00,000 --> 00:00:02,000\nHello from Bloom\n\n2\n00:00:02,500 --> 00:00:04,000\nSecond caption\n"
        )
    }
}
