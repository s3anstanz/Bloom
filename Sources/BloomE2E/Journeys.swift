import AppKit
import BloomCore
import BloomFixtures
import UniformTypeIdentifiers

@MainActor
enum Journeys {
    static let all: [Journey] = [
        Journey(name: "convert", title: "⇧ Convert a photo to PNG") { session in
            let photo = try session.image("photo.jpg")
            let original = try Data(contentsOf: photo)
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.shift)
            try await session.point(at: Format.png.title, in: .convert, files: [photo])
            try await session.drop()
            let png = try await session.expectFile("photo.png")
            try session.expectImage(png, type: .png, width: 1200, height: 800)
            try session.expectUnchanged(photo, from: original)
        },
        Journey(name: "tools-holding-command", title: "⌘ Half Size, holding ⌘ through the drop") { session in
            let photo = try session.image("photo.jpg")
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.hold(.command)
            try await session.point(at: Tool.halfSize.title, in: .tools, files: [photo])
            try await session.drop()
            try await session.release(.command)
            let half = try await session.expectFile("photo (50%).jpg")
            try session.expectImage(half, type: .jpeg, width: 600, height: 400)
        },
        Journey(name: "compress-size", title: "⌘ Compress a photo to the Smaller size") { session in
            let photo = try session.photo("photo.jpg", width: 3200, height: 2000)
            let original = try Data(contentsOf: photo)
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.command)
            try await session.point(at: Tool.compress.title, in: .tools, files: [photo])
            try await session.point(atChoice: CompressionLevel.smaller.title, of: Tool.compress.title, in: .tools, files: [photo])
            try await session.drop()
            let smaller = try await session.expectFile("photo (compressed).jpg")
            try session.expectImage(smaller, type: .jpeg, width: 1600, height: 1000)
            try session.expectUnchanged(photo, from: original)
        },
        Journey(name: "compress-balanced", title: "⌘ Compress dropped on the petal makes the Balanced size") { session in
            let photo = try session.photo("photo.jpg", width: 3200, height: 2000)
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.command)
            try await session.point(at: Tool.compress.title, in: .tools, files: [photo])
            try await session.drop()
            let balanced = try await session.expectFile("photo (compressed).jpg")
            try session.expectImage(balanced, type: .jpeg, width: 2400, height: 1500)
        },
        Journey(name: "switch-with-tabs", title: "Switch from Convert to Tools with the tabs") { session in
            let photo = try session.image("photo.jpg")
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.shift)
            try await session.point(atTab: .tools)
            try await session.point(at: Tool.halfSize.title, in: .tools, files: [photo])
            try await session.drop()
            let half = try await session.expectFile("photo (50%).jpg")
            try session.expectImage(half, type: .jpeg, width: 600, height: 400)
        },
        Journey(name: "copy-path-holding-control", title: "⌃ Copy Path, holding ⌃ through the drop") { session in
            let photo = try session.image("photo.jpg")
            NSPasteboard.general.clearContents()
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.hold(.control)
            try await session.point(at: QuickAction.copyPath.title, in: .actions, files: [photo])
            try await session.drop()
            try await session.release(.control)
            try await session.expectPathOnPasteboard(photo)
        },
        Journey(name: "copy", title: "⌃ Copy puts the file itself on the pasteboard") { session in
            let photo = try session.image("photo.jpg")
            NSPasteboard.general.clearContents()
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.control)
            try await session.point(at: QuickAction.copy.title, in: .actions, files: [photo])
            try await session.drop()
            try await session.expectFilesOnPasteboard([photo])
        },
        Journey(name: "move", title: "⌃ Move to a folder that already has that name") { session in
            let photo = try session.image("photo.jpg")
            let original = try Data(contentsOf: photo)
            let destination = try session.destination()
            let taken = destination.appendingPathComponent("photo.jpg")
            try Data("Already here.".utf8).write(to: taken)
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.control)
            try await session.point(at: QuickAction.move.title, in: .actions, files: [photo])
            try await session.drop()
            try await session.chooseInMovePanel(destination)
            let moved = try await session.expectFile("photo 2.jpg", in: destination)
            try session.expectUnchanged(moved, from: original)
            try session.expectUnchanged(taken, from: Data("Already here.".utf8))
            try await session.expectOnly([], after: 0)
        },
        Journey(name: "float", title: "⌃ Float keeps the file on screen to drag somewhere later") { session in
            let photo = try session.image("photo.jpg")
            let original = try Data(contentsOf: photo)
            let destination = try session.destination()
            try await session.openInFinder(alongside: destination)
            try await session.pickUp("photo.jpg")
            try await session.tap(.control)
            try await session.point(at: QuickAction.float.title, in: .actions, files: [photo])
            try await session.drop()
            let card = try await session.expectFloatCard()
            try await session.expectFlowerClosed()
            let target = try session.finderWindow(showing: destination)
            try await session.drag(from: CGPoint(x: card.midX, y: card.minY + 60), to: CGPoint(x: target.midX, y: target.midY + 20))
            let copy = try await session.expectFile("photo.jpg", in: destination)
            try session.expectUnchanged(copy, from: original)
            try session.expectUnchanged(photo, from: original)
            try await Session.waitUntil("Float's card to close", timeout: 3) { Session.floatCards().isEmpty }
        },
        Journey(name: "open-in-terminal", title: "⌃ Terminal opens the file's folder") { session in
            let photo = try session.image("photo.jpg")
            let wasRunning = Session.terminalIsRunning
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.control)
            try await session.point(at: QuickAction.terminal.title, in: .actions, files: [photo])
            try await session.drop()
            try await session.expectTerminal(at: session.folder, wasRunning: wasRunning)
        },
        Journey(name: "airdrop", title: "⌃ AirDrop opens AirDrop, or its petal is dimmed and says why") { session in
            let photo = try session.image("photo.jpg")
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.control)
            try await session.point(at: QuickAction.airDrop.title, in: .actions, files: [photo])
            let caption = Session.caption()
            try await session.drop()
            if caption == QuickAction.airDrop.detail {
                let said = try await session.result(after: QuickAction.airDrop.progress, detail: caption)
                guard said == "AirDrop opened" else { throw Failure("Bloom said “\(said ?? "nothing")” instead of opening AirDrop.") }
                try await Session.pause(1.5)
                try await session.screenshotOfScreen("AirDrop")
                try await session.type(key: 53)
            } else {
                guard let caption, !caption.isEmpty else { throw Failure("The AirDrop petal says nothing when pointed at.") }
                session.note = "AirDrop can’t work on this Mac, so its petal is dimmed and says “\(caption)”."
                try await session.expectFlowerClosed()
                try await session.expectOnly(["photo.jpg"], after: 1)
            }
        },
        Journey(name: "taken-name", title: "A name that's taken gets a number") { session in
            let photo = try session.image("photo.jpg")
            let taken = try session.image("photo.png", type: .png)
            let original = try Data(contentsOf: taken)
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.shift)
            try await session.point(at: Format.png.title, in: .convert, files: [photo])
            try await session.drop()
            let png = try await session.expectFile("photo 2.png")
            try session.expectImage(png, type: .png, width: 1200, height: 800)
            try session.expectUnchanged(taken, from: original)
        },
        Journey(name: "failed-conversion", title: "A failed conversion leaves nothing behind") { session in
            let broken = try session.file("broken.jpg", contents: "This is not a photo.")
            try await session.openInFinder()
            try await session.pickUp("broken.jpg")
            try await session.tap(.shift)
            try await session.point(at: Format.png.title, in: .convert, files: [broken])
            try await session.drop()
            try await Session.pause(1)
            try await session.screenshot("failed")
            try await session.expectOnly(["broken.jpg"], after: 3)
        },
        Journey(name: "let-go-in-the-center", title: "Letting go in the center saves nothing") { session in
            try session.image("photo.jpg")
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.shift)
            try await session.pointAtCenter()
            try await session.drop()
            try await session.expectFlowerClosed()
            try await session.expectOnly(["photo.jpg"], after: 2)
        },
        Journey(name: "drop-after-letting-go", title: "A drop right after letting go in the center still lands") { session in
            let photo = try session.image("photo.jpg")
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.shift)
            try await session.pointAtCenter()
            try await session.drop()
            try await session.expectFlowerClosed()
            try await session.expectOnly(["photo.jpg"], after: 2)
            try await session.pickUp("photo.jpg")
            try await session.tap(.shift)
            try await session.point(at: Format.png.title, in: .convert, files: [photo])
            try await session.drop()
            let png = try await session.expectFile("photo.png")
            try session.expectImage(png, type: .png, width: 1200, height: 800)
        },
    ]
}
