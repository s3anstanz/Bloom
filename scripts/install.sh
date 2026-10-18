#!/bin/bash
# Builds Bloom.app from this checkout and (re)launches it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Bloom.app"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Bloom runs on macOS only." >&2
  exit 1
fi

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift isn't installed yet. A dialog will offer Apple's Command Line Tools;"
  echo "install them, then run this script again."
  xcode-select --install
  exit 1
fi

echo "→ Building (the first build takes a minute)"
"$ROOT/scripts/bundle.sh" release "$APP"

pkill -x Bloom 2>/dev/null || true
open "$APP"
echo "✓ Bloom is running from $APP. Look for the flower in your menu bar."
