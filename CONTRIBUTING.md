# Contributing

## Workflow

1. Branch from `main`.
2. Make the change, with tests for anything new in `BloomCore`.
3. Run the checks appropriate to the change using the validation policy in [AGENTS.md](AGENTS.md). Substantive application changes require the macOS build/test/verify loop before opening the PR; report any unavailable checks explicitly.
4. Open a pull request using the template. For anything that changes how Bloom looks or moves, include a screenshot or screen recording.
5. All applicable CI must be green. Routine documentation-only PRs skip expensive jobs through the shared change classifier. Add the `full-ci` label for substantive documentation changes or whenever deeper verification is needed; mixed and unknown changes receive full CI.
6. The maintainer reviews and merges.

## Ground rules

- **Local only.** `BloomCore` never uses the network; `scripts/check-no-network.sh` enforces it.
- **No dependencies.** Use Apple frameworks and the command-line tools that ship with macOS.
- **Originals are never modified.** Results go next to the source file with Finder-style names (`photo.jpg`, `photo 2.jpg`).
- **macOS 13 minimum.** Gate newer APIs with `#available`, and offer the petal only where it works.
- **Zero warnings.** Release builds compile with warnings as errors.

## Commit and PR titles

Use [Conventional Commits](https://www.conventionalcommits.org): `feat: add WebP petal`, `fix: keep EXIF orientation when compressing`, `chore: bump CodeQL`.
