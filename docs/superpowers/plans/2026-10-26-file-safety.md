# File output and report privacy

Goal: preserve existing files even when output names collide, and keep untrusted diagnostic text out of browser URLs. Reject output paths beneath shared non-sticky, ACL-allowing or other-user-owned ancestors, so another user cannot swap a private staging directory through its parent. Use the existing checkout and Apple APIs; add no dependencies and retain macOS 13 support.

Approach: stage each batch in private, mode-0700 sibling directories, then use macOS's exclusive rename to publish each result with Finder numbering. Writers and failure cleanup see only private staging paths. Do not reserve an empty public file: writers could replace it or follow a swapped symlink. Do not rely on sanitizing raw error messages: arbitrary filenames and document content cannot be enumerated reliably.

- [x] Add regressions for dangling symlinks, colliding output publication, staging cleanup, private permissions, and untrusted report diagnostics.
- [x] Add an internal output transaction; route every conversion/tool output through it. Publish with `renamex_np(RENAME_EXCL)` and retry only destination collisions. A publication failure retains any already-published results rather than deleting paths another process may have changed.
- [x] Replace browser-report diagnostics with a fixed privacy notice. Keep local error messages available in the app and update the README's report description.
- [x] Add archive path/symlink escape regression coverage using hand-built archives. Confine archive subprocess writes to their private output using the built-in macOS sandbox-exec, with parameterized policy paths and no network access. Require macOS tests for this policy.
- [ ] Run available checks, request independent code review, commit, push and open a PR. Require macOS CI for build/unit/E2E validation; this Linux machine cannot execute AppKit.

Review focus: concurrent outputs, dangling symlinks, directory outputs, batch failure cleanup, malformed-archive stderr containing private member names. Sandboxing other converters, network behavior of document importers, and resource budgets remain separate macOS investigation work; do not advertise these as fixed.

Local validation: Swift 6.0.3 parsing and strict formatting passed for all changed Swift files; the no-network guard and diff checks passed. An isolated harness exercising the production report builder with stand-ins for platform metadata fails against the original implementation and passes against this patch. The package test command cannot build on Linux (`AVFoundation` unavailable), so no macOS unit/E2E pass is claimed. Independent source review found no remaining critical/important issues after fixes. GitHub API access is currently denied by the environment proxy; PR creation and macOS CI evidence remain outstanding.
