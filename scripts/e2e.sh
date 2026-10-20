#!/bin/bash
# Plays Bloom's end-to-end journeys on this Mac: builds and opens Bloom.app, then drags files out of Finder
# with real mouse and key events and checks what Bloom saves. Quits any running Bloom first.
# Usage: scripts/e2e.sh [output folder] [--matrix] [journey or sample ...]
# --matrix also drops a sample of every kind of file on every petal Bloom offers for it, which takes a while.
# The terminal running it needs Accessibility, Screen Recording and Automation (Finder) access.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/e2e"
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
  OUT="$1"
  shift
fi

cd "$ROOT"
scripts/bundle.sh release build/Bloom.app
swift build -c release --product BloomE2E
pkill -x Bloom || true
open -n build/Bloom.app
trap 'pkill -x Bloom || true' EXIT
"$(swift build -c release --show-bin-path)/BloomE2E" --out "$OUT" "$@"
