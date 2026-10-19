import AppKit
import BloomCore
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
            try await session.point(at: "PNG", in: .convert, files: [photo])
            try await session.drop()
            let png = try await session.expectFile("photo.png")
            try session.expectImage(png, type: .png, width: 640, height: 480)
            try session.expectUnchanged(photo, from: original)
        },
        Journey(name: "tools-holding-command", title: "⌘ Half Size, holding ⌘ through the drop") { session in
            let photo = try session.image("photo.jpg")
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.hold(.command)
            try await session.point(at: "Half Size", in: .tools, files: [photo])
            try await session.drop()
            try await session.release(.command)
            let half = try await session.expectFile("photo (50%).jpg")
            try session.expectImage(half, type: .jpeg, width: 320, height: 240)
        },
        Journey(name: "compress-size", title: "⌘ Compress a photo to the Smaller size") { session in
            let photo = try session.photo("photo.jpg", width: 3200, height: 2000)
            let original = try Data(contentsOf: photo)
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.command)
            try await session.point(at: "Compress", in: .tools, files: [photo])
            try await session.point(atChoice: "Smaller", of: "Compress", in: .tools, files: [photo])
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
            try await session.point(at: "Compress", in: .tools, files: [photo])
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
            try await session.point(at: "Half Size", in: .tools, files: [photo])
            try await session.drop()
            let half = try await session.expectFile("photo (50%).jpg")
            try session.expectImage(half, type: .jpeg, width: 320, height: 240)
        },
        // The first flower after launch once switched tabs without showing it, until the next drag. The drop lands by
        // where petals sit either way, so the check is what the screen shows.
        Journey(name: "switch-on-first-drag", title: "Switch to Tools with the tabs on the first drag after Bloom opens") { session in
            let photo = try session.image("photo.jpg")
            try await session.relaunchBloom()
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.shift)
            try await session.point(atTab: .tools)
            try await session.point(at: "Half Size", in: .tools, files: [photo])
            try await session.expectTab(.tools)
            try await session.drop()
            let half = try await session.expectFile("photo (50%).jpg")
            try session.expectImage(half, type: .jpeg, width: 320, height: 240)
        },
        Journey(name: "copy-path-holding-control", title: "⌃ Copy Path, holding ⌃ through the drop") { session in
            let photo = try session.image("photo.jpg")
            NSPasteboard.general.clearContents()
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.hold(.control)
            try await session.point(at: "Copy Path", in: .actions, files: [photo])
            try await session.drop()
            try await session.release(.control)
            try await session.expectPathOnPasteboard(photo)
        },
        Journey(name: "taken-name", title: "A name that's taken gets a number") { session in
            let photo = try session.image("photo.jpg")
            let taken = try session.image("photo.png", type: .png)
            let original = try Data(contentsOf: taken)
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.shift)
            try await session.point(at: "PNG", in: .convert, files: [photo])
            try await session.drop()
            let png = try await session.expectFile("photo 2.png")
            try session.expectImage(png, type: .png, width: 640, height: 480)
            try session.expectUnchanged(taken, from: original)
        },
        Journey(name: "failed-conversion", title: "A failed conversion leaves nothing behind") { session in
            let broken = try session.file("broken.jpg", contents: "This is not a photo.")
            try await session.openInFinder()
            try await session.pickUp("broken.jpg")
            try await session.tap(.shift)
            try await session.point(at: "PNG", in: .convert, files: [broken])
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
            try await session.point(at: "PNG", in: .convert, files: [photo])
            try await session.drop()
            let png = try await session.expectFile("photo.png")
            try session.expectImage(png, type: .png, width: 640, height: 480)
        },
    ]
}
