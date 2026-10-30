#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
OUT="$(mktemp -d /private/tmp/multi-layout-state.XXXXXX)"
xcrun swiftc -disable-sandbox -swift-version 6 -module-cache-path "$OUT/cache" \
 "$ROOT/macos/Sources/MultiSwitcherCore/MultiInterfaceMetrics.swift" \
 "$ROOT/macos/Sources/MultiSwitcher/MultiDesignKit.swift" \
 "$ROOT/macos/Sources/MultiSwitcher/MultiPopoverKit.swift" \
 "$ROOT/macos/Sources/MultiSwitcher/LayoutPresentationState.swift" \
 "$ROOT/macos/Sources/MultiSwitcher/StatusPopoverController.swift" \
 "$ROOT/macos/Tests/LayoutStateChecks/LayoutStateChecks.swift" -o "$OUT/checks"
"$OUT/checks"
