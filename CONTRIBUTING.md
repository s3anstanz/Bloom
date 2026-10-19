# Contributing

## Workflow

1. Branch from `main`, named `type/short-name` like `fix/airdrop-tahoe`.
2. Make the change, with tests for anything new in `BloomCore`.
3. Run `scripts/check.sh`. It runs what CI will run for the files you changed.
4. Open a pull request using the template, titled as below.
5. CI must be green. **CI result** and **E2E result** are the checks to require before merging: each passes when every job the change needed passed. CodeQL for Swift takes about ten minutes, so it runs on `main` after each merge and weekly; fix its findings in a follow-up pull request.
6. The maintainer reviews and merges.

## Which tests run

`scripts/test-plan.sh` reads the files a change touches and picks the highest level any of them needs. Each level includes the ones above it, and the plan, with each file and the level it asked for, is at the top of every CI run's summary.

| Level | What runs | When the change touches |
|---|---|---|
| 0 | The pull request title check | Only documentation, issue forms or CodeQL |
| 1 | Formatting, the no-network check, a warnings-as-errors build and the unit tests, on macOS 15 and 26 | Any Swift code, tests or scripts |
| 2 | The end-to-end journeys | The app itself: drags, key taps, the flower, the Actions petals, the E2E suite, the app bundle |
| 3 | The journeys and the petal matrix | How files are converted and processed, which petals a file gets, document rendering, the sample files, the package, how the tests run, or any file no rule names |

The **flower preview** also runs when a change touches how the flower looks or moves (`FlowerView`, `FlowerMotion`, `PetalLayout`, `MenuBarIcon`) or the preview itself.

Pull requests play the end-to-end tests on macOS 26. Pushes to `main` play what their changes need on macOS 15 and 26, and every Monday and every run started from the Actions tab plays everything on both. Labels add a level and never remove one: `run:journeys`, `run:matrix` and `preview`. When a change adds a file the rules don't name, it gets the full run; add a rule to `scripts/test-plan.sh` if it needs less.

The **flower preview** posts a **Flower preview** comment with each moment as a looping GIF and stills: the bloom, pointing at petals, switching flowers, resting on Compress until its sizes open and pointing at each, a drop that saves, a drop that fails, a petal that can't work on this Mac, and letting go. It refreshes the comment on every push. To make the same files on your Mac, run `swift run Bloom --preview build/preview`; macOS asks once to let your terminal record the screen.

The **end-to-end journeys** drag files out of Finder with real mouse and key events, tap ⇧, ⌘ and ⌃, drop on petals and check what Bloom saves or what each action does, and the run's summary shows a screenshot of each step.

The **petal matrix** generates a sample of every kind of file Bloom handles, drops each on every petal of every flower and checks each result opens as its type. Its table marks each petal ✅ worked, ⚪ had nothing to do or can't work on that Mac (with Bloom's reason), or ❌ failed (with what went wrong). GitHub's runners are virtual Macs without Wi‑Fi or Bluetooth, so only a run on a real Mac sends to AirDrop.

To play them on your Mac, run `scripts/check.sh --e2e`, or `scripts/e2e.sh [--matrix]` naming journeys or samples to play only those. It quits any running Bloom, takes over the mouse and keyboard while it plays, and your terminal needs Accessibility, Screen Recording and Automation access.

## Ground rules

- **Local only.** `BloomCore` never uses the network; `scripts/check-no-network.sh` enforces it.
- **No dependencies.** Use Apple frameworks and the command-line tools that ship with macOS.
- **Originals are never modified.** Results go next to the source file with Finder-style names (`photo.jpg`, `photo 2.jpg`).
- **macOS 13 minimum.** Gate newer APIs with `#available`, and offer the petal only where it works.
- **Zero warnings.** Release builds compile with warnings as errors.

## Commit and PR titles

Pull request titles, and the commit each one squashes into, follow [Conventional Commits](https://www.conventionalcommits.org) as `type(area): what changes`, like `feat(convert): add a WebP petal` or `fix(actions): AirDrop opens on Tahoe`. The **PR title** check enforces it and labels the pull request `type: …` and `area: …`.

| Type | For | Release |
|---|---|---|
| `feat` | Something new someone using Bloom can do | Middle number |
| `fix` | Something that didn't work and now does | Last number |
| `perf` | The same result, faster or smaller | Last number |
| `refactor` | Code reorganised with no change in behavior | None |
| `test` | Tests only | None |
| `ci`, `build` | Workflows, scripts and packaging | None |
| `docs` | Documentation only | None |
| `chore` | Upkeep, like dependency bumps and releases | None |
| `revert` | Undoing an earlier change | As the change it undoes |

The area is optional and one of `convert`, `tools`, `actions`, `flower`, `menu`, `feedback`, `e2e`, `ci`, `docs` or `release`. A `!` after the type or area marks a change that breaks something people rely on. The type and area say what a change is for; which tests run comes from the files it touches.

## Releasing

Bloom's version is `CFBundleShortVersionString` in `Support/Info.plist`, and the menu shows it. Versions follow [Semantic Versioning](https://semver.org) and stay below 1.0 for now: the middle number goes up for new petals and behavior, the last one for fixes.

1. Open a pull request titled `chore(release): release 0.x.y` that changes that version.
2. Once it merges, run the E2E workflow on `main` from the Actions tab, which plays everything on macOS 15 and 26, and release only when it's green.
3. Tag the merge commit `v0.x.y` and publish a GitHub release for the tag, with notes generated from the pull requests merged since the last one.
