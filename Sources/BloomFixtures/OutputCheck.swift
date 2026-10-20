import AVFoundation
import AppKit
import BloomCore
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Why a file Bloom saved is unusable, or nil when it exists, has content and opens as the type its extension claims.
/// A folder, like Split's pages, needs something in it, and each thing in it is checked the same way.
public func defect(in url: URL) async -> String? {
    let name = url.lastPathComponent
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return "\(name) is missing" }
    if isFolder.boolValue {
        let contents = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }
        guard !contents.isEmpty else { return "\(name) is an empty folder" }
        for item in contents.sorted() {
            if let problem = await defect(in: url.appendingPathComponent(item)) { return "\(name)/\(problem)" }
        }
        return nil
    }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    guard size > 0 else { return "\(name) is empty" }
    let ext = url.pathExtension.lowercased()
    switch FileKind(url) {
    case .image:
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            CGImageSourceCreateImageAtIndex(source, 0, nil) != nil,
            let found = CGImageSourceGetType(source).map({ $0 as String })
        else { return "\(name) can't be opened as an image" }
        if let claimed = UTType(filenameExtension: ext), found != claimed.identifier {
            return "\(name) is really \(found)"
        }
    case .pdf:
        guard (PDFDocument(url: url)?.pageCount ?? 0) > 0 else { return "\(name) can't be opened as a PDF" }
    case .video:
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        let pictures = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        guard seconds > 0, !pictures.isEmpty else { return "\(name) has no playable video" }
    case .audio:
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        let sound = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard seconds > 0, !sound.isEmpty else { return "\(name) has no playable audio" }
    case .document:
        return documentDefect(in: url, ext: ext)
    case .subtitle:
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let valid = ext == "vtt" ? text.hasPrefix("WEBVTT") : text.first?.isNumber == true && text.contains(" --> ")
        return valid ? nil : "\(name) isn't a valid \(ext.uppercased()) file"
    case .archive:
        guard ext == "zip" else { return nil }
        return succeeds("/usr/bin/unzip", ["-tqq", url.path]) ? nil : "\(name) isn't a valid zip archive"
    case .other:
        break
    }
    return nil
}

private func documentDefect(in url: URL, ext: String) -> String? {
    let name = url.lastPathComponent
    switch ext {
    case "txt":
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(name) has no text" : nil
    case "html", "htm":
        // Reading HTML as rich text loads WebKit, so a look at the markup stands in for opening it.
        let text = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").lowercased()
        return text.contains("<html") || text.contains("<!doctype html") ? nil : "\(name) isn't HTML"
    default:
        let types: [String: NSAttributedString.DocumentType] = ["rtf": .rtf, "docx": .officeOpenXML, "odt": .openDocument]
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = types[ext].map { [.documentType: $0] } ?? [:]
        guard let document = try? NSAttributedString(url: url, options: options, documentAttributes: nil),
            !document.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "\(name) can't be opened as a \(ext.uppercased()) document" }
        return nil
    }
}

private func succeeds(_ path: String, _ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}
