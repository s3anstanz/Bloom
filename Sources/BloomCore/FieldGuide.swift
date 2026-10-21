import Foundation

/// "What Can Bloom Do?": a panel under the menu bar icon that shows the real flower for each kind of file, to browse
/// before trying it on a file. Its petals come from `WheelCatalog`, so a new petal shows up in the guide on its own.
public enum FieldGuide {
    /// The chips along the top of the guide, one kind of file each.
    public enum Kind: CaseIterable {
        case photo, video, pdf, song, document, other

        public var title: String {
            switch self {
            case .photo: return "Photo"
            case .video: return "Video"
            case .pdf: return "PDF"
            case .song: return "Song"
            case .document: return "Document"
            case .other: return "Other"
            }
        }

        /// The file the guide pictures for this kind. It never exists: the guide reads only its name.
        public var sample: URL {
            let name: String
            switch self {
            case .photo: name = "photo.jpg"
            case .video: name = "clip.mov"
            case .pdf: name = "report.pdf"
            case .song: name = "song.m4a"
            case .document: name = "notes.docx"
            case .other: name = "Anything else"
            }
            return URL(fileURLWithPath: "/Bloom Field Guide").appendingPathComponent(name)
        }

        /// What the flower would read from a typical file of this kind: a photo with nothing see-through, a video with
        /// sound, a song in stereo.
        var facts: WheelCatalog.Facts {
            switch self {
            case .photo: return WheelCatalog.Facts(transparent: false)
            case .song: return WheelCatalog.Facts(audioChannels: 2)
            case .video, .pdf, .document, .other: return WheelCatalog.Facts()
            }
        }
    }

    /// The petals the flower for `mode` offers a typical file of `kind`.
    public static func items(for kind: Kind, mode: Mode) -> [WheelItem] {
        WheelCatalog.items(for: [kind.sample], mode: mode, facts: kind.facts)
    }

    /// What the guide says about a petal: why it can't work here, or its name and what it does, and for a petal with
    /// sizes, how to pick another while dragging.
    public static func caption(for item: WheelItem) -> String {
        if let unavailable = item.unavailable { return unavailable }
        let others = item.choices.filter { $0.detail != item.detail }
        let badges = others.compactMap(\.badge)
        guard !others.isEmpty, badges.count == others.count else { return "\(item.title): \(item.detail)" }
        return "\(item.title): \(item.detail). Rest on it for \(sizes(badges))."
    }

    /// "1600 or 3200 px" when the sizes share a unit, otherwise "540p or 1080p".
    private static func sizes(_ badges: [String]) -> String {
        let parts = badges.map { $0.split(separator: " ") }
        if parts.allSatisfy({ $0.count == 2 }), Set(parts.map { $0[1] }).count == 1 {
            return parts.map { String($0[0]) }.joined(separator: " or ") + " \(parts[0][1])"
        }
        return badges.joined(separator: " or ")
    }

    /// Where a panel of `size` goes under the menu bar icon at `icon`, in AppKit screen coordinates (y up): with the
    /// icon above its right side and its top all but touching the menu bar, so it reads as coming from the icon, kept on
    /// the screen. Without the icon, it goes top right, a little further down.
    public static func origin(under icon: CGRect?, size: CGSize, in screen: CGRect) -> CGPoint {
        let margin: CGFloat = 8
        let gap: CGFloat = icon == nil ? margin : 2
        let maxX = screen.maxX - margin - size.width
        let x = icon.map { $0.midX - size.width * 0.85 } ?? maxX
        return CGPoint(x: max(screen.minX + margin, min(x, maxX)), y: screen.maxY - gap - size.height)
    }
}

/// The card under the menu bar icon on Bloom's first launch, offering the field guide. It shows until it's answered,
/// then never again.
public struct FirstLaunchCard {
    /// The setting that records the card was answered.
    public static let answeredKey = "firstLaunchCardAnswered"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isDue: Bool {
        !defaults.bool(forKey: Self.answeredKey)
    }

    /// Show Me or Not Now: either way, the card is done.
    public func answered() {
        defaults.set(true, forKey: Self.answeredKey)
    }
}
