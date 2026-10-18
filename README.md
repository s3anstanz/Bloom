# Bloom

Drag a file, tap a key, and a flower blooms around your cursor. Each petal is something you can do with the file. Release on a petal and the result lands next to the original. Everything runs on your Mac; Bloom never touches the network.

| Tap while dragging | Petals | Flower |
|---|---|---|
| **⇧ Shift** | Pink | **Convert:** only the formats this file can become |
| **⌘ Command** | Violet | **Tools:** compress, resize, rotate, remove background and more |
| **⌃ Control** | Blue | **Actions:** AirDrop, Float, Copy, Move, Copy Path, Terminal |

## Install

Requires macOS 13 or later and Apple's Command Line Tools (the installer offers them if they're missing).

```bash
git clone https://github.com/s3anstanz/Bloom.git ~/Bloom
~/Bloom/scripts/install.sh
```

Bloom runs from the menu bar (flower icon). From that menu you can set **Compress To** (75%, 50% or 25%) and turn on **Launch at Login**. To get the latest version:

```bash
~/Bloom/scripts/update.sh
```

## Use

1. Start dragging one or more files in Finder or on the Desktop.
2. Tap **⇧**, **⌘** or **⌃**. The petals unfold from the center; you can let go of the key and the flower stays until you drop. Tap another key to switch flowers.
3. Move toward a petal until it lifts and lights up, then let go. The center shows ✓ and you hear a pop.
4. To cancel, let go in the center. Moving off the flower and letting go is a normal drop.

Originals are never modified. Results get Finder-style names: `photo.jpg`, then `photo 2.jpg`, and so on.

### ⇧ Convert

| Dragged file | Converts to |
|---|---|
| Images (JPG, PNG, HEIC, WebP, AVIF, TIFF, GIF, BMP, …) | JPG, PNG, HEIC, TIFF, GIF, BMP, JP2, PDF, plus WebP and AVIF where macOS can write them |
| PDF | PNG, JPG (one image per page), TXT |
| Video (MOV, MP4, M4V) | MP4, MOV, M4V, GIF (first 60 s), M4A (the soundtrack, for videos that have one) |
| Audio (MP3, M4A, WAV, AIFF, FLAC, …) | M4A, WAV, AIFF |
| Documents (DOCX, DOC, RTF, ODT, HTML, TXT, MD) | PDF, DOCX, RTF, TXT, HTML, ODT |
| Subtitles (SRT, VTT) | SRT, VTT |

When several files are dragged together, the flower offers the conversions they all support.

### ⌘ Tools

| Tool | Works on |
|---|---|
| Compress (uses the Compress To setting) | Images → JPG, video → MP4, audio → AAC; PDFs use macOS's Reduce File Size filter |
| Half Size, Flip, Grayscale, No Meta (removes location and camera data) | Images |
| Rotate | Images and PDFs |
| Remove BG | Images, on macOS 14 or later |
| Mute | Video |
| Split | PDFs (one PDF per page) |
| Merge PDF | Two or more PDFs and/or images |
| Extract | ZIP, TAR, TGZ and other archives |
| Zip | Anything, including folders |

### ⌃ Actions

| Action | What it does |
|---|---|
| **AirDrop** | Opens the AirDrop sheet |
| **Float** | Keeps the file in a small card on screen. Drag its icon anywhere later, double-click to open, drag the card's edge to move it, ✕ to close |
| **Copy** | Puts the file on the clipboard, ready to paste with ⌘V |
| **Move** | Asks for a folder and moves the file there |
| **Copy Path** | Copies the full path |
| **Terminal** | Opens the file's folder in Terminal |

## Permissions

- macOS may ask once per folder (such as Desktop or Documents) to let Bloom save files there.
- Bloom watches mouse drags and modifier keys only; it needs no Accessibility or Input Monitoring access.

## Develop

| Task | Command |
|---|---|
| Build, package and relaunch | `scripts/install.sh` |
| Run the tests | `swift test` |
| Format the code | `scripts/format.sh` |
| Check BloomCore stays offline | `scripts/check-no-network.sh` |

- `Sources/BloomCore`: everything about files: which petals a file gets, every conversion and tool, key taps and petal hit-testing.
- `Sources/Bloom`: the menu-bar app, drag detection, the flower, Float cards and the Actions petals.
- `Sources/BloomRender`: a helper bundled inside Bloom.app that renders documents to PDF, keeping the app responsive during long documents.
- `Tests/BloomCoreTests`: runs every petal on generated sample files and checks each result opens, plus catalog, naming, subtitle, key-tap and petal-geometry tests.

Every pull request is built and tested on a Mac by GitHub Actions, and the finished `Bloom.app` is attached to the run. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Privacy and security

Bloom reads the files you drop on it and writes results beside them. It has no network code, no analytics and no third-party dependencies, and CI fails if networking code appears in BloomCore. To report a security problem, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © 2026 Westfall Labs LLC
