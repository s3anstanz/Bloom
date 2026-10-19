import BloomCore
import XCTest

final class FolderAccessTests: XCTestCase {
    private var folder: URL!
    private var home: URL!

    override func setUpWithError() throws {
        folder = try Fixtures.makeFolder()
        home = folder.appendingPathComponent("home")
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    func testFilesInsideProtectedFoldersAreRecognisedAtAnyDepth() {
        XCTAssertEqual(protected("Desktop/card.pdf"), .desktop)
        XCTAssertEqual(protected("Desktop/Taxes/2025/card.pdf"), .desktop)
        XCTAssertEqual(protected("Documents/card.pdf"), .documents)
        XCTAssertEqual(protected("Downloads/card.pdf"), .downloads)
    }

    func testOtherFoldersAreNotProtected() {
        XCTAssertNil(protected("Desktop2/card.pdf"))
        XCTAssertNil(protected("Pictures/card.pdf"))
        XCTAssertNil(protected("card.pdf"))
        XCTAssertNil(FolderAccess.protectedFolder(containing: URL(fileURLWithPath: "/Volumes/Drive/Desktop/card.pdf"), home: home))
    }

    func testTheMessageNamesEachFolderOnce() {
        let desktop = FolderAccess.deniedMessage(for: files("Desktop/a.pdf", "Desktop/Sub/b.pdf"), home: home)
        XCTAssertEqual(desktop, "Allow Bloom to use your Desktop folder in Privacy & Security → Files & Folders.")

        let two = FolderAccess.deniedMessage(for: files("Downloads/a.pdf", "Desktop/b.pdf"), home: home)
        XCTAssertEqual(two, "Allow Bloom to use your Desktop and Downloads folders in Privacy & Security → Files & Folders.")

        let three = FolderAccess.deniedMessage(for: files("Documents/a", "Downloads/b", "Desktop/c"), home: home)
        XCTAssertEqual(three, "Allow Bloom to use Desktop, Documents and Downloads in Privacy & Security → Files & Folders.")
    }

    func testTheMessageIsGeneralWhenTheFolderIsUnknown() {
        let message = FolderAccess.deniedMessage(for: [URL(fileURLWithPath: "/Volumes/Drive/a.pdf")], home: home)
        XCTAssertEqual(message, "macOS won’t let Bloom AirDrop this. Check Privacy & Security → Files & Folders.")
    }

    func testRequestReportsWhetherTheFolderCanBeRead() async throws {
        let readable = try Fixtures.directory(in: folder)
        let isReadable = await FolderAccess.request(readable)
        XCTAssertTrue(isReadable)

        let locked = folder.appendingPathComponent("Locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let isLockedReadable = await FolderAccess.request(locked)
        XCTAssertFalse(isLockedReadable)
    }

    private func protected(_ path: String) -> FolderAccess.Folder? {
        FolderAccess.protectedFolder(containing: home.appendingPathComponent(path), home: home)
    }

    private func files(_ paths: String...) -> [URL] {
        paths.map { home.appendingPathComponent($0) }
    }
}
