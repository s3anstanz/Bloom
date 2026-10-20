#!/bin/bash
# Checks a pull request title against Bloom's naming convention, `type(area): what changes`. The area is optional;
# a `!` before the colon marks a breaking change.
# Usage: scripts/check-title.sh "<title>"
set -euo pipefail

types="feat fix perf refactor test ci docs chore build revert"
areas="convert tools actions flower menu feedback e2e ci docs release"
title="${1:-}"

pattern='^([a-z]+)(\(([a-z0-9-]+)\))?(!)?: [^ ].*$'
if ! [[ "$title" =~ $pattern ]]; then
  echo "“$title” doesn't follow type(area): what changes, like “fix(actions): AirDrop opens on Tahoe”." >&2
  exit 1
fi
type="${BASH_REMATCH[1]}"
area="${BASH_REMATCH[3]}"
if ! [[ " $types " == *" $type "* ]]; then
  echo "“$type” isn't a type. Use one of: $types." >&2
  exit 1
fi
if [ -n "$area" ] && ! [[ " $areas " == *" $area "* ]]; then
  echo "“$area” isn't an area. Use one of: $areas, or leave it out." >&2
  exit 1
fi
