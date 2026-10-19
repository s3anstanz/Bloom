import AppKit
import BloomCore

@MainActor
enum QuickActions {
    static let airDropMissing = "AirDrop isn’t available on this Mac"

    /// Why `action` can't work on this Mac right now, or nil when it can. The flower dims its petal and shows this.
    static func unavailability(of action: QuickAction, for files: [URL]) -> String? {
        switch action {
        // Only a Mac without AirDrop dims it. macOS refuses files in folders like the Desktop until the person allows
        // Bloom in, and only a drop can ask them, so `run` handles those.
        case .airDrop: return airDropService == nil ? airDropMissing : nil
        case .terminal: return terminal == nil ? "Terminal isn’t installed" : nil
        case .float, .copy, .move, .copyPath: return nil
        }
    }

    /// Returns the status line to show, or nil when the person cancelled.
    static func run(_ action: QuickAction, on files: [URL]) async throws -> String? {
        switch action {
        case .airDrop:
            guard let service = airDropService else { throw ConversionError("\(airDropMissing).") }
            // AirDrop takes only files Bloom may read on its own, and it says yes if any one file passes, so check each.
            let refused = files.filter { !service.canPerform(withItems: [$0]) }
            if !refused.isEmpty {
                // A drag doesn't count for folders like the Desktop. Reading the folder makes macOS ask the person, once.
                let refusal = await FolderAccess.resolve(refused, canShare: { service.canPerform(withItems: [$0]) })
                guard refusal.inDeniedFolders.isEmpty else {
                    throw ConversionError(FolderAccess.deniedMessage(for: refusal.inDeniedFolders))
                }
                // Readable and still refused isn't a folder problem; AirDrop itself is off or unavailable.
                guard refusal.otherwise.isEmpty else {
                    dragLog.notice("AirDrop: macOS can't send \(refusal.otherwise.count, privacy: .public) readable files")
                    throw ConversionError("\(airDropMissing).")
                }
            }
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: files)
            return "AirDrop opened"
        case .float:
            FloatShelf.shared.show(files, near: NSEvent.mouseLocation)
            return files.count == 1 ? "Floating. Drag it anywhere" : "Floating \(files.count) files"
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(files.map { $0 as NSURL })
            return "Copied. Paste with ⌘V"
        case .move:
            return try move(files)
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(files.map(\.path).joined(separator: "\n"), forType: .string)
            return files.count == 1 ? "Path copied" : "\(files.count) paths copied"
        case .terminal:
            guard let terminal else { throw ConversionError("Terminal isn’t installed.") }
            let isFolder = (try? files[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let folder = isFolder ? files[0] : files[0].deletingLastPathComponent()
            NSWorkspace.shared.open(
                [folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return "Opened in Terminal"
        }
    }

    private static var terminal: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
    }

    private static var airDropService: NSSharingService? {
        let service = NSSharingService(named: .sendViaAirDrop)
        if service == nil { dragLog.notice("AirDrop: macOS has no AirDrop service for Bloom") }
        return service
    }

    private static func move(_ files: [URL]) throws -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        panel.message = "Move \(files.count == 1 ? files[0].lastPathComponent : "\(files.count) files") to…"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return nil }
        for file in files {
            let ext = file.pathExtension
            let target = Engine.uniqueURL(in: folder, base: file.deletingPathExtension().lastPathComponent, ext: ext.isEmpty ? nil : ext)
            try FileManager.default.moveItem(at: file, to: target)
        }
        return "Moved to \(folder.lastPathComponent)"
    }
}
