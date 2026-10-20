#!/bin/bash
# Runs the checks CI runs for your changes: scripts/test-plan.sh works out from the files you touched whether they
# need the build and unit tests, the flower preview, the end-to-end journeys or the petal matrix.
# Usage: scripts/check.sh [--base <ref>] [--e2e]
#   --base  what your changes are compared with (default origin/main)
#   --e2e   also plays the journeys, and the petal matrix, when your changes need them. They take over the mouse
#           and keyboard, so they run only when asked; CI plays them on every pull request that needs them.
set -euo pipefail

cd "$(dirname "$0")/.."

base="origin/main"
e2e=false
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --e2e) e2e=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

plan="$(scripts/test-plan.sh --base "$base")"
needs() { grep -qx "$1=true" <<<"$plan"; }
echo "$plan"

if needs build; then
  scripts/format.sh
  scripts/check-no-network.sh
  swift build -c release -Xswiftc -warnings-as-errors
  swift test
fi
if needs preview; then
  swift run Bloom --preview build/preview
  echo "The flower preview is in build/preview."
fi
if needs journeys; then
  flags=()
  if needs matrix; then flags+=(--matrix); fi
  if $e2e; then
    scripts/e2e.sh build/e2e ${flags[@]+"${flags[@]}"}
  else
    echo "These changes need the end-to-end tests${flags[*]+ ${flags[*]}}. CI plays them; scripts/check.sh --e2e plays them here."
  fi
fi
