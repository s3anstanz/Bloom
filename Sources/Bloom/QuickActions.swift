import AppKit
import BloomCore

@MainActor
enum QuickActions {
    /// Returns the status line to show, or nil when the person cancelled.
    static func run(_ action: QuickAction, on files: [URL]) async throws -> String? {
        switch action {
        case .airDrop:
            guard let service = NSSharingService(named: .sendViaAirDrop) else {
                throw ConversionError("AirDrop isn’t available on this Mac.")
            }
            // AirDrop takes only files Bloom may read on its own, and it says yes if any one file passes, so check each.
            let refused = files.filter { !service.canPerform(withItems: [$0]) }
            if !refused.isEmpty {
                // A drag doesn't count for folders like the Desktop. Reading the folder makes macOS ask the person, once.
                let stillRefused = await FolderAccess.resolve(refused, canShare: { service.canPerform(withItems: [$0]) })
                guard stillRefused.isEmpty else { throw ConversionError(FolderAccess.deniedMessage(for: stillRefused)) }
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
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
                throw ConversionError("Terminal isn’t installed.")
            }
            let isFolder = (try? files[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let folder = isFolder ? files[0] : files[0].deletingLastPathComponent()
            NSWorkspace.shared.open(
                [folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return "Opened in Terminal"
        }
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
