import Foundation

/// The user folders macOS asks about before an app may read them on its own, which AirDrop needs.
/// A drag lets Bloom read the dropped file, but AirDrop only takes files Bloom could read without one.
public enum FolderAccess {
    public enum Folder: CaseIterable {
        case desktop, documents, downloads

        public var name: String {
            switch self {
            case .desktop: return "Desktop"
            case .documents: return "Documents"
            case .downloads: return "Downloads"
            }
        }
    }

    /// The protected folder `file` is inside, at any depth, or nil.
    public static func protectedFolder(
        containing file: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Folder? {
        let path = file.standardizedFileURL.pathComponents
        let homePath = home.standardizedFileURL.pathComponents
        return Folder.allCases.first { folder in
            // Whole components only, so "Desktop2" isn't the Desktop.
            let prefix = homePath + [folder.name]
            return path.count >= prefix.count && Array(path.prefix(prefix.count)) == prefix
        }
    }

    /// Lists `folder`, which makes macOS ask the person the first time, and returns whether Bloom may read it now.
    /// Listing waits for the person's answer, so this never runs on the main actor.
    public static func request(_ folder: URL) async -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
    }

    /// What to tell the person when macOS still refuses `files` after asking. Each fits the flower's two-line caption.
    public static func deniedMessage(
        for files: [URL], home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let found = files.map { protectedFolder(containing: $0, home: home) }
        let settings = "Privacy & Security → Files & Folders."
        guard !found.contains(where: { $0 == nil }) else {
            return "macOS won’t let Bloom AirDrop this. Check \(settings)"
        }
        let names = Folder.allCases.filter { found.contains($0) }.map(\.name)
        switch names.count {
        case 1: return "Allow Bloom to use your \(names[0]) folder in \(settings)"
        case 2: return "Allow Bloom to use your \(names[0]) and \(names[1]) folders in \(settings)"
        default: return "Allow Bloom to use \(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1]) in \(settings)"
        }
    }
}
