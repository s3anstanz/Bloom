import AppKit
import BloomCore
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

    func testEveryImagePetalWorks() async throws {
        let png = try Fixtures.image(in: folder)
        let jpg = try Fixtures.image(in: folder, name: "photo.jpg", type: .jpeg, transparent: false)
        await assertEveryPetalWorks(for: [png])
        await assertEveryPetalWorks(for: [jpg])
    }

    func testEveryDocumentPetalWorks() async throws {
        let txt = try Fixtures.textFile(in: folder, name: "notes.txt", contents: Fixtures.text)
        let rtf = try Fixtures.rtf(in: folder)
        let html = try Fixtures.textFile(
            in: folder,
            name: "page.html",
            contents: "<html><body><h1>Bloom</h1><p>\(Fixtures.text)</p></body></html>"
        )
        await assertEveryPetalWorks(for: [txt])
        await assertEveryPetalWorks(for: [rtf])
        await assertEveryPetalWorks(for: [html])
    }

    func testEveryPDFPetalWorks() async throws {
        let pdf = try Fixtures.pdf(in: folder)
        await assertEveryPetalWorks(for: [pdf])
    }

    func testEveryAudioPetalWorks() async throws {
        let tone = try Fixtures.audio(in: folder)
        await assertEveryPetalWorks(for: [tone])
    }

    func testEveryVideoPetalWorks() async throws {
        let clip = try await Fixtures.video(in: folder)
        await assertEveryPetalWorks(for: [clip])
    }

    func testEverySubtitlePetalWorks() async throws {
        let srt = try Fixtures.textFile(in: folder, name: "captions.srt", contents: Fixtures.srt)
        let vtt = try Fixtures.textFile(in: folder, name: "captions.vtt", contents: Fixtures.vtt)
        await assertEveryPetalWorks(for: [srt])
        await assertEveryPetalWorks(for: [vtt])
    }

    func testArchiveAndFolderPetalsWork() async throws {
        let notes = try Fixtures.textFile(in: folder, name: "notes.txt", contents: Fixtures.text)
        let tarball = try Fixtures.tarball(in: folder, containing: notes)
        let directory = try Fixtures.directory(in: folder)
        await assertEveryPetalWorks(for: [tarball])
        await assertEveryPetalWorks(for: [directory])
    }

    func testMultiFilePetalsWork() async throws {
        let pdf = try Fixtures.pdf(in: folder)
        let png = try Fixtures.image(in: folder)
        await assertEveryPetalWorks(for: [pdf, png])

        let notes = try Fixtures.textFile(in: folder, name: "notes.txt", contents: Fixtures.text)
        let photo = try Fixtures.image(in: folder, name: "photo.jpg", type: .jpeg, transparent: false)
        await assertEveryPetalWorks(for: [notes, photo])
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

    func testCompressingLowSampleRateMonoAudioWorksAtEveryLevel() async throws {
        let voice = try Fixtures.audio(in: folder, name: "voice.wav", sampleRate: 22_050, channels: 1)
        defer { UserDefaults.standard.removeObject(forKey: CompressionSetting.key) }
        for level in CompressionSetting.choices {
            UserDefaults.standard.set(level, forKey: CompressionSetting.key)
            let outputs = try await Engine.apply(.compress, to: [voice])
            XCTAssertEqual(outputs.first?.pathExtension, "m4a", "level \(level)")
            if let output = outputs.first, let problem = await defect(in: output) {
                XCTFail("level \(level): \(problem)")
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
