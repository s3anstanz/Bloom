#!/bin/bash
# Plays Bloom's end-to-end journeys on this Mac: builds and opens Bloom.app, then drags files out of Finder
# with real mouse and key events and checks what Bloom saves. Quits any running Bloom first.
# Usage: scripts/e2e.sh [output folder] [journey ...]
# The terminal running it needs Accessibility, Screen Recording and Automation (Finder) access.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/e2e}"
shift || true

cd "$ROOT"
scripts/bundle.sh release build/Bloom.app
swift build -c release --product BloomE2E
pkill -x Bloom || true
open -n build/Bloom.app
trap 'pkill -x Bloom || true' EXIT
"$(swift build -c release --show-bin-path)/BloomE2E" --out "$OUT" "$@"
