import AVFoundation
import BloomCore
import ImageIO
import PDFKit
import XCTest

/// Runs every Convert and Tools petal offered for `files` and fails for any petal whose result is missing or won't open.
/// Remove BG is covered separately because it depends on the Mac's Vision support.
func assertEveryPetalWorks(for files: [URL], file: StaticString = #filePath, line: UInt = #line) async {
    for mode in [Mode.convert, .tools] {
        // A petal with choices does what one of them does, so each choice stands in for it.
        let petals = await WheelCatalog.items(for: files, mode: mode).flatMap { $0.choices.isEmpty ? [$0] : $0.choices }
        for item in petals {
            if case .tool(.removeBackground) = item.operation { continue }
            let label = "\(files.map(\.lastPathComponent).joined(separator: " + ")) → \(item.title)"
            do {
                let outputs: [URL]
                switch item.operation {
                case .convert(let format):
                    outputs = try await Engine.convert(files, to: format)
                case .tool(let tool):
                    outputs = try await Engine.apply(tool, to: files)
                case .compress(let level):
                    do {
                        outputs = try await Engine.compress(files, level: level)
                    } catch is AlreadySmall {
                        // A small generated sample can come out bigger; CompressionTests checks that real files shrink.
                        continue
                    }
                case .action:
                    continue
                }
                XCTAssertFalse(outputs.isEmpty, "\(label): no output", file: file, line: line)
                for output in outputs {
                    if let problem = await defect(in: output) {
                        XCTFail("\(label): \(problem)", file: file, line: line)
                    }
                }
            } catch {
                XCTFail("\(label): \(error.localizedDescription)", file: file, line: line)
            }
        }
    }
}

/// Why an output is unusable, or nil when it exists, has content and opens as its type.
func defect(in url: URL) async -> String? {
    let name = url.lastPathComponent
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return "\(name) is missing" }
    if isFolder.boolValue {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return contents.isEmpty ? "\(name) is an empty folder" : nil
    }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    guard size > 0 else { return "\(name) is empty" }
    switch FileKind(url) {
    case .image:
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            return "\(name) can't be opened as an image"
        }
    case .pdf:
        guard (PDFDocument(url: url)?.pageCount ?? 0) > 0 else { return "\(name) can't be opened as a PDF" }
    case .video, .audio:
        let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        guard seconds > 0 else { return "\(name) has no playable length" }
    default:
        break
    }
    return nil
}
