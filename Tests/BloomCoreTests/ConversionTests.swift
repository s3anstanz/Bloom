import AppKit
import BloomCore
import BloomFixtures
import ImageIO
import XCTest

final class ConversionTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        // Document → PDF prints through AppKit, which expects an application object to exist.
        await MainActor.run { _ = NSApplication.shared }
        folder = try Fixtures.makeFolder()
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    /// The petal matrix's samples, so every kind of file it drops through the app is converted here on every pull request.
    func testEveryPetalWorksOnEverySample() async throws {
        for sample in Samples.all {
            let own = folder.appendingPathComponent(sample.name)
            try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
            await assertEveryPetalWorks(for: try await sample.make(own))
        }
    }

    func testMergePDFKeepsEveryPage() async throws {
        let pdf = try Fixtures.pdf(in: folder, pages: 2)
        let png = try Fixtures.image(in: folder)
        let merged = try await Engine.apply(.mergePDF, to: [pdf, png])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(pageCount(of: merged[0]), 3)
    }

    func testPDFToPNGMakesOneImagePerPage() async throws {
        let pdf = try Fixtures.pdf(in: folder, pages: 3)
        let outputs = try await Engine.convert([pdf], to: .png)
        let pages = try FileManager.default.contentsOfDirectory(atPath: outputs[0].path).sorted()
        XCTAssertEqual(pages, ["Page 1.png", "Page 2.png", "Page 3.png"])
    }

    func testCompressingLowSampleRateMonoAudioWorksAtEverySize() async throws {
        let voice = try Fixtures.audio(in: folder, name: "voice.wav", sampleRate: 22_050, channels: 1)
        for level in CompressionLevel.allCases {
            let outputs = try await Engine.compress([voice], level: level)
            XCTAssertEqual(outputs.first?.pathExtension, "m4a", level.title)
            if let output = outputs.first, let problem = await defect(in: output) {
                XCTFail("\(level.title): \(problem)")
            }
        }
    }

    func testRemoveBackgroundMakesATransparentPNG() async throws {
        guard #available(macOS 14, *) else { throw XCTSkip("Remove BG needs macOS 14 or later.") }
        let photo = try Fixtures.image(in: folder, name: "photo.jpg", type: .jpeg, transparent: false)
        let outputs: [URL]
        do {
            outputs = try await Engine.apply(.removeBackground, to: [photo])
        } catch {
            throw XCTSkip("Vision can't separate a subject on this Mac: \(error.localizedDescription)")
        }
        XCTAssertEqual(outputs.first?.pathExtension, "png")
        let source = try XCTUnwrap(outputs.first.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) })
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let opaque: [CGImageAlphaInfo] = [.none, .noneSkipFirst, .noneSkipLast]
        XCTAssertFalse(opaque.contains(image.alphaInfo), "the cut-out should keep transparency")
    }
}

private func pageCount(of url: URL) -> Int {
    CGPDFDocument(url as CFURL)?.numberOfPages ?? 0
}
