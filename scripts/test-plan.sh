#!/bin/bash
# Works out which tests a change needs from the files it touches, so a README edit doesn't play the petal matrix and
# a change to how files are converted can't skip it.
#
# Usage: scripts/test-plan.sh [--base <ref>] [--all] [--with journeys|matrix|preview ...]
#   --base   what the change is compared with (default origin/main)
#   --all    everything, as on the Monday run
#   --with   adds a level on top of what the files need; nothing takes one away
#
# Prints build=, preview=, journeys= and matrix= as true or false, and level= as the highest level needed. With
# TEST_PLAN_SUMMARY set to a file, also writes a Markdown table of each changed file and the level it asks for.
#
# Levels:
#   0  quick checks only: documentation, issue forms, CodeQL
#   1  build and unit tests: any Swift code, tests or scripts
#   2  end-to-end journeys: the app itself (drags, the flower, key taps, actions) and the E2E suite
#   3  petal matrix: how files are converted and processed, the petal catalog, the sample files, the package
# A file no rule names asks for level 3, so a new kind of file is tested fully until a rule says otherwise.
# The flower preview runs for files that change how the flower looks or moves, whatever their level.
set -euo pipefail

cd "$(dirname "$0")/.."

base="origin/main"
all=false
with=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --all) all=true; shift ;;
    --with) with="$with $2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Prints a file's level, whether it changes the flower's look (preview or -), and why.
classify() {
  case "$1" in
    *.md | LICENSE | docs/* | .github/ISSUE_TEMPLATE/* | .github/dependabot.yml | .github/workflows/codeql.yml)
      echo "0 - documentation and repository settings" ;;
    .github/workflows/pr-title.yml | scripts/check-title.sh)
      echo "0 - pull request title check" ;;
    Sources/BloomCore/Engine.swift | Sources/BloomCore/Compression.swift | Sources/BloomCore/DocumentRenderer.swift)
      echo "3 - converts and processes files" ;;
    Sources/BloomCore/Catalog.swift)
      echo "3 - decides which petals each kind of file gets" ;;
    Sources/BloomRender/* | scripts/bundle.sh)
      echo "3 - renders documents inside Bloom.app" ;;
    Sources/BloomFixtures/* | Sources/BloomE2E/Matrix.swift)
      echo "3 - the sample files and the petal matrix" ;;
    Package.swift)
      echo "3 - the package and its targets" ;;
    .github/workflows/e2e.yml | .github/workflows/test-plan.yml | scripts/test-plan.sh)
      echo "3 - how the end-to-end tests run" ;;
    Sources/Bloom/FlowerView.swift | Sources/BloomCore/FlowerMotion.swift | Sources/BloomCore/PetalLayout.swift)
      echo "2 preview the flower's look and motion" ;;
    Sources/Bloom/MenuBarIcon.swift)
      echo "1 preview the menu bar icon, which no drag or drop depends on" ;;
    Sources/Bloom/FlowerPreview.swift | .github/workflows/preview.yml)
      echo "1 preview the flower preview itself" ;;
    Sources/Bloom/QuickActions.swift | Sources/Bloom/FloatShelf.swift)
      echo "2 - the Actions petals" ;;
    Sources/Bloom/IssueLink.swift | Sources/BloomCore/IssueReport.swift)
      echo "1 - Report a Problem and Send Feedback" ;;
    Sources/Bloom/* | Sources/BloomCore/KeyTaps.swift | Sources/BloomCore/DragStart.swift | Sources/BloomCore/FlowerTabs.swift)
      echo "2 - drags, key taps and the flower" ;;
    Sources/BloomE2E/* | scripts/e2e.sh | .github/scripts/publish-images.sh)
      echo "2 - the end-to-end journeys" ;;
    Support/*)
      echo "2 - Bloom.app's bundle" ;;
    Tests/* | Sources/* | scripts/* | .swift-format | .github/workflows/ci.yml | .github/scripts/*)
      echo "1 - code checked by the build and unit tests" ;;
    *)
      echo "3 - no rule names this file, so everything runs" ;;
  esac
}

level=0
preview=false
rows=""
if $all; then
  level=3
  preview=true
  rows="| (everything) | 3 | the full run |"$'\n'
else
  # Committed changes, plus uncommitted and new files when run on a working copy.
  files="$({
    git diff --name-only "$base"...HEAD
    git diff --name-only HEAD
    git ls-files --others --exclude-standard
  } | sort -u)"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    read -r file_level file_preview reason <<<"$(classify "$file")"
    if [ "$file_level" -gt "$level" ]; then level="$file_level"; fi
    if [ "$file_preview" = preview ]; then preview=true; fi
    rows+="| \`$file\` | $file_level | $reason |"$'\n'
  done <<<"$files"
fi

for extra in $with; do
  case "$extra" in
    journeys) if [ "$level" -lt 2 ]; then level=2; fi ;;
    matrix) level=3 ;;
    preview) preview=true ;;
    *) echo "Unknown level for --with: $extra" >&2; exit 2 ;;
  esac
done

flag() { if [ "$1" -ge "$2" ]; then echo true; else echo false; fi; }
build="$(flag "$level" 1)"
journeys="$(flag "$level" 2)"
matrix="$(flag "$level" 3)"
if [ "$build" = false ]; then preview=false; fi

echo "level=$level"
echo "build=$build"
echo "preview=$preview"
echo "journeys=$journeys"
echo "matrix=$matrix"

if [ -n "${TEST_PLAN_SUMMARY:-}" ]; then
  state() { if [ "$1" = true ]; then echo "runs"; else echo "skipped"; fi; }
  {
    echo "### Tests for this change: level $level"
    echo
    echo "| Build and unit tests | Flower preview | Journeys | Petal matrix |"
    echo "|---|---|---|---|"
    echo "| $(state "$build") | $(state "$preview") | $(state "$journeys") | $(state "$matrix") |"
    echo
    if [ -n "$with" ]; then
      echo "Added by label:$with"
      echo
    fi
    echo "| File | Level | Why |"
    echo "|---|---|---|"
    printf '%s' "${rows:-| (no files) | 0 | |
}"
  } >>"$TEST_PLAN_SUMMARY"
fi
