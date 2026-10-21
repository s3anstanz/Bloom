import BloomCore
import BloomFixtures
import XCTest

final class FieldGuideTests: XCTestCase {
    /// What a petal shows: its name, icon, caption and sizes.
    private struct Shown: Equatable {
        let title: String
        let symbol: String
        let detail: String
        let badge: String?
        let choices: [Shown]

        init(_ item: WheelItem) {
            title = item.title
            symbol = item.symbol
            detail = item.detail
            badge = item.badge
            choices = item.choices.map(Shown.init)
        }
    }

    /// A real file of each kind, like the one the guide pictures for it.
    private func realFile(_ kind: FieldGuide.Kind, in folder: URL) async throws -> URL {
        switch kind {
        case .photo: return try Fixtures.image(in: folder, name: "photo.jpg", type: .jpeg, transparent: false)
        case .video: return try await Fixtures.video(in: folder)
        case .pdf: return try Fixtures.pdf(in: folder)
        case .song: return try Fixtures.audio(in: folder, name: "song.m4a", channels: 2)
        case .document: return try Fixtures.document(in: folder, name: "notes.docx", type: .officeOpenXML)
        case .other: return try Fixtures.textFile(in: folder, name: "data.unknownkind", contents: Fixtures.text)
        }
    }

    func testEveryKindShowsThePetalsTheRealFlowerOffersThatFile() async throws {
        let folder = try Fixtures.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for kind in FieldGuide.Kind.allCases {
            let file = try await realFile(kind, in: folder)
            for mode in FlowerTabs.modes {
                let real = await WheelCatalog.items(for: [file], mode: mode).map(Shown.init)
                let guide = FieldGuide.items(for: kind, mode: mode).map(Shown.init)
                XCTAssertEqual(guide, real, "\(kind.title), \(mode)")
            }
        }
    }

    func testTheOtherChipShowsWhatAFolderGets() async throws {
        let folder = try Fixtures.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let directory = try Fixtures.directory(in: folder)
        for mode in FlowerTabs.modes {
            let real = await WheelCatalog.items(for: [directory], mode: mode).map(Shown.init)
            XCTAssertEqual(FieldGuide.items(for: .other, mode: mode).map(Shown.init), real, "\(mode)")
        }
    }

    func testTheGuidePicturesTypicalFiles() {
        func titles(_ kind: FieldGuide.Kind, _ mode: Mode) -> [String] { FieldGuide.items(for: kind, mode: mode).map(\.title) }
        XCTAssertEqual(titles(.video, .convert), ["MP4", "M4V", "GIF", "M4A"], "A video with sound can become M4A")
        XCTAssertFalse(titles(.photo, .convert).contains("JPG"), "A photo isn't offered its own format")
        XCTAssertEqual(FieldGuide.items(for: .photo, mode: .tools).first?.detail, "Compress to JPG, up to 2400 px")
        XCTAssertEqual(titles(.song, .convert), ["WAV", "AIFF"])
        XCTAssertEqual(titles(.other, .convert), [])
        XCTAssertEqual(titles(.other, .tools), ["Zip"])
        for kind in FieldGuide.Kind.allCases {
            XCTAssertEqual(titles(kind, .actions), QuickAction.allCases.map(\.title), kind.title)
        }
    }

    func testCaptionsSayWhatAPetalDoesAndHowToPickAnotherSize() {
        func compress(_ kind: FieldGuide.Kind) -> String? {
            FieldGuide.items(for: kind, mode: .tools).first { $0.title == Tool.compress.title }.map(FieldGuide.caption)
        }
        XCTAssertEqual(compress(.photo), "Compress: Compress to JPG, up to 2400 px. Rest on it for 1600 or 3200 px.")
        XCTAssertEqual(compress(.video), "Compress: Compress to MP4, up to 720p. Rest on it for 540p or 1080p.")
        XCTAssertEqual(compress(.song), "Compress: Compress to AAC, 128 kbps. Rest on it for 64 or 192 kbps.")
        XCTAssertEqual(compress(.pdf), "Compress: Shrink with macOS’s Reduce File Size filter", "The filter has one size")
        let zip = FieldGuide.items(for: .other, mode: .tools)[0]
        XCTAssertEqual(FieldGuide.caption(for: zip), "Zip: Pack into a .zip")
    }

    func testAPetalThatCantWorkSaysWhy() throws {
        var airDrop = try XCTUnwrap(FieldGuide.items(for: .photo, mode: .actions).first)
        airDrop.unavailable = "AirDrop isn’t available on this Mac"
        XCTAssertEqual(FieldGuide.caption(for: airDrop), "AirDrop isn’t available on this Mac")
    }

    func testPanelSitsUnderTheIconAndStaysOnScreen() {
        // A 1440 × 900 screen whose menu bar takes the top 24 points.
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 876)
        let size = CGSize(width: 344, height: 200)
        let icon = CGRect(x: 1180, y: 876, width: 30, height: 24)
        let under = FieldGuide.origin(under: icon, size: size, in: screen)
        XCTAssertEqual(under.y, 876 - 2 - 200, "All but touching the menu bar, as if it came from the icon")
        XCTAssertEqual(under.x + size.width * 0.85, icon.midX, accuracy: 0.01, "The icon is above the panel's right side")

        let nearEdge = FieldGuide.origin(under: CGRect(x: 1420, y: 876, width: 20, height: 24), size: size, in: screen)
        XCTAssertEqual(nearEdge.x + size.width, 1440 - 8, "Kept clear of the screen's right edge")
        let farLeft = FieldGuide.origin(under: CGRect(x: 20, y: 876, width: 20, height: 24), size: size, in: screen)
        XCTAssertEqual(farLeft.x, 8, "Kept clear of the screen's left edge")
        let unknown = FieldGuide.origin(under: nil, size: size, in: screen)
        XCTAssertEqual(unknown, CGPoint(x: 1440 - 8 - 344, y: 876 - 8 - 200), "Top right without the icon")

        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        let onSecond = FieldGuide.origin(under: CGRect(x: 3000, y: 1055, width: 30, height: 25), size: size, in: second)
        XCTAssertTrue(second.contains(CGRect(origin: onSecond, size: size)), "On the screen with the icon")
    }

    func testFirstLaunchCardShowsUntilAnswered() throws {
        let suite = "FieldGuideTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(FirstLaunchCard(defaults: defaults).isDue)
        FirstLaunchCard(defaults: defaults).answered()
        XCTAssertFalse(FirstLaunchCard(defaults: defaults).isDue, "Answered once, it never shows again")
    }
}
