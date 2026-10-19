import AVFoundation
import AppKit
import CoreImage
import ImageIO
import PDFKit
import Quartz
import UniformTypeIdentifiers
import Vision

public struct ConversionError: LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Every conversion and tool runs locally with macOS frameworks and built-in command-line tools.
public enum Engine {
    /// Runs a Convert or Tools petal on what was dropped on it and returns what it saved. The app's drop and the tests
    /// both go through here, so the tests run what a drop runs. Actions run in the app, so they return nil.
    public static func run(_ operation: WheelItem.Operation, on files: [URL]) async throws -> [URL]? {
        switch operation {
        case .convert(let format): return try await convert(files, to: format)
        case .tool(let tool): return try await apply(tool, to: files)
        case .compress(let level): return try await compress(files, level: level)
        case .action: return nil
        }
    }

    public static func convert(_ files: [URL], to format: Format) async throws -> [URL] {
        var outputs: [URL] = []
        for file in files where !format.matches(file) {
            do {
                outputs.append(try await convertOne(file, to: format))
            } catch {
                discard(outputs)
                throw ConversionError("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return outputs
    }

    public static func apply(_ tool: Tool, to files: [URL]) async throws -> [URL] {
        switch tool {
        case .compress:
            return try await compress(files, level: .balanced)
        case .mergePDF:
            return [try mergePDF(files)]
        case .zip:
            return [try await archive(files)]
        default:
            var outputs: [URL] = []
            for file in files {
                do {
                    outputs.append(try await applyOne(tool, to: file))
                } catch {
                    discard(outputs)
                    throw ConversionError("\(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return outputs
        }
    }

    /// Compresses each file at `level` beside the original. A result that isn't smaller than its original is thrown
    /// away, and when none is smaller nothing is saved.
    public static func compress(_ files: [URL], level: CompressionLevel) async throws -> [URL] {
        var outputs: [URL] = []
        for file in files {
            do {
                let output = try await compressOne(file, kind: FileKind(file), level: level)
                if fileSize(output) < fileSize(file) {
                    outputs.append(output)
                } else {
                    discard([output])
                }
            } catch {
                discard(outputs)
                throw ConversionError("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        guard !outputs.isEmpty else { throw AlreadySmall(level: level, files: files.count) }
        return outputs
    }

    public static func canWriteImage(_ format: Format) -> Bool {
        guard let type = format.imageType else { return false }
        return writableImageTypes.contains(type.identifier)
    }

    private static let writableImageTypes = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    // MARK: Conversions

    private static func convertOne(_ file: URL, to format: Format) async throws -> URL {
        switch (FileKind(file), format) {
        case (.image, .pdf):
            return try imageToPDF(file)
        case (.image, _):
            return try convertImage(file, to: format)
        case (.pdf, .txt):
            return try pdfToText(file)
        case (.pdf, _):
            return try pdfToImages(file, format: format)
        case (.video, .gif):
            return try await videoToGIF(file)
        case (.video, .m4a):
            return try await export(AVURLAsset(url: file), from: file, presets: [AVAssetExportPresetAppleM4A], as: .m4a, ext: "m4a")
        case (.video, .mp4):
            return try await reencode(file, as: .mp4, ext: "mp4")
        case (.video, .mov):
            return try await reencode(file, as: .mov, ext: "mov")
        case (.video, .m4v):
            return try await reencode(file, as: .m4v, ext: "m4v")
        case (.audio, _):
            return try await convertAudio(file, to: format)
        case (.document, .pdf):
            return try await documentToPDF(file)
        case (.document, _):
            return try await convertDocument(file, to: format)
        case (.subtitle, _):
            return try convertSubtitle(file, to: format)
        default:
            throw ConversionError("Can’t convert this file to \(format.title).")
        }
    }

    private static func convertImage(_ file: URL, to format: Format) throws -> URL {
        guard let type = format.imageType else { throw ConversionError("\(format.title) isn’t an image format.") }
        let output = outputURL(for: file, ext: format.rawValue)
        try writeImage(loadImage(file), to: output, type: type)
        return output
    }

    private static func imageToPDF(_ file: URL) throws -> URL {
        let document = PDFDocument()
        try appendImage(file, to: document)
        let output = outputURL(for: file, ext: "pdf")
        guard document.write(to: output) else {
            discard([output])
            throw ConversionError("Couldn’t save the PDF.")
        }
        return output
    }

    private static func pdfToText(_ file: URL) throws -> URL {
        guard let text = PDFDocument(url: file)?.string,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ConversionError("No text found. This PDF may be scanned images.")
        }
        let output = outputURL(for: file, ext: "txt")
        try text.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    private static func pdfToImages(_ file: URL, format: Format) throws -> URL {
        guard let type = format.imageType else { throw ConversionError("\(format.title) isn’t an image format.") }
        guard let document = CGPDFDocument(file as CFURL), document.numberOfPages > 0 else {
            throw ConversionError("Couldn’t open this PDF.")
        }
        let pageCount = document.numberOfPages
        if pageCount == 1, let page = document.page(at: 1) {
            let output = outputURL(for: file, ext: format.rawValue)
            try writeImage(render(page), to: output, type: type)
            return output
        }
        let folder = outputURL(for: file, ext: nil, suffix: " (\(format.title))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            for number in 1...pageCount {
                guard let page = document.page(at: number) else { continue }
                let name = pageName(number, of: pageCount)
                try writeImage(render(page), to: folder.appendingPathComponent(name).appendingPathExtension(format.rawValue), type: type)
            }
        } catch {
            discard([folder])
            throw error
        }
        return folder
    }

    private static func videoToGIF(_ file: URL) async throws -> URL {
        let asset = AVURLAsset(url: file)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw ConversionError("This video has no frames.") }
        let fps = 12.0
        let frameCount = max(1, Int(min(duration, 60) * fps))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let output = outputURL(for: file, ext: "gif")
        guard let gif = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw ConversionError("Couldn’t create the GIF.")
        }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        do {
            for index in 0..<frameCount {
                let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
                let frame = try await generator.image(at: time).image
                CGImageDestinationAddImage(gif, frame, frameProperties)
            }
            guard CGImageDestinationFinalize(gif) else { throw ConversionError("Couldn’t save the GIF.") }
        } catch {
            discard([output])
            throw error
        }
        return output
    }

    private static func reencode(_ file: URL, as fileType: AVFileType, ext: String) async throws -> URL {
        try await export(
            AVURLAsset(url: file),
            from: file,
            presets: [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality],
            as: fileType,
            ext: ext
        )
    }

    /// Tries each preset in order; passthrough fails for codecs the container can't hold, so a re-encode follows it.
    private static func export(
        _ asset: AVAsset,
        from file: URL,
        presets: [String],
        as fileType: AVFileType,
        ext: String,
        suffix: String = ""
    ) async throws -> URL {
        let output = outputURL(for: file, ext: ext, suffix: suffix)
        var lastError: Error = ConversionError("This file can’t be saved as \(ext.uppercased()).")
        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset),
                session.supportedFileTypes.contains(fileType)
            else { continue }
            session.outputURL = output
            session.outputFileType = fileType
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { done.resume() }
            }
            if session.status == .completed { return output }
            lastError = session.error ?? lastError
            discard([output])
        }
        throw lastError
    }

    private static func convertAudio(_ file: URL, to format: Format) async throws -> URL {
        let settings: [String]
        switch format {
        case .m4a: settings = ["-f", "m4af", "-d", "aac"]
        case .wav: settings = ["-f", "WAVE", "-d", "LEI16"]
        case .aiff: settings = ["-f", "AIFF", "-d", "BEI16"]
        default: throw ConversionError("Can’t convert audio to \(format.title).")
        }
        let output = outputURL(for: file, ext: format.rawValue)
        do {
            try await shell("/usr/bin/afconvert", settings + [file.path, output.path])
        } catch {
            discard([output])
            throw error
        }
        return output
    }

    private static func convertDocument(_ file: URL, to format: Format) async throws -> URL {
        let output = outputURL(for: file, ext: format.rawValue)
        var arguments = ["-convert", format.rawValue, "-output", output.path]
        if UTType(filenameExtension: file.pathExtension)?.conforms(to: .plainText) == true {
            arguments += ["-format", "txt"]
        }
        do {
            try await shell("/usr/bin/textutil", arguments + [file.path])
        } catch {
            discard([output])
            throw error
        }
        return output
    }

    /// Bloom.app ships the BloomRender helper next to its executable. AppKit prints text only on a main thread, so
    /// rendering in the helper keeps the app's main thread free; without the helper (tests) it renders in-process.
    private static func documentToPDF(_ file: URL) async throws -> URL {
        let output = outputURL(for: file, ext: "pdf")
        do {
            if let helper = Bundle.main.url(forAuxiliaryExecutable: "BloomRender") {
                try await shell(helper.path, [file.path, output.path])
            } else {
                try await DocumentRenderer.renderPDF(from: file, to: output)
            }
        } catch {
            discard([output])
            throw error
        }
        return output
    }

    private static func convertSubtitle(_ file: URL, to format: Format) throws -> URL {
        let raw = try (try? String(contentsOf: file, encoding: .utf8)) ?? String(contentsOf: file, encoding: .isoLatin1)
        let lines =
            raw
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        let converted: String
        switch format {
        case .vtt:
            let body = lines.map { $0.contains("-->") ? $0.replacingOccurrences(of: ",", with: ".") : $0 }
            converted = "WEBVTT\n\n" + body.joined(separator: "\n")
        case .srt:
            converted = srt(fromVTT: lines)
        default:
            throw ConversionError("Can’t convert subtitles to \(format.title).")
        }
        let output = outputURL(for: file, ext: format.rawValue)
        try converted.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    private static func srt(fromVTT lines: [String]) -> String {
        var cues: [String] = []
        for block in lines.split(separator: "") {
            guard let timing = block.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = block[timing].components(separatedBy: "-->")
            let endToken = parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
            let text = block[block.index(after: timing)...].joined(separator: "\n")
            cues.append("\(cues.count + 1)\n\(srtTimestamp(parts[0])) --> \(srtTimestamp(endToken))\n\(text)")
        }
        return cues.joined(separator: "\n\n") + "\n"
    }

    /// WebVTT allows "mm:ss.ttt"; SRT requires "hh:mm:ss,ttt".
    private static func srtTimestamp(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ",")
        return value.filter { $0 == ":" }.count == 1 ? "00:" + value : value
    }

    // MARK: Tools

    private static func applyOne(_ tool: Tool, to file: URL) async throws -> URL {
        let kind = FileKind(file)
        switch tool {
        case .compress:
            return try await compressOne(file, kind: kind, level: .balanced)
        case .halfSize:
            return try editImage(file, suffix: " (50%)", scale: 0.5) { $0 }
        case .rotate:
            if kind == .pdf { return try rotatePDF(file) }
            return try editImage(file, suffix: " (rotated)") { try rotatedRight($0) }
        case .flip:
            return try editImage(file, suffix: " (flipped)") { try flipped($0) }
        case .grayscale:
            return try editImage(file, suffix: " (grayscale)") { try grayscale($0) }
        case .stripMetadata:
            return try editImage(file, suffix: " (no metadata)") { $0 }
        case .removeBackground:
            guard #available(macOS 14, *) else { throw ConversionError("Remove Background needs macOS 14 or later.") }
            return try removeBackground(file)
        case .mute:
            return try await mute(file)
        case .splitPages:
            return try splitPages(file)
        case .extract:
            return try await extract(file)
        case .mergePDF, .zip:
            throw ConversionError("\(tool.title) works on the whole selection.")
        }
    }

    private static func compressOne(_ file: URL, kind: FileKind, level: CompressionLevel) async throws -> URL {
        switch kind {
        case .video:
            let asset = AVURLAsset(url: file)
            return try await export(asset, from: file, presets: [level.videoPreset], as: .mp4, ext: "mp4", suffix: " (compressed)")
        case .audio:
            let output = outputURL(for: file, ext: "m4a", suffix: " (compressed)")
            let aac = ["-f", "m4af", "-d", "aac"]
            // Apple's AAC encoder only accepts certain bitrates for each sample rate and channel count (it rejects the
            // rest with '!dat'). Stepping down to the next one it takes keeps each size at or below what it promises.
            let requested = level.audioBitratePerChannel * CompressionLevel.channels(of: file)
            for bitrate in [requested] + CompressionLevel.aacBitrates.filter({ $0 < requested }) {
                do {
                    try await shell("/usr/bin/afconvert", aac + ["-b", String(bitrate), file.path, output.path])
                    return output
                } catch {
                    discard([output])
                }
            }
            // Its default bitrate always works.
            do {
                try await shell("/usr/bin/afconvert", aac + [file.path, output.path])
            } catch {
                discard([output])
                throw error
            }
            return output
        case .pdf:
            return try compressPDF(file)
        default:
            let transparent = CompressionLevel.isTransparent(file)
            let output = outputURL(for: file, ext: transparent ? "png" : "jpg", suffix: " (compressed)")
            try writeImage(
                loadImage(file, maxPixelSize: level.maxPixelSize), to: output, type: transparent ? .png : .jpeg, quality: level.jpegQuality)
            return output
        }
    }

    private static func compressPDF(_ file: URL) throws -> URL {
        guard let document = PDFDocument(url: file) else { throw ConversionError("Couldn’t open this PDF.") }
        // Preview's own "Reduce File Size" Quartz filter; PDFKit accepts it under the "QuartzFilter" write option.
        let reduceFileSize: QuartzFilter? = QuartzFilter(url: URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter"))
        guard let filter = reduceFileSize else { throw ConversionError("macOS’s Reduce File Size filter is missing.") }
        let output = outputURL(for: file, ext: "pdf", suffix: " (compressed)")
        guard document.write(to: output, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]) else {
            discard([output])
            throw ConversionError("Couldn’t save the compressed PDF.")
        }
        return output
    }

    private static func editImage(
        _ file: URL,
        suffix: String,
        scale: Double = 1,
        transform: (CGImage) throws -> CGImage
    ) throws -> URL {
        let format = Format.allCases.first { canWriteImage($0) && $0.matches(file) } ?? .png
        let output = outputURL(for: file, ext: format.rawValue, suffix: suffix)
        try writeImage(transform(loadImage(file, scale: scale)), to: output, type: format.imageType ?? .png, quality: 0.95)
        return output
    }

    private static func rotatedRight(_ image: CGImage) throws -> CGImage {
        let context = try canvas(width: image.height, height: image.width)
        context.translateBy(x: 0, y: CGFloat(image.width))
        context.rotate(by: -.pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try snapshot(context)
    }

    private static func flipped(_ image: CGImage) throws -> CGImage {
        let context = try canvas(width: image.width, height: image.height)
        context.translateBy(x: CGFloat(image.width), y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try snapshot(context)
    }

    private static func grayscale(_ image: CGImage) throws -> CGImage {
        guard
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else { throw ConversionError("Couldn’t prepare the image.") }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return try snapshot(context)
    }

    @available(macOS 14.0, *)
    private static func removeBackground(_ file: URL) throws -> URL {
        let image = try loadImage(file)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw ConversionError("Couldn’t find a subject in this image.")
        }
        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )
        let masked = CIImage(cvPixelBuffer: buffer)
        guard let cutout = CIContext().createCGImage(masked, from: masked.extent) else {
            throw ConversionError("Couldn’t remove the background.")
        }
        let output = outputURL(for: file, ext: "png", suffix: " (no background)")
        try writeImage(cutout, to: output, type: .png)
        return output
    }

    private static func mute(_ file: URL) async throws -> URL {
        let asset = AVURLAsset(url: file)
        let composition = AVMutableComposition()
        var videoTracks = 0
        for track in try await asset.loadTracks(withMediaType: .video) {
            guard let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                continue
            }
            let range = try await track.load(.timeRange)
            try copy.insertTimeRange(range, of: track, at: range.start)
            copy.preferredTransform = try await track.load(.preferredTransform)
            videoTracks += 1
        }
        guard videoTracks > 0 else { throw ConversionError("This file has no video.") }
        let isMOV = file.pathExtension.lowercased() == "mov"
        return try await export(
            composition,
            from: file,
            presets: [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality],
            as: isMOV ? .mov : .mp4,
            ext: isMOV ? "mov" : "mp4",
            suffix: " (muted)"
        )
    }

    private static func rotatePDF(_ file: URL) throws -> URL {
        guard let document = PDFDocument(url: file) else { throw ConversionError("Couldn’t open this PDF.") }
        for index in 0..<document.pageCount {
            if let page = document.page(at: index) {
                page.rotation = (page.rotation + 90) % 360
            }
        }
        let output = outputURL(for: file, ext: "pdf", suffix: " (rotated)")
        guard document.write(to: output) else {
            discard([output])
            throw ConversionError("Couldn’t save the PDF.")
        }
        return output
    }

    private static func splitPages(_ file: URL) throws -> URL {
        guard let document = PDFDocument(url: file), document.pageCount > 0 else {
            throw ConversionError("Couldn’t open this PDF.")
        }
        let folder = outputURL(for: file, ext: nil, suffix: " (pages)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            try writePages(of: document, into: folder)
        } catch {
            discard([folder])
            throw error
        }
        return folder
    }

    private static func writePages(of document: PDFDocument, into folder: URL) throws {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            let destination = folder.appendingPathComponent(pageName(index + 1, of: document.pageCount)).appendingPathExtension("pdf")
            guard single.write(to: destination) else { throw ConversionError("Couldn’t save page \(index + 1).") }
        }
    }

    private static func mergePDF(_ files: [URL]) throws -> URL {
        let sorted = files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let merged = PDFDocument()
        for file in sorted {
            if FileKind(file) == .pdf {
                guard let document = PDFDocument(url: file) else { throw ConversionError("Couldn’t open \(file.lastPathComponent).") }
                for index in 0..<document.pageCount {
                    if let page = document.page(at: index)?.copy() as? PDFPage {
                        merged.insert(page, at: merged.pageCount)
                    }
                }
            } else {
                try appendImage(file, to: merged)
            }
        }
        let output = uniqueURL(in: sorted[0].deletingLastPathComponent(), base: "Merged", ext: "pdf")
        guard merged.write(to: output) else {
            discard([output])
            throw ConversionError("Couldn’t save the merged PDF.")
        }
        return output
    }

    private static func extract(_ file: URL) async throws -> URL {
        var base = file.deletingPathExtension().lastPathComponent
        if base.lowercased().hasSuffix(".tar") { base = String(base.dropLast(4)) }
        let folder = uniqueURL(in: file.deletingLastPathComponent(), base: base, ext: nil)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            if file.pathExtension.lowercased() == "zip" {
                try await shell("/usr/bin/ditto", ["-x", "-k", file.path, folder.path])
            } else {
                try await shell("/usr/bin/tar", ["-xf", file.path, "-C", folder.path])
            }
        } catch {
            discard([folder])
            throw error
        }
        return folder
    }

