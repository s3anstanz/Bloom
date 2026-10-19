import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// The three flowers: ⇧ Convert, ⌘ Tools, ⌃ Actions.
public enum Mode {
    case convert, tools, actions
}

public enum FileKind {
    case image, pdf, video, audio, document, subtitle, archive, other

    private static let subtitleExtensions: Set<String> = ["srt", "vtt"]
    private static let archiveExtensions: Set<String> = ["zip", "tar", "tgz", "tbz", "txz"]
    /// Compressed tarballs end in .tar plus one of these. On its own, each is a single compressed file that tar can't unpack.
    private static let tarballCompressionExtensions: Set<String> = ["gz", "bz2", "xz"]
    private static let documentTypes: [UTType] =
        [.rtf, .rtfd, .html, .plainText]
        + [
            "org.openxmlformats.wordprocessingml.document",
            "com.microsoft.word.doc",
            "org.oasis-open.opendocument.text",
        ].compactMap { UTType($0) }

    public init(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isPackageKey])
        let type = values?.contentType ?? UTType(filenameExtension: ext) ?? .data
        let isTarball = Self.tarballCompressionExtensions.contains(ext) && url.deletingPathExtension().pathExtension.lowercased() == "tar"
        if values?.isDirectory == true && values?.isPackage != true {
            self = .other
        } else if Self.subtitleExtensions.contains(ext) {
            self = .subtitle
        } else if Self.archiveExtensions.contains(ext) || isTarball {
            self = .archive
        } else if type.conforms(to: .pdf) {
            self = .pdf
        } else if type.conforms(to: .image) {
            self = .image
        } else if type.conforms(to: .movie) {
            self = .video
        } else if type.conforms(to: .audio) {
            self = .audio
        } else if Self.documentTypes.contains(where: { type.conforms(to: $0) }) {
            self = .document
        } else {
            self = .other
        }
    }
}

public enum Format: String, CaseIterable {
    case jpg, png, heic, webp, avif, tiff, gif, bmp, jp2, pdf
    case mp4, mov, m4v, m4a, wav, aiff
    case docx, rtf, txt, html, odt
    case srt, vtt

    public var title: String { rawValue.uppercased() }

    public var symbol: String {
        switch self {
        case .jpg: return "photo"
        case .png: return "photo.on.rectangle"
        case .heic: return "camera"
        case .webp: return "globe"
        case .avif: return "photo.artframe"
        case .tiff: return "square.stack.fill"
        case .gif: return "sparkles"
        case .bmp: return "square.grid.3x3"
        case .jp2: return "photo.fill"
        case .pdf: return "doc.richtext"
        case .mp4: return "film"
        case .mov: return "video"
        case .m4v: return "play.rectangle"
        case .m4a: return "music.note"
        case .wav: return "waveform"
        case .aiff: return "hifispeaker"
        case .docx: return "doc.text"
        case .rtf: return "textformat"
        case .txt: return "text.alignleft"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .odt: return "doc"
        case .srt: return "captions.bubble"
        case .vtt: return "text.bubble"
        }
    }

    public var imageType: UTType? {
        switch self {
        case .jpg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .webp: return .webP
        case .avif: return UTType("public.avif")
        case .tiff: return .tiff
        case .gif: return .gif
        case .bmp: return .bmp
        case .jp2: return UTType("public.jpeg-2000")
        default: return nil
        }
    }

    public func matches(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch self {
        case .jpg: return ext == "jpg" || ext == "jpeg"
        case .tiff: return ext == "tif" || ext == "tiff"
        case .html: return ext == "html" || ext == "htm"
        case .aiff: return ext == "aif" || ext == "aiff"
        default: return ext == rawValue
        }
    }
}

public enum Tool: CaseIterable {
    case compress, halfSize, rotate, flip, grayscale, removeBackground, stripMetadata
    case mute, splitPages, mergePDF, extract, zip

    public var title: String {
        switch self {
        case .compress: return "Compress"
        case .halfSize: return "Half Size"
        case .rotate: return "Rotate"
        case .flip: return "Flip"
        case .grayscale: return "Grayscale"
        case .removeBackground: return "Remove BG"
        case .stripMetadata: return "No Meta"
        case .mute: return "Mute"
        case .splitPages: return "Split"
        case .mergePDF: return "Merge PDF"
        case .extract: return "Extract"
        case .zip: return "Zip"
        }
    }

