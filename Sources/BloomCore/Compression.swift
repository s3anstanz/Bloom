import AVFoundation
import Foundation
import ImageIO

/// The sizes that bloom past the Compress petal. Dropping on Compress itself uses `balanced`.
public enum CompressionLevel: CaseIterable {
    case smaller, balanced, sharper

    public var title: String {
        switch self {
        case .smaller: return "Smaller"
        case .balanced: return "Balanced"
        case .sharper: return "Sharper"
        }
    }

    /// The longest side of a compressed image, in pixels.
    var maxPixelSize: Int {
        switch self {
        case .smaller: return 1600
        case .balanced: return 2400
        case .sharper: return 3200
        }
    }

    var jpegQuality: Double {
        switch self {
        case .smaller: return 0.25
        case .balanced: return 0.5
        case .sharper: return 0.75
        }
    }

    /// The tallest a compressed video gets; AVFoundation's presets never enlarge a smaller one.
    var videoHeight: Int {
        switch self {
        case .smaller: return 540
        case .balanced: return 720
        case .sharper: return 1080
        }
    }

    var videoPreset: String {
        switch self {
        case .smaller: return AVAssetExportPreset960x540
        case .balanced: return AVAssetExportPreset1280x720
        case .sharper: return AVAssetExportPreset1920x1080
        }
    }

    var audioBitratePerChannel: Int {
        switch self {
        case .smaller: return 32_000
        case .balanced: return 64_000
        case .sharper: return 96_000
        }
    }

    /// What this size makes of files of these kinds: a short badge for its petal ("720p") and the end of its caption
    /// ("MP4, up to 720p"). Nil for a mix of kinds, whose results differ, and for PDFs, which have one size.
    /// `transparent` says whether the images show through anywhere, and is nil when some do and some don't.
    func result(for kinds: [FileKind], audioChannels: Int?, transparent: Bool?) -> (badge: String, detail: String)? {
        guard let kind = kinds.first, kinds.allSatisfy({ $0 == kind }) else { return nil }
        switch kind {
        case .image:
            guard let transparent else { return nil }
            return ("\(maxPixelSize) px", "\(transparent ? "PNG" : "JPEG"), up to \(maxPixelSize) px")
        case .video:
            return ("\(videoHeight)p", "MP4, up to \(videoHeight)p")
        case .audio:
            guard let audioChannels else { return nil }
            let kbps = audioBitratePerChannel * audioChannels / 1000
            return ("\(kbps) kbps", "AAC, \(kbps) kbps")
        default:
            return nil
        }
    }

    /// Common AAC bitrates, highest first, to step down through when the encoder rejects the one asked for.
    static let aacBitrates = [256_000, 192_000, 160_000, 128_000, 96_000, 80_000, 64_000, 48_000, 32_000, 24_000, 16_000]

    /// Compressed audio keeps mono as mono and mixes anything wider down to stereo.
    static func channels(of file: URL) -> Int {
        min(Int((try? AVAudioFile(forReading: file).fileFormat.channelCount) ?? 2), 2)
    }

    /// Compressed images stay PNG when any of them shows through, which JPEG would fill with white. A copy at most
    /// 256 px across is enough to tell: shrinking blends a see-through pixel into its neighbours rather than losing it.
    static func isTransparent(_ file: URL) -> Bool {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256]
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            properties[kCGImagePropertyHasAlpha] as? Bool == true,
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return false }
        guard
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return false }
        let bytes = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        return stride(from: 3, to: image.width * image.height * 4, by: 4).contains { bytes[$0] < 255 }
    }
}

/// Compress made nothing smaller, so it saved nothing.
public struct AlreadySmall: LocalizedError {
    public let errorDescription: String?

    init(level: CompressionLevel, files: Int) {
        errorDescription = "\(level.title) wouldn’t make \(files == 1 ? "it" : "them") any smaller, so nothing was saved."
    }
}
