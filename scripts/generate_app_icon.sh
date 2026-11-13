#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
OUT="$(mktemp -d /private/tmp/multi-icon-generator.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -disable-sandbox -swift-version 6 -module-cache-path "$OUT/cache" \
 "$ROOT/macos/Sources/MultiSwitcherCore/MultiInterfaceMetrics.swift" \
 "$ROOT/macos/Sources/MultiSwitcher/MultiDesignKit.swift" \
 "$ROOT/macos/generate_icon.swift" -o "$OUT/generate"
"$OUT/generate" "$ROOT/macos"
