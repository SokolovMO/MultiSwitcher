#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CHECK_ROOT="$(mktemp -d /private/tmp/multi-sidebar-check.XXXXXX)"
xcrun swiftc -swift-version 6 -target arm64-apple-macos15.0 -module-cache-path "$CHECK_ROOT/cache" \
 "$ROOT/macos/Sources/MultiSwitcherCore/MultiInterfaceMetrics.swift" \
 "$ROOT/macos/Sources/MultiSwitcher/MultiDesignKit.swift" \
 "$ROOT/macos/Tests/SidebarChecks/ComponentSettingsFixture.swift" \
 "$ROOT/macos/Tests/SidebarChecks/SidebarChecks.swift" -o "$CHECK_ROOT/checks"
"$CHECK_ROOT/checks"