    private static func archive(_ files: [URL]) async throws -> URL {
        let folder = files[0].deletingLastPathComponent()
        if files.count == 1 {
            let output = uniqueURL(in: folder, base: files[0].lastPathComponent, ext: "zip")
            do {
                try await shell("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", files[0].path, output.path])
            } catch {
                discard([output])
                throw error
            }
            return output
        }
        guard files.allSatisfy({ $0.deletingLastPathComponent().path == folder.path }) else {
            throw ConversionError("Zip files from one folder at a time.")
        }
        let output = uniqueURL(in: folder, base: "Archive", ext: "zip")
        // "./" keeps a name like "-m" from being read as zip's move-and-delete option; -nw stops zip expanding * and ? in names.
        let names = files.map { "./" + $0.lastPathComponent }
        do {
            try await shell("/usr/bin/zip", ["-r", "-q", "-X", "-nw", output.lastPathComponent] + names, in: folder)
        } catch {
            discard([output])
            throw error
        }
        return output
    }

    // MARK: Images

    private static func loadImage(_ file: URL, scale: Double = 1, maxPixelSize: Int? = nil) throws -> CGImage {
        if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        {
            var size = Int(Double(max(width, height)) * scale)
            if let maxPixelSize { size = min(size, maxPixelSize) }
            // A full-size "thumbnail" applies the EXIF orientation so photos stay upright.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(size, 1),
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return image
            }
        }
        if let image = NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return image
        }
        throw ConversionError("Couldn’t read this image.")
    }

    private static func writeImage(_ image: CGImage, to output: URL, type: UTType, quality: Double = 0.9) throws {
        let opaqueTypes: Set<UTType> = [.jpeg, .bmp]
        let finalImage = try opaqueTypes.contains(type) ? flattened(image) : image
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError("This Mac can’t write \(type.preferredFilenameExtension?.uppercased() ?? "this format").")
        }
        CGImageDestinationAddImage(destination, finalImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            discard([output])
            throw ConversionError("Couldn’t save the image.")
        }
    }

    /// Puts transparent images on white so JPEG and BMP output doesn't turn transparency black.
    private static func flattened(_ image: CGImage) throws -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return image
        default:
            break
        }
        guard
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { throw ConversionError("Couldn’t prepare the image.") }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return try snapshot(context)
    }

    private static func canvas(width: Int, height: Int) throws -> CGContext {
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw ConversionError("Couldn’t prepare the image.") }
        context.interpolationQuality = .high
        return context
    }

    private static func snapshot(_ context: CGContext) throws -> CGImage {
        guard let image = context.makeImage() else { throw ConversionError("Couldn’t prepare the image.") }
        return image
    }

    private static func appendImage(_ file: URL, to document: PDFDocument) throws {
        let image = try loadImage(file)
        guard let page = PDFPage(image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))) else {
            throw ConversionError("Couldn’t add \(file.lastPathComponent) to the PDF.")
        }
        document.insert(page, at: document.pageCount)
    }

    private static func render(_ page: CGPDFPage, scale: CGFloat = 2) throws -> CGImage {
        let box = page.getBoxRect(.cropBox)
        let size = page.rotationAngle % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        guard
            let context = CGContext(
                data: nil,
                width: Int(size.width * scale),
                height: Int(size.height * scale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { throw ConversionError("Couldn’t render this PDF.") }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.concatenate(
            page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return try snapshot(context)
    }

    // MARK: Files

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    /// Deletes results Bloom created, so a failure never leaves a partial result beside the user's files.
    private static func discard(_ outputs: [URL]) {
        for output in outputs {
            try? FileManager.default.removeItem(at: output)
        }
    }

    private static func pageName(_ number: Int, of count: Int) -> String {
        let label = String(number)
        return "Page " + String(repeating: "0", count: String(count).count - label.count) + label
    }

    private static func outputURL(for file: URL, ext: String?, suffix: String = "") -> URL {
        uniqueURL(
            in: file.deletingLastPathComponent(),
            base: file.deletingPathExtension().lastPathComponent + suffix,
            ext: ext
        )
    }

    /// Finder-style naming: "photo.jpg", then "photo 2.jpg", "photo 3.jpg"…
    public static func uniqueURL(in folder: URL, base: String, ext: String?) -> URL {
        func candidate(_ name: String) -> URL {
            let url = folder.appendingPathComponent(name)
            return ext.map { url.appendingPathExtension($0) } ?? url
        }
        var url = candidate(base)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = candidate("\(base) \(counter)")
            counter += 1
        }
        return url
    }

    private static func shell(_ tool: String, _ arguments: [String], in directory: URL? = nil) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        // stderr goes to a file: a pipe nobody drains while the tool runs blocks it once ~64 KB of warnings pile up.
        let errorLog = FileManager.default.temporaryDirectory.appendingPathComponent("bloom-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errorLog.path, contents: nil)
        let errors = try FileHandle(forWritingTo: errorLog)
        process.standardError = errors
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finished in
                try? errors.close()
                let log = (try? String(contentsOf: errorLog, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(at: errorLog)
                if finished.terminationStatus == 0 {
                    continuation.resume()
                    return
                }
                let message = log.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = "\(URL(fileURLWithPath: tool).lastPathComponent) failed."
                continuation.resume(throwing: ConversionError(message.isEmpty ? fallback : message))
            }
            do {
                try process.run()
            } catch {
                try? errors.close()
                try? FileManager.default.removeItem(at: errorLog)
                continuation.resume(throwing: error)
            }
        }
    }
}
