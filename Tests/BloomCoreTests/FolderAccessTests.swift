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

    func testAFileAsksForItsFolderAndAFolderAsksForItself() throws {
        let desktop = home.appendingPathComponent("Desktop")
        let project = desktop.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let card = try Fixtures.textFile(in: desktop, name: "card.txt", contents: Fixtures.text)

        XCTAssertEqual(FolderAccess.requestTarget(for: card).path, desktop.path)
        // Asking for the Desktop's parent, the home folder, would never bring up the Desktop prompt.
        XCTAssertEqual(FolderAccess.requestTarget(for: desktop).path, desktop.path)
        XCTAssertEqual(FolderAccess.requestTarget(for: project).path, project.path)
    }

    @MainActor
    func testOnlyFilesInDeniedFoldersAreStillRefused() async throws {
        let desktop = try folder(named: "Desktop")
        let downloads = try folder(named: "Downloads")
        let mac = FakeMac(answers: [desktop.path: true, downloads.path: false])
        let a = desktop.appendingPathComponent("a.pdf")
        let b = downloads.appendingPathComponent("b.pdf")

        let refusal = await FolderAccess.resolve([a, b], canShare: mac.canShare, request: mac.request, pause: 0)

        XCTAssertEqual(refusal.inDeniedFolders, [b])
        XCTAssertEqual(refusal.otherwise, [])
        XCTAssertEqual(mac.asked, [desktop.path, downloads.path])
    }

    @MainActor
    func testAnAllowThatMacOSAppliesLateStillCounts() async throws {
        let desktop = try folder(named: "Desktop")
        let mac = FakeMac(answers: [desktop.path: true], checksBeforeApplied: 3)

        let refusal = await FolderAccess.resolve(
            [desktop.appendingPathComponent("a.pdf")], canShare: mac.canShare, request: mac.request, pause: 0)

        XCTAssertTrue(refusal.isEmpty)
    }

    @MainActor
    func testDontAllowFailsWithoutWaiting() async throws {
        let desktop = try folder(named: "Desktop")
        let mac = FakeMac(answers: [desktop.path: false])
        let file = desktop.appendingPathComponent("a.pdf")

        let refusal = await FolderAccess.resolve([file], canShare: mac.canShare, request: mac.request, pause: 0)

        XCTAssertEqual(refusal.inDeniedFolders, [file])
        XCTAssertEqual(refusal.otherwise, [])
        XCTAssertEqual(mac.checks, 1)
    }

    @MainActor
    func testAFileRefusedAlthoughItsFolderIsAllowedIsNotBlamedOnTheFolder() async throws {
        // AirDrop itself being off looks like this: the folder is readable, and AirDrop still says no.
        let desktop = try folder(named: "Desktop")
        let mac = FakeMac(answers: [desktop.path: true], checksBeforeApplied: .max)
        let file = desktop.appendingPathComponent("a.pdf")

        let refusal = await FolderAccess.resolve([file], canShare: mac.canShare, request: mac.request, attempts: 5, pause: 0)

        XCTAssertEqual(refusal.inDeniedFolders, [])
        XCTAssertEqual(refusal.otherwise, [file])
        XCTAssertEqual(mac.checks, 5)
    }

    private func folder(named name: String) throws -> URL {
        let url = home.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func protected(_ path: String) -> FolderAccess.Folder? {
        FolderAccess.protectedFolder(containing: home.appendingPathComponent(path), home: home)
    }

    private func files(_ paths: String...) -> [URL] {
        paths.map { home.appendingPathComponent($0) }
    }
}

/// Stands in for macOS: a folder's answer to the prompt, and AirDrop's check, which only passes once an Allow is applied.
@MainActor
private final class FakeMac {
    private let answers: [String: Bool]
    private let checksBeforeApplied: Int
    private var allowed: Set<String> = []
    private(set) var asked: [String] = []
    private(set) var checks = 0

    init(answers: [String: Bool], checksBeforeApplied: Int = 0) {
        self.answers = answers
        self.checksBeforeApplied = checksBeforeApplied
    }

    func request(_ folder: URL) async -> Bool {
        asked.append(folder.path)
        let answer = answers[folder.path] ?? false
        if answer { allowed.insert(folder.path) }
        return answer
    }

    func canShare(_ file: URL) -> Bool {
        checks += 1
        return allowed.contains(file.deletingLastPathComponent().path) && checks > checksBeforeApplied
    }
}
