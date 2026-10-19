# Bloom

macOS menu-bar utility: drag a file, tap ⇧ / ⌘ / ⌃, release on a petal. Local-only, no third-party dependencies, MIT (Westfall Labs LLC).

These instructions apply to every agent working in this repository, including Claude Code (through `CLAUDE.md`) and Codex.

## Commands

- Build, package and relaunch: `scripts/install.sh`
- Check a change: `scripts/check.sh` runs what CI will run for the files it touches (`scripts/test-plan.sh`); `--e2e` also plays the end-to-end tests when they're needed.
- Test: `swift test`
- Format: `scripts/format.sh` (CI fails on any formatting difference)
- Offline guard: `scripts/check-no-network.sh`
- Package only: `scripts/bundle.sh release build/Bloom.app`
- Flower preview: `swift run Bloom --preview build/preview` writes a GIF and a strip of stills for each moment of the flower. On a pull request that changes how the flower looks or moves, the Preview workflow renders them on a Mac runner, posts them as a comment and refreshes it on every push; the `preview` label asks for it on any other pull request. Read the stills there to check the change.
- End-to-end: `scripts/e2e.sh` plays the journeys in `Sources/BloomE2E` on the real app. Each drags a file out of Finder with real mouse and key events, opens a flower, drops and checks what Bloom saves, or what an action does. `scripts/e2e.sh --matrix` also plays the petal matrix: a generated sample of every kind of file dropped on every petal Bloom offers for it, each result checked to open as its type, with a table of what worked, what can't work on that Mac and why, and what failed. The E2E workflow plays them when a change needs them (below) and shows the screenshots in the run's summary; read those to check how a change behaves.

## Which tests run

`scripts/test-plan.sh` picks the tests from the files a change touches, never from its title, and CI writes the plan at the top of each run's summary. Level 0 is the title check alone (documentation, issue forms); 1 adds the build and unit tests on macOS 15 and 26 (any code, tests or scripts); 2 adds the end-to-end journeys (drags, key taps, the flower, the Actions petals, the E2E suite); 3 adds the petal matrix (conversions, Compress, document rendering, the petal catalog, the sample files, the package, how tests run, and any file no rule names). The flower preview runs for changes to how the flower looks or moves. Pull requests play end-to-end tests on macOS 26; `main` plays on both, and Monday and hand-started runs play everything. The labels `run:journeys`, `run:matrix` and `preview` add a level. When you add a file, give it a rule in `scripts/test-plan.sh` if it needs less than the full run. Details: `CONTRIBUTING.md`.

## Layout

- `Sources/BloomCore`: file logic (petal catalog, conversions, tools, actions, naming). Public API for the app; covered by tests.
- `Sources/Bloom`: menu bar, drag detection, flower UI. Keep logic out of here; move anything testable into BloomCore.
- `Sources/BloomRender`: helper executable bundled in Bloom.app that prints documents to PDF, so AppKit text printing never runs on the app's main thread.
- `Sources/BloomE2E`: end-to-end journeys and the petal matrix for `scripts/e2e.sh`, driving Finder and Bloom the way a person does.
- `Sources/BloomFixtures`: sample files generated on the fly for the tests and the journeys, and `defect(in:)`, which says why a result doesn't open as its type.
- `Tests/BloomCoreTests`: XCTest. Generate fixtures with `BloomFixtures`; don't commit binary samples.
- `Support/Info.plist`: bundle metadata: identifier `com.westfalllabs.bloom` and the version the menu shows (releasing: `CONTRIBUTING.md`).

## Rules

- Every change lands through a pull request titled `type(area): what changes` (types, areas and branch names: `CONTRIBUTING.md`); the maintainer merges. CI (format, offline guard, warnings-as-errors build, tests, CodeQL for workflow files) must pass. CodeQL for Swift runs on `main` after each merge and weekly; fix its findings in a follow-up pull request.
- BloomCore never touches the network. Add no Swift packages.
- New BloomCore behavior ships with tests that would fail if it broke. Assert results (files exist, open as their type, have the expected size or content), not implementation details.
- A new way to drag, open, switch flowers or drop gets a journey in `Sources/BloomE2E` that fails if it breaks. A new kind of file gets a sample in the petal matrix.
- A petal that can't work on this Mac, like AirDrop when macOS won't send the file, is shown dimmed with the reason (`WheelItem.unavailable`), never offered and left to fail.
- Minimum macOS 13. Gate newer APIs with `#available` and hide the petal when unavailable.
- Never modify the original file; write results beside it with Finder-style unique names.
- Report a Problem and Send Feedback open a GitHub issue form in the person's browser, filled in by `IssueReport`: the Bloom version and commit, macOS version and Mac chip, and for a failed petal the petal, file types and Bloom's message with file and folder names taken out. The person reads and submits it; the app sends nothing itself.
- Keep the README's petal tables in sync with what the code offers.

## Review guidelines

Flag as **P0**:

- Writing to, moving, renaming or deleting the user's original file, except through the Move action the user chose.
- Overwriting any existing file instead of picking a unique name.
- Network access, telemetry, analytics or a third-party package anywhere in the app.
- An issue report that carries a file's name, folder or contents.
- A failed conversion that leaves a partial or corrupt output behind, or reports success.
- External tools run in a way that lets a file name become part of a command, rather than as separate arguments to `Process`.

Flag as **P1**:

- New BloomCore behavior without a test that would fail if it broke.
- A petal offered where it can't work: the wrong file type, or an API newer than macOS 13 without an `#available` check.
- An output that may not open as the type its extension claims.
- UI state changed off the main actor, or a conversion that blocks the main thread.
- The README's petal tables out of sync with what the code offers.

Formatting is enforced by CI; don't flag formatting or naming preferences.
