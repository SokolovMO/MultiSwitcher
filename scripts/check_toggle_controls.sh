#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CHECK_ROOT="$(mktemp -d /private/tmp/multi-toggle-check.XXXXXX)"
xcrun swiftc -swift-version 6 -target arm64-apple-macos15.0 -module-cache-path "$CHECK_ROOT/cache" \
 "$ROOT/macos/Sources/MultiSwitcher/GraphiteToggleButton.swift" \
 "$ROOT/macos/Tests/ToggleChecks/ToggleChecks.swift" -o "$CHECK_ROOT/checks"
"$CHECK_ROOT/checks"
