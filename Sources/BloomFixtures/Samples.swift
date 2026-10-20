import Foundation

/// A file, or a selection of files, of a kind Bloom handles. The unit tests run every Convert and Tools petal on each
/// sample, and the petal matrix drops each one on every petal through the real app, so a new kind of file added here is
/// tested both ways.
public struct Sample {
    public let name: String
    /// The matrix also tries each petal in the Actions flower, which offers the same six for any file.
    public var actions = false
    public let make: (URL) async throws -> [URL]
}

public enum Samples {
    public static let all: [Sample] = [
        // A circle and a box, so Remove BG has a subject to cut out; the journeys compress a detailed photo.
        Sample(name: "JPEG picture", actions: true) { [try Fixtures.image(in: $0, name: "picture.jpg", type: .jpeg, transparent: false)] },
        Sample(name: "PNG with transparency") { [try Fixtures.image(in: $0)] },
        Sample(name: "PDF") { [try Fixtures.pdf(in: $0)] },
        Sample(name: "Video with sound") { [try await Fixtures.video(in: $0, detailed: true)] },
        Sample(name: "Screen recording without sound") { [try await Fixtures.silentVideo(in: $0)] },
        Sample(name: "WAV audio") { [try Fixtures.audio(in: $0, seconds: 2, noise: true)] },
        Sample(name: "Plain text") { [try Fixtures.textFile(in: $0, name: "notes.txt", contents: Fixtures.text)] },
        Sample(name: "RTF") { [try Fixtures.rtf(in: $0)] },
        Sample(name: "HTML") {
            [try Fixtures.textFile(in: $0, name: "page.html", contents: "<html><body><h1>Bloom</h1><p>\(Fixtures.text)</p></body></html>")]
        },
        Sample(name: "Word") { [try Fixtures.document(in: $0, name: "letter.docx", type: .officeOpenXML)] },
        Sample(name: "OpenDocument") { [try Fixtures.document(in: $0, name: "letter.odt", type: .openDocument)] },
        Sample(name: "SRT subtitles") { [try Fixtures.textFile(in: $0, name: "captions.srt", contents: Fixtures.srt)] },
        Sample(name: "WebVTT subtitles") { [try Fixtures.textFile(in: $0, name: "captions.vtt", contents: Fixtures.vtt)] },
        Sample(name: "Tarball") { folder in
            let notes = try Fixtures.textFile(in: folder, name: "notes.txt", contents: Fixtures.text)
            let tarball = try Fixtures.tarball(in: folder, containing: notes)
            try FileManager.default.removeItem(at: notes)
            return [tarball]
        },
        Sample(name: "Folder", actions: true) { [try Fixtures.directory(in: $0)] },
        Sample(name: "PDF and PNG", actions: true) { [try Fixtures.pdf(in: $0), try Fixtures.image(in: $0)] },
        Sample(name: "Text and photo") {
            [
                try Fixtures.textFile(in: $0, name: "notes.txt", contents: Fixtures.text),
                try Fixtures.image(in: $0, name: "photo.jpg", type: .jpeg, transparent: false),
            ]
        },
    ]

    /// Every sample, or those whose name contains one of `filters`, ignoring case.
    public static func matching(_ filters: Set<String>) -> [Sample] {
        guard !filters.isEmpty else { return all }
        return all.filter { sample in filters.contains { sample.name.localizedCaseInsensitiveContains($0) } }
    }
}

/// The bytes of every file in a sample, a folder's included, so a check can tell whether a petal touched the original.
public struct Originals {
    private let contents: [String: Data]

    public init(_ files: [URL]) {
        contents = Self.snapshot(files)
    }

    /// Why the sample isn't as it was, or nil when every file, and everything in a folder, is there and unchanged.
    public func change(in files: [URL]) -> String? {
        for file in files where !FileManager.default.fileExists(atPath: file.path) {
            return "\(file.lastPathComponent) is gone."
        }
        let now = Self.snapshot(files)
        if let path = contents.keys.sorted().first(where: { now[$0] != contents[$0] }) {
            return now[path] == nil ? "\(path) is gone." : "\(path) was changed."
        }
        if let added = now.keys.sorted().first(where: { contents[$0] == nil }) {
            return "\(added) appeared inside the sample."
        }
        return nil
    }

    private static func snapshot(_ files: [URL]) -> [String: Data] {
        var contents: [String: Data] = [:]
        for file in files {
            let parent = file.deletingLastPathComponent().path + "/"
            var paths = [file]
            // Finder's hidden .DS_Store files come and go with the windows it shows, so they don't count.
            if let walk = FileManager.default.enumerator(at: file, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                paths += walk.compactMap { $0 as? URL }
            }
            for path in paths where !path.hasDirectoryPath || path == file {
                if let data = try? Data(contentsOf: path) {
                    contents[String(path.path.dropFirst(parent.count))] = data
                }
            }
        }
        return contents
    }
}
