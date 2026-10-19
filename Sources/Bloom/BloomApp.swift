import AppKit
import BloomCore
import ServiceManagement
import SwiftUI

@main
struct BloomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Bloom", systemImage: "camera.macro") {
            StatusMenu()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var watcher: DragWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--preview"), arguments.indices.contains(flag + 1) {
            let folder = URL(fileURLWithPath: arguments[flag + 1])
            Task { await FlowerPreview.run(into: folder) }
            return
        }
        let watcher = DragWatcher(radial: RadialController())
        watcher.start()
        self.watcher = watcher
    }
}

private struct StatusMenu: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(CompressionSetting.key) private var compressionLevel = 50

    var body: some View {
        Text("While dragging a file, tap:")
        Text("⇧  Convert")
        Text("⌘  Tools")
        Text("⌃  Actions")
        Divider()
        Picker("Compress To", selection: $compressionLevel) {
            ForEach(CompressionSetting.choices, id: \.self) { level in
                Text("\(level)%").tag(level)
            }
        }
        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        Divider()
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            Text("Bloom \(version)")
        }
        Button("Quit Bloom") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
