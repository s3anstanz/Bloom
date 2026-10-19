# Contributing

## Workflow

1. Branch from `main`.
2. Make the change, with tests for anything new in `BloomCore`.
3. Run `scripts/format.sh` and `swift test`.
4. Open a pull request using the template.
5. CI must be green: formatting, the no-network check, a warnings-as-errors build, the tests, and CodeQL for the workflow files. CodeQL for Swift takes about ten minutes, so it runs on `main` after each merge and weekly; fix its findings in a follow-up pull request.
6. The maintainer reviews and merges.

Add the `preview` label to a pull request that changes how the flower looks or moves. The Preview workflow then runs Bloom on a Mac runner and posts a **Flower preview** comment with each moment as a looping GIF and stills: the bloom, pointing at petals, switching flowers, a drop that saves, a drop that fails, and letting go. It refreshes the comment on every push while the label stays. To make the same files on your Mac, run `swift run Bloom --preview build/preview`; macOS asks once to let your terminal record the screen.

## Ground rules

- **Local only.** `BloomCore` never uses the network; `scripts/check-no-network.sh` enforces it.
- **No dependencies.** Use Apple frameworks and the command-line tools that ship with macOS.
- **Originals are never modified.** Results go next to the source file with Finder-style names (`photo.jpg`, `photo 2.jpg`).
- **macOS 13 minimum.** Gate newer APIs with `#available`, and offer the petal only where it works.
- **Zero warnings.** Release builds compile with warnings as errors.

## Commit and PR titles

Use [Conventional Commits](https://www.conventionalcommits.org): `feat: add WebP petal`, `fix: keep EXIF orientation when compressing`, `chore: bump CodeQL`.
