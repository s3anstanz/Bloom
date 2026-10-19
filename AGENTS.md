# Bloom

macOS menu-bar utility: drag a file, tap ⇧ / ⌘ / ⌃, release on a petal. Local-only, no third-party dependencies, MIT (Westfall Labs LLC).

These instructions apply to every agent working in this repository, including Claude Code (through `CLAUDE.md`) and Codex.

## Commands

- Build, package and relaunch: `scripts/install.sh`
- Test: `swift test`
- Format: `scripts/format.sh` (CI fails on any formatting difference)
- Offline guard: `scripts/check-no-network.sh`
- Package only: `scripts/bundle.sh release build/Bloom.app`
- Flower preview: `swift run Bloom --preview build/preview` writes a GIF and a strip of stills for each moment of the flower. Add the `preview` label to a pull request that changes how the flower looks or moves: the Preview workflow renders them on a Mac runner, posts them as a comment and refreshes it on every push. Read the stills there to check the change.
- End-to-end: `scripts/e2e.sh` plays the journeys in `Sources/BloomE2E` on the real app. Each drags a file out of Finder with real mouse and key events, opens a flower, drops and checks what Bloom saves. The E2E workflow plays them on every pull request and on `main` and shows each step's screenshot in the run's summary; read those to check how a change behaves.

## Layout

- `Sources/BloomCore`: file logic (petal catalog, conversions, tools, actions, naming). Public API for the app; covered by tests.
- `Sources/Bloom`: menu bar, drag detection, flower UI. Keep logic out of here; move anything testable into BloomCore.
- `Sources/BloomRender`: helper executable bundled in Bloom.app that prints documents to PDF, so AppKit text printing never runs on the app's main thread.
- `Sources/BloomE2E`: end-to-end journeys for `scripts/e2e.sh`, driving Finder and Bloom the way a person does.
- `Tests/BloomCoreTests`: XCTest. Generate fixtures in the test; don't commit binary samples.
- `Support/Info.plist`: bundle metadata (identifier `com.westfalllabs.bloom`).

## Rules

- Every change lands through a pull request; the maintainer merges. CI (format, offline guard, warnings-as-errors build, tests, CodeQL for workflow files) must pass. CodeQL for Swift runs on `main` after each merge and weekly; fix its findings in a follow-up pull request.
- BloomCore never touches the network. Add no Swift packages.
- New BloomCore behavior ships with tests that would fail if it broke. Assert results (files exist, open as their type, have the expected size or content), not implementation details.
- A new way to drag, open, switch flowers or drop gets a journey in `Sources/BloomE2E` that fails if it breaks.
- Minimum macOS 13. Gate newer APIs with `#available` and hide the petal when unavailable.
- Never modify the original file; write results beside it with Finder-style unique names.
- Keep the README's petal tables in sync with what the code offers.

## Review guidelines

Flag as **P0**:

- Writing to, moving, renaming or deleting the user's original file, except through the Move action the user chose.
- Overwriting any existing file instead of picking a unique name.
- Network access, telemetry, analytics or a third-party package anywhere in the app.
- A failed conversion that leaves a partial or corrupt output behind, or reports success.
- External tools run in a way that lets a file name become part of a command, rather than as separate arguments to `Process`.

Flag as **P1**:

- New BloomCore behavior without a test that would fail if it broke.
- A petal offered where it can't work: the wrong file type, or an API newer than macOS 13 without an `#available` check.
- An output that may not open as the type its extension claims.
- UI state changed off the main actor, or a conversion that blocks the main thread.
- The README's petal tables out of sync with what the code offers.

Formatting is enforced by CI; don't flag formatting or naming preferences.
