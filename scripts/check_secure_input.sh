#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CHECK_ROOT="${MULTI_SECURE_INPUT_BUILD_ROOT:-$(mktemp -d /private/tmp/multi-secure-input.XXXXXX)}"
export CLANG_MODULE_CACHE_PATH="$CHECK_ROOT/cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CHECK_ROOT/cache"
export MULTISWITCHER_ENABLE_UPDATES=0
export MULTISWITCHER_ENABLE_CRASH_REPORTING=0
# Avoid the release Package.resolved pulling in Sparkle for a core-only check.
mkdir -p "$CHECK_ROOT/package"
cp "$ROOT/macos/Package.swift" "$CHECK_ROOT/package/Package.swift"
cp -R "$ROOT/macos/Sources" "$ROOT/macos/Tests" "$CHECK_ROOT/package/"
swift build --disable-sandbox --build-system native --package-path "$CHECK_ROOT/package" --scratch-path "$CHECK_ROOT/build" --target MultiSwitcherCore >/dev/null
SOURCES=()
for source in "$ROOT"/macos/Sources/MultiSwitcher/*.swift; do
    [[ "$source" == */MultiSwitcherApplication.swift ]] || SOURCES+=("$source")
done
xcrun swiftc -swift-version 6 -disable-sandbox -module-cache-path "$CHECK_ROOT/cache" \
 -I "$CHECK_ROOT/build/arm64-apple-macosx/debug/Modules" \
 "$CHECK_ROOT"/build/arm64-apple-macosx/debug/MultiSwitcherCore.build/*.swift.o \
 "${SOURCES[@]}" "$ROOT/macos/Tests/SecureInputChecks/SecureInputChecks.swift" -o "$CHECK_ROOT/checks"
MULTI_NOTICE_ICON="$ROOT/macos/MultiSwitcher.icns" MULTI_AUDIT_DATA_ROOT="$CHECK_ROOT/data" "$CHECK_ROOT/checks"
echo "Checks completed with isolated data: $CHECK_ROOT/data"
