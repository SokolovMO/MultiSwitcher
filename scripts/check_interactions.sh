#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CHECK_ROOT="${MULTI_INTERACTION_BUILD_ROOT:-$(mktemp -d /private/tmp/multi-interactions.XXXXXX)}"
export CLANG_MODULE_CACHE_PATH="$CHECK_ROOT/cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CHECK_ROOT/cache"
swift build --disable-sandbox --build-system native --package-path "$ROOT/macos" --scratch-path "$CHECK_ROOT/build" --target MultiSwitcherCore >/dev/null
SOURCES=()
for source in "$ROOT"/macos/Sources/MultiSwitcher/*.swift; do
    [[ "$source" == */MultiSwitcherApplication.swift ]] || SOURCES+=("$source")
done
xcrun swiftc -swift-version 6 -disable-sandbox -module-cache-path "$CHECK_ROOT/cache" \
 -I "$CHECK_ROOT/build/arm64-apple-macosx/debug/Modules" \
 "$CHECK_ROOT"/build/arm64-apple-macosx/debug/MultiSwitcherCore.build/*.swift.o \
 "${SOURCES[@]}" "$ROOT/macos/Tests/InteractionChecks/InteractionChecks.swift" -o "$CHECK_ROOT/checks"
MULTI_AUDIT_DATA_ROOT="$CHECK_ROOT/data" "$CHECK_ROOT/checks"