    public var symbol: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .halfSize: return "minus.magnifyingglass"
        case .rotate: return "rotate.right"
        case .flip: return "arrow.left.and.right"
        case .grayscale: return "circle.lefthalf.filled"
        case .removeBackground: return "wand.and.stars"
        case .stripMetadata: return "eye.slash"
        case .mute: return "speaker.slash"
        case .splitPages: return "square.split.2x1"
        case .mergePDF: return "doc.on.doc"
        case .extract: return "archivebox"
        case .zip: return "doc.zipper"
        }
    }

    public var detail: String {
        switch self {
        case .compress: return "Make it smaller"
        case .halfSize: return "Resize to 50%"
        case .rotate: return "Rotate 90° clockwise"
        case .flip: return "Flip horizontally"
        case .grayscale: return "Make it black and white"
        case .removeBackground: return "Cut out the subject"
        case .stripMetadata: return "Remove location and camera data"
        case .mute: return "Remove the audio track"
        case .splitPages: return "One PDF per page"
        case .mergePDF: return "Combine into one PDF"
        case .extract: return "Unpack into a folder"
        case .zip: return "Compress into a .zip"
        }
    }

    public var progress: String {
        switch self {
        case .compress: return "Compressing…"
        case .halfSize: return "Resizing…"
        case .rotate: return "Rotating…"
        case .flip: return "Flipping…"
        case .grayscale: return "Converting to grayscale…"
        case .removeBackground: return "Removing background…"
        case .stripMetadata: return "Removing metadata…"
        case .mute: return "Muting…"
        case .splitPages: return "Splitting…"
        case .mergePDF: return "Merging…"
        case .extract: return "Extracting…"
        case .zip: return "Zipping…"
        }
    }

    func applies(to files: [URL], kinds: [FileKind]) -> Bool {
        let all = { (allowed: Set<FileKind>) in kinds.allSatisfy { allowed.contains($0) } }
        switch self {
        case .compress: return all([.image, .video, .audio, .pdf])
        case .halfSize, .flip, .grayscale, .stripMetadata: return all([.image])
        case .rotate: return all([.image]) || all([.pdf])
        case .removeBackground:
            if #available(macOS 14, *) { return all([.image]) }
            return false
        case .mute: return all([.video])
        case .splitPages: return all([.pdf])
        case .mergePDF: return kinds.count > 1 && all([.pdf, .image])
        case .extract: return all([.archive])
        case .zip: return Set(files.map { $0.deletingLastPathComponent().path }).count == 1
        }
    }
}

public enum QuickAction: CaseIterable {
    case airDrop, float, copy, move, copyPath, terminal

    public var title: String {
        switch self {
        case .airDrop: return "AirDrop"
        case .float: return "Float"
        case .copy: return "Copy"
        case .move: return "Move"
        case .copyPath: return "Copy Path"
        case .terminal: return "Terminal"
        }
    }

    public var symbol: String {
        switch self {
        case .airDrop: return "dot.radiowaves.left.and.right"
        case .float: return "macwindow.on.rectangle"
        case .copy: return "doc.on.clipboard"
        case .move: return "folder"
        case .copyPath: return "link"
        case .terminal: return "terminal"
        }
    }

    public var detail: String {
        switch self {
        case .airDrop: return "Send with AirDrop"
        case .float: return "Keep it floating on screen to drag later"
        case .copy: return "Copy the file, then paste it anywhere"
        case .move: return "Move to a folder you pick"
        case .copyPath: return "Copy the full path"
        case .terminal: return "Open its folder in Terminal"
        }
    }

    public var progress: String {
        switch self {
        case .airDrop: return "Opening AirDrop…"
        case .float: return "Floating…"
        case .copy: return "Copying…"
        case .move: return "Choose a folder…"
        case .copyPath: return "Copying path…"
        case .terminal: return "Opening Terminal…"
        }
    }
}

/// One petal: what it shows and what it does.
public struct WheelItem: Identifiable {
    public enum Operation {
        case convert(Format)
        case tool(Tool)
        case compress(CompressionLevel)
        case action(QuickAction)
    }

    public let operation: Operation
    public let title: String
    public let symbol: String
    public let detail: String
    public let progress: String
    /// A second, shorter line under the title, like a size's "720p".
    public internal(set) var badge: String?
    /// Petals that bloom past this one's tip when the pointer rests on it, like Compress's sizes. Only the first petal
    /// has them, so they open above the flower.
    public internal(set) var choices: [WheelItem] = []

    public var id: String { title }
}

