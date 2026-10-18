import AppKit
import BloomCore
import SwiftUI

@main
struct BloomApp: App {
    var body: some Scene {
        MenuBarExtra("Bloom", systemImage: "camera.macro") {
            Text("Bloom \(BloomCore.version)")
            Divider()
            Button("Quit Bloom") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
