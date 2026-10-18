# Bloom

Drag a file, tap a key, and a flower blooms around your cursor. Each petal is something you can do with the file: convert it, shrink it, rotate it, AirDrop it. Release on a petal and the result lands next to the original. Everything runs on your Mac; Bloom never touches the network.

| Tap while dragging | Flower |
|---|---|
| **⇧ Shift** | Convert: only the formats this file can become |
| **⌘ Command** | Tools: compress, resize, rotate, remove background and more |
| **⌃ Control** | Actions: AirDrop, Float, Copy, Move, Copy Path, Terminal |

> This repository is being set up. The app's features arrive in the next pull request; until then the build is a placeholder menu-bar app.

## Install

Requires macOS 13 or later and Apple's Command Line Tools (the installer offers them if they're missing).

```bash
git clone https://github.com/s3anstanz/Bloom.git ~/Bloom
~/Bloom/scripts/install.sh
```

Bloom runs from the menu bar (flower icon). To get the latest version:

```bash
~/Bloom/scripts/update.sh
```

## Develop

| Task | Command |
|---|---|
| Build, package and relaunch | `scripts/install.sh` |
| Run the tests | `swift test` |
| Format the code | `scripts/format.sh` |
| Check BloomCore stays offline | `scripts/check-no-network.sh` |

- `Sources/BloomCore`: everything about files: which petals a file gets, and every conversion, tool and action. Fully unit-tested.
- `Sources/Bloom`: the menu-bar app, drag detection and the flower.
- `Tests/BloomCoreTests`: the test suite.

Every pull request is built and tested on a Mac by GitHub Actions, and the finished `Bloom.app` is attached to the run. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Privacy and security

Bloom reads the files you drop on it and writes results beside them. It has no network code, no analytics and no third-party dependencies, and CI fails if networking code appears in BloomCore. To report a security problem, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © 2026 Westfall Labs LLC