public enum WheelCatalog {
    /// The petals a flower offers for the dragged files: only what can actually work on all of them.
    public static func items(for files: [URL], mode: Mode) async -> [WheelItem] {
        let kinds = files.map(FileKind.init)
        switch mode {
        case .convert:
            var offered = formats(for: kinds).filter { format in !files.allSatisfy(format.matches) }
            if offered.contains(.m4a), await !videosHaveAudio(files) {
                offered.removeAll { $0 == .m4a }
            }
            return offered.map { format in
                WheelItem(
                    operation: .convert(format),
                    title: format.title,
                    symbol: format.symbol,
                    detail: detail(for: format, kinds: kinds),
                    progress: "Converting to \(format.title)…"
                )
            }
        case .tools:
            let channels = kinds.allSatisfy { $0 == .audio } ? audioChannels(files) : nil
            return Tool.allCases
                .filter { $0.applies(to: files, kinds: kinds) }
                .map { tool -> WheelItem in
                    if tool == .compress { return compressItem(kinds: kinds, audioChannels: channels) }
                    return WheelItem(
                        operation: .tool(tool), title: tool.title, symbol: tool.symbol, detail: tool.detail, progress: tool.progress)
                }
        case .actions:
            return QuickAction.allCases
                .map { WheelItem(operation: .action($0), title: $0.title, symbol: $0.symbol, detail: $0.detail, progress: $0.progress) }
        }
    }

    /// Dropping on Compress makes the Balanced size, and resting on it opens all three, each captioned with what it makes
    /// of these files. PDFs go through macOS's filter, which has one size.
    private static func compressItem(kinds: [FileKind], audioChannels: Int?) -> WheelItem {
        let tool = Tool.compress
        func detail(_ level: CompressionLevel) -> String {
            guard let result = level.result(for: kinds, audioChannels: audioChannels) else { return "Compress at the \(level.title) size" }
            return "Compress to \(result.detail)"
        }
        guard !kinds.allSatisfy({ $0 == .pdf }) else {
            return WheelItem(
                operation: .compress(.balanced),
                title: tool.title,
                symbol: tool.symbol,
                detail: "Shrink with macOS’s Reduce File Size filter",
                progress: tool.progress
            )
        }
        let sizes = CompressionLevel.allCases.map { level in
            WheelItem(
                operation: .compress(level),
                title: level.title,
                symbol: tool.symbol,
                detail: detail(level),
                progress: tool.progress,
                badge: level.result(for: kinds, audioChannels: audioChannels)?.badge
            )
        }
        return WheelItem(
            operation: .compress(.balanced),
            title: tool.title,
            symbol: tool.symbol,
            detail: detail(.balanced),
            progress: tool.progress,
            choices: sizes
        )
    }

    /// The channel count every file compresses to, or nil when they differ.
    private static func audioChannels(_ files: [URL]) -> Int? {
        let counts = Set(files.map(CompressionLevel.channels))
        return counts.count == 1 ? counts.first : nil
    }

    /// Videos without a soundtrack, such as most screen recordings, can't become M4A.
    private static func videosHaveAudio(_ files: [URL]) async -> Bool {
        for file in files where FileKind(file) == .video {
            let tracks = (try? await AVURLAsset(url: file).loadTracks(withMediaType: .audio)) ?? []
            if tracks.isEmpty { return false }
        }
        return true
    }

    private static func formats(for kinds: [FileKind]) -> [Format] {
        guard let first = kinds.first else { return [] }
        return kinds.dropFirst().reduce(targets(for: first)) { shared, kind in
            let allowed = targets(for: kind)
            return shared.filter { allowed.contains($0) }
        }
    }

    private static func targets(for kind: FileKind) -> [Format] {
        switch kind {
        case .image:
            return [Format.jpg, .png, .heic, .webp, .avif, .tiff, .gif, .bmp, .jp2].filter(Engine.canWriteImage) + [.pdf]
        case .pdf: return [.png, .jpg, .txt]
        case .video: return [.mp4, .mov, .m4v, .gif, .m4a]
        case .audio: return [.m4a, .wav, .aiff]
        case .document: return [.pdf, .docx, .rtf, .txt, .html, .odt]
        case .subtitle: return [.srt, .vtt]
        case .archive, .other: return []
        }
    }

    private static func detail(for format: Format, kinds: [FileKind]) -> String {
        if kinds.allSatisfy({ $0 == .video }) {
            if format == .m4a { return "Extract the audio as M4A" }
            if format == .gif { return "Make a GIF (first 60 seconds)" }
        }
        return "Convert to \(format.title)"
    }
}
