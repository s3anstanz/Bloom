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
        // The first flower after launch once switched tabs without showing it, until the next drag. The drop lands by
        // where petals sit either way, so the check is what the screen shows.
        Journey(name: "switch-on-first-drag", title: "Switch to Tools with the tabs on the first drag after Bloom opens") { session in
            let photo = try session.image("photo.jpg")
            try await session.relaunchBloom()
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.tap(.shift)
            try await session.point(atTab: .tools)
            try await session.point(at: Tool.halfSize.title, in: .tools, files: [photo])
            try await session.expectTab(.tools)
            try await session.drop()
            let half = try await session.expectFile("photo (50%).jpg")
            try session.expectImage(half, type: .jpeg, width: 600, height: 400)
        },
        // Someone new who pauses mid-drag sees the keys, and once a key opens a flower the hint is gone for good.
        Journey(name: "key-hint", title: "A paused first drag shows the keys, until a flower has opened") { session in
            let photo = try session.image("photo.jpg")
            try await session.relaunchBloom(forgetting: [KeyHint.retiredKey])
            try await session.openInFinder()
            try await session.pickUp("photo.jpg")
            try await session.expectKeyHint()
            // Letting go without a key hides it, but the next paused drag still shows it.
            try await session.cancelDrag()
            try await session.expectNoKeyHint(for: 0.5)
            try await session.pickUp("photo.jpg")
            try await session.expectKeyHint()
            try await session.tap(.shift)
            try await session.point(at: Format.png.title, in: .convert, files: [photo])
            try await session.expectNoKeyHint(for: 0.5)
            try await session.cancelDrag()
            try await session.expectFlowerClosed(timeout: FlowerMotion.closeDuration + 4)
            try await session.pickUp("photo.jpg")
            try await session.expectNoKeyHint(for: KeyHint.delay + 1.5)
            try await session.cancelDrag()
            try await session.expectOnly(["photo.jpg"], after: 1)
        },
        // Someone new finds Bloom under its icon, and Show Me opens the guide, which follows the pointer while Finder
        // is in front. Once answered, the card never shows again.
        Journey(name: "first-launch-show-me", title: "The first-launch card's Show Me opens the field guide, once") { session in
            try await session.relaunchBloom(forgetting: [FirstLaunchCard.answeredKey])
            try await session.openInFinder()
            try await session.expectHelp("bloom.firstLaunchCard", "first-launch card")
            try await session.click(help: "bloom.showMe")
            try await session.expectHelp("bloom.fieldGuide", "field guide")
            try await session.expectNoHelp("bloom.firstLaunchCard", for: 0.5)
            try await session.click(help: "bloom.chip.\(FieldGuide.Kind.pdf.title)")
            try await session.click(help: "bloom.tab.Tools")
            let items = FieldGuide.items(for: .pdf, mode: .tools)
            try await session.point(atGuidePetal: Tool.splitPages.title, of: items)
            guard let split = items.first(where: { $0.title == Tool.splitPages.title }) else { throw Failure("A PDF has no Split petal.") }
            try await session.expectGuideCaption(FieldGuide.caption(for: split))
            try await session.click(help: "bloom.closeGuide")
            try await session.expectNoHelp("bloom.fieldGuide", for: 1)
            try await session.relaunchBloom()
            try await session.expectNoHelp("bloom.firstLaunchCard", for: 5)
        },
        Journey(name: "first-launch-not-now", title: "The first-launch card's Not Now closes it for good") { session in
            try await session.relaunchBloom(forgetting: [FirstLaunchCard.answeredKey])
            try await session.openInFinder()
            try await session.expectHelp("bloom.firstLaunchCard", "first-launch card")
            try await session.click(help: "bloom.notNow")
            try await session.expectNoHelp("bloom.firstLaunchCard", for: 1)
            try await session.expectNoHelp("bloom.fieldGuide", for: 0.5)
            try await session.relaunchBloom()
            try await session.expectNoHelp("bloom.firstLaunchCard", for: 5)
        },
        Journey(name: "menu-opens-guide", title: "What Can Bloom Do? opens the field guide, which stays open through a drop") { session in
            let photo = try session.image("photo.jpg")
            try await session.openInFinder()
            try await session.choose(menuItem: "What Can Bloom Do?")
            try await session.expectHelp("bloom.fieldGuide", "field guide")
            try await session.pickUp("photo.jpg")
            try await session.tap(.shift)
            try await session.point(at: Format.png.title, in: .convert, files: [photo])
            try await session.drop()
            let png = try await session.expectFile("photo.png")
            try session.expectImage(png, type: .png, width: 1200, height: 800)
            try await session.expectFlowerClosed()
            try await session.expectHelp("bloom.fieldGuide", "still open")
            try await session.click(help: "bloom.closeGuide")
            try await session.expectNoHelp("bloom.fieldGuide", for: 1)
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
            let before = Session.screenWindows()
            try await session.drop()
            if caption == QuickAction.airDrop.detail {
                let owner = try await session.expectNewWindow(besides: before)
                session.note = "AirDrop opened its window, shown by \(owner)."
                try await session.type(key: 53)
            } else {
                guard let caption, !caption.isEmpty else { throw Failure("The AirDrop petal says nothing when pointed at.") }
                session.note = "AirDrop can’t work on this Mac, so its petal is dimmed and says “\(caption)”."
                try await session.expectFlowerClosed()
                try await session.expectOnly(["photo.jpg"], after: 1)
            }
        },
        Journey(name: "document-to-pdf", title: "⇧ A document becomes a PDF, printed by the helper inside Bloom.app") { session in
            let notes = try Fixtures.rtf(in: session.folder)
            let original = try Data(contentsOf: notes)
            try await session.openInFinder()
            try await session.pickUp("notes.rtf")
            try await session.tap(.shift)
            try await session.point(at: Format.pdf.title, in: .convert, files: [notes])
            try await session.drop()
            let pdf = try await session.expectFile("notes.pdf")
            if let problem = await defect(in: pdf) { throw Failure(problem) }
            try session.expectUnchanged(notes, from: original)
        },
        Journey(name: "two-files", title: "⌘ Merge PDF from a PDF and a photo dragged together") { session in
            let pdf = try Fixtures.pdf(in: session.folder, pages: 2)
            let photo = try session.image("photo.jpg")
            try await session.openInFinder()
            try await session.pickUp("document.pdf", "photo.jpg")
            try await session.tap(.command)
            try await session.point(at: Tool.mergePDF.title, in: .tools, files: [pdf, photo])
            try await session.drop()
            let merged = try await session.expectFile("Merged.pdf")
            let pages = CGPDFDocument(merged as CFURL)?.numberOfPages ?? 0
            guard pages == 3 else { throw Failure("Merged.pdf has \(pages) pages instead of the PDF's 2 and the photo's 1.") }
        },
        Journey(name: "back-to-back", title: "Ten drags in a row, each as the last flower closes, open the flower first time") { session in
            // Drags that start right after a save are where Bloom has missed drags, so none is tapped or dragged again.
            session.retriesMissedFlower = false
            let photo = try session.image("photo.jpg")
            try await session.openInFinder()
            for round in 1...10 {
                try await session.pickUp("photo.jpg")
                try await session.tap(.shift)
                try await session.point(at: Format.png.title, in: .convert, files: [photo])
                try await session.drop()
                _ = try await session.expectFile(round == 1 ? "photo.png" : "photo \(round).png")
                try await session.expectFlowerClosed()
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
