#!/bin/bash
# Builds Bloom and wraps the binary in an ad-hoc signed Bloom.app.
# Usage: scripts/bundle.sh [debug|release] [path/to/Bloom.app]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="${2:-$ROOT/build/Bloom.app}"

cd "$ROOT"
swift build -c "$CONFIG" --product Bloom
swift build -c "$CONFIG" --product BloomRender
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Bloom" "$APP/Contents/MacOS/Bloom"
cp "$BIN_DIR/BloomRender" "$APP/Contents/MacOS/BloomRender"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP/Contents/MacOS/BloomRender"
codesign --force --sign - "$APP"
echo "Built $APP"
