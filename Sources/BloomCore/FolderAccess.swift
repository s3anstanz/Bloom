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

    /// The folder to list for `item`. Inside the Desktop, Documents or Downloads it's that folder itself: the drag
    /// already lets Bloom list a dropped subfolder, so only the protected folder brings up the prompt, and its parent,
    /// the home folder, never does. Elsewhere it's a dropped folder itself, or the folder a file is in.
    public static func requestTarget(for item: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let target: URL
        if let folder = protectedFolder(containing: item, home: home) {
            target = home.appendingPathComponent(folder.name)
        } else {
            let isFolder = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            target = isFolder ? item : item.deletingLastPathComponent()
        }
        // One spelling per folder, with or without a trailing slash, so equal folders compare equal.
        return URL(fileURLWithPath: target.path, isDirectory: true)
    }

    /// The files AirDrop still refuses after Bloom asked for their folders.
    public struct Refusal: Equatable {
        /// In folders the person said no to: Files & Folders can fix these.
        public let inDeniedFolders: [URL]
        /// Refused although Bloom may read their folder, for example because AirDrop itself is off.
        public let otherwise: [URL]

        public var isEmpty: Bool { inDeniedFolders.isEmpty && otherwise.isEmpty }
    }

    /// Asks for the folders of the files AirDrop refused and returns the files it still refuses.
    /// `canShare` is AirDrop's own check. macOS applies an Allow a moment after the prompt closes, so files in
    /// allowed folders are checked up to `attempts` times, `pause` nanoseconds apart; files in denied folders aren't waited on.
    @MainActor
    public static func resolve(
        _ refused: [URL],
        canShare: (URL) -> Bool,
        request: (URL) async -> Bool = { await FolderAccess.request($0) },
        attempts: Int = 20,
        pause: UInt64 = 100_000_000,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async -> Refusal {
        let target = { (item: URL) in requestTarget(for: item, home: home) }
        var targets: [URL] = []
        for folder in refused.map(target) where !targets.contains(folder) {
            targets.append(folder)
        }
        var denied: Set<URL> = []
        for folder in targets {
            if await !request(folder) { denied.insert(folder) }
        }
        var remaining = refused
        for attempt in 1...max(attempts, 1) {
            remaining = remaining.filter { !canShare($0) }
            let waiting = remaining.contains { !denied.contains(target($0)) }
            guard waiting, attempt < attempts else { break }
            try? await Task.sleep(nanoseconds: pause)
        }
        let isDenied = { (file: URL) in denied.contains(target(file)) }
        return Refusal(inDeniedFolders: remaining.filter(isDenied), otherwise: remaining.filter { !isDenied($0) })
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
