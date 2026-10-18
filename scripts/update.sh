#!/bin/bash
# Pulls the latest Bloom from GitHub, then rebuilds and relaunches it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
git -C "$ROOT" pull --ff-only
"$ROOT/scripts/install.sh"
