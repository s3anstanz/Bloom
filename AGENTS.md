# Bloom

macOS menu-bar utility: drag a file, tap ⇧ / ⌘ / ⌃, release on a petal. Local-only, no third-party dependencies, MIT (Westfall Labs LLC).

These instructions apply to every agent working in this repository, including Claude Code (through `CLAUDE.md`) and Codex.

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

- Every change lands through a pull request; the maintainer merges. All applicable CI checks must pass; see the validation policy below.
- BloomCore never touches the network. Add no Swift packages.
- New BloomCore behavior ships with tests that would fail if it broke. Assert results (files exist, open as their type, have the expected size or content), not implementation details.
- Minimum macOS 13. Gate newer APIs with `#available` and hide the petal when unavailable.
- Never modify the original file; write results beside it with Finder-style unique names.
- UI changes include a screenshot or recording in the PR description.
- Keep the README's petal tables in sync with what the code offers.

## Validation and review policy

- Before opening a PR, inspect the complete diff, run the relevant checks, fix failures, and repeat affected checks after the final edit. Record commands and actual results in the PR. Never claim an unrun check passed.
- Code, features, tests, rules, CI, scripts, dependencies, configuration, security, and behavior changes warrant a second set of eyes, even if only one line changes. Mixed PRs follow this substantive-change policy.
- For application or test changes, verify on macOS: formatting, `scripts/check-no-network.sh`, `swift build -c release -Xswiftc -warnings-as-errors`, and `swift test`. Package with `scripts/bundle.sh release build/Bloom.app` when packaging is affected; exercise changed UI and include visual evidence. Validate workflow/script changes with their relevant linters and focused checks.
- If the required platform or tool is unavailable, report the exact limitation and unrun checks. Do not treat missing macOS access as successful build/test verification; obtain macOS CI evidence before merging.
- Purely cosmetic copy and routine documentation changes need proofreading, link/command checks where relevant, and `git diff --check`; they do not need an application rebuild. Copy edits in Swift or resource files conservatively receive full CI.
- CI skips expensive build/test/package and CodeQL jobs only when every changed path is `README.md` or a Markdown file under `docs/`, excluding files named AGENTS.md, CLAUDE.md, RULES.md, SECURITY.md, or CONTRIBUTING.md (case-insensitive). Unknown paths, empty/undetermined diffs, and mixed changes run full CI. Renames consider both old and new paths. Scheduled CodeQL scans still run.
- Paths cannot determine intent: documentation that changes requirements, rules, security guidance, or executable instructions is substantive. Add the `full-ci` PR label to force all checks for such changes or whenever unsure. Keep policy files outside the routine documentation allowlist, or extend the classifier when introducing them.
- Local verification complements required CI; it does not replace independent CI for substantive changes. Do not weaken assertions or bypass checks to obtain a green status.
- `AGENTS.md` guides Codex review after it starts; it cannot suppress the automatic review trigger. The repository's Codex automatic-review setting remains separate. Do not request an additional manual Codex review for a purely trivial PR unless asked.

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
