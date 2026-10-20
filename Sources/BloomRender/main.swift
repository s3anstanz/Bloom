import AppKit
import BloomCore

// Usage: BloomRender <document> <output.pdf>. Bloom runs this so document printing never blocks its own main thread.
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: BloomRender <document> <output.pdf>\n".utf8))
    exit(2)
}

do {
    try await MainActor.run {
        _ = NSApplication.shared
        try DocumentRenderer.renderPDF(from: URL(fileURLWithPath: arguments[1]), to: URL(fileURLWithPath: arguments[2]))
    }
} catch {
    FileHandle.standardError.write(Data(error.localizedDescription.utf8))
    exit(1)
}
