# Contributing

## Workflow

1. Branch from `main`.
2. Make the change, with tests for anything new in `BloomCore`.
3. Run `scripts/format.sh` and `swift test`.
4. Open a pull request using the template.
5. CI must be green: formatting, the no-network check, a warnings-as-errors build, the tests, and CodeQL for the workflow files. CodeQL for Swift takes about ten minutes, so it runs on `main` after each merge and weekly; fix its findings in a follow-up pull request.
6. The maintainer reviews and merges.

Add the `preview` label to a pull request that changes how the flower looks or moves. The Preview workflow then runs Bloom on a Mac runner and posts a **Flower preview** comment with each moment as a looping GIF and stills: the bloom, pointing at petals, switching flowers, resting on Compress until its sizes open and pointing at each, a drop that saves, a drop that fails, and letting go. It refreshes the comment on every push while the label stays. To make the same files on your Mac, run `swift run Bloom --preview build/preview`; macOS asks once to let your terminal record the screen.

The **E2E** workflow plays Bloom's end-to-end journeys on macOS 15 and macOS 26 runners for every pull request. It drags files out of Finder with real mouse and key events, taps ⇧, ⌘ and ⌃, drops on petals and checks what Bloom saves or what each action does, and the run's summary shows a screenshot of each step.

The **petal matrix** goes further: it generates a sample of every kind of file Bloom handles, drops each on every petal of every flower and checks each result opens as its type. Its table marks each petal ✅ worked, ⚪ had nothing to do or can't work on that Mac (with Bloom's reason), or ❌ failed (with what went wrong). It runs on `main`, every Monday, from the Actions tab, and on pull requests labelled `full-e2e`. GitHub's runners are virtual Macs without AirDrop, so only a run on a real Mac sends to AirDrop.

To play them on your Mac, run `scripts/e2e.sh`, or `scripts/e2e.sh --matrix` for the matrix too; name journeys or samples to play only those. It quits any running Bloom, and your terminal needs Accessibility, Screen Recording and Automation access.

## Ground rules

- **Local only.** `BloomCore` never uses the network; `scripts/check-no-network.sh` enforces it.
- **No dependencies.** Use Apple frameworks and the command-line tools that ship with macOS.
- **Originals are never modified.** Results go next to the source file with Finder-style names (`photo.jpg`, `photo 2.jpg`).
- **macOS 13 minimum.** Gate newer APIs with `#available`, and offer the petal only where it works.
- **Zero warnings.** Release builds compile with warnings as errors.

## Commit and PR titles

Use [Conventional Commits](https://www.conventionalcommits.org): `feat: add WebP petal`, `fix: keep EXIF orientation when compressing`, `chore: bump CodeQL`.

## Releasing

Bloom's version is `CFBundleShortVersionString` in `Support/Info.plist`, and the menu shows it. Versions follow [Semantic Versioning](https://semver.org) and stay below 1.0 for now: the middle number goes up for new petals and behavior, the last one for fixes.

1. Open a pull request titled `chore: release 0.x.y` that changes that version.
2. Once it merges, tag the merge commit `v0.x.y` and publish a GitHub release for the tag, with notes generated from the pull requests merged since the last one.
