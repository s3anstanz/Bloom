#!/bin/bash
# Formats all Swift code in place with swift-format, which ships with Swift 6 (Xcode 16 and later).
set -euo pipefail

cd "$(dirname "$0")/.."
swift format --in-place --recursive Package.swift Sources Tests
