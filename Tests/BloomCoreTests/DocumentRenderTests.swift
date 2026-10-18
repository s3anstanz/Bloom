import CoreGraphics
import XCTest

final class DocumentRenderTests: XCTestCase {
    func testHelperRendersADocumentToPDFOutsideTheApp() throws {
        let folder = try Fixtures.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let notes = try Fixtures.rtf(in: folder)
        let output = folder.appendingPathComponent("notes.pdf")
        let helper = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("BloomRender")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: helper.path), "BloomRender should be built next to the tests")

        let process = Process()
        process.executableURL = helper
        process.arguments = [notes.path, output.path]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(CGPDFDocument(output as CFURL)?.numberOfPages, 1)
    }
}
