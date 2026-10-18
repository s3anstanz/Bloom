# Bloom

macOS menu-bar utility: drag a file, tap ⇧ / ⌘ / ⌃, release on a petal. Local-only, no third-party dependencies, MIT (Westfall Labs LLC).

## Commands

- Build, package and relaunch: `scripts/install.sh`
- Test: `swift test`
- Format: `scripts/format.sh` (CI fails on any formatting difference)
- Offline guard: `scripts/check-no-network.sh`
- Package only: `scripts/bundle.sh release build/Bloom.app`

## Layout

- `Sources/BloomCore`: file logic (petal catalog, conversions, tools, actions, naming). Public API for the app; covered by tests.
- `Sources/Bloom`: menu bar, drag detection, flower UI. Keep logic out of here; move anything testable into BloomCore.
- `Tests/BloomCoreTests`: XCTest. Generate fixtures in the test; don't commit binary samples.
- `Support/Info.plist`: bundle metadata (identifier `com.westfalllabs.bloom`).

## Rules

- Every change lands through a pull request; the maintainer merges. CI (format, offline guard, warnings-as-errors build, tests, CodeQL) must pass.
- BloomCore never touches the network. Add no Swift packages.
- New BloomCore behavior ships with tests that would fail if it broke. Assert results (files exist, open as their type, have the expected size or content), not implementation details.
- Minimum macOS 13. Gate newer APIs with `#available` and hide the petal when unavailable.
- Never modify the original file; write results beside it with Finder-style unique names.
- UI changes include a screenshot or recording in the PR description.
- Keep the README's petal tables in sync with what the code offers.
