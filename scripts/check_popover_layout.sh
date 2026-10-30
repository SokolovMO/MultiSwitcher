#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
CHECK_ROOT="$(mktemp -d /private/tmp/multi-popover-check.XXXXXX)"
xcrun swiftc -swift-version 6 -target arm64-apple-macos15.0 \
  -module-cache-path "$CHECK_ROOT/cache" \
  "$ROOT/macos/Sources/MultiSwitcherCore/MultiInterfaceMetrics.swift" \
  "$ROOT/macos/Sources/MultiSwitcher/MultiDesignKit.swift" \
  "$ROOT/macos/Sources/MultiSwitcher/MultiPopoverKit.swift" \
  "$ROOT/macos/Tests/PopoverChecks/PopoverChecks.swift" -o "$CHECK_ROOT/checks"
MULTI_POPOVER_CHECK_OUTPUT="$CHECK_ROOT/output" "$CHECK_ROOT/checks"
