#!/bin/bash
# Exercises selected-text conversion without starting the app or changing its profile.
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
    echo "Selection conversion checks require macOS (Carbon keyboard layouts)." >&2
    exit 1
fi

CHECK_REPO=$(cd "$(dirname "$0")/.." && pwd)
CHECK_TESTS="$CHECK_REPO/macos/Tests/SelectionConversionChecks"
CHECK_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/multiswitcher-selection-checks.XXXXXX")
trap 'rm -rf "$CHECK_TEMP"' EXIT
mkdir -p "$CHECK_TEMP/module-cache"

python3 "$CHECK_TESTS/prepare.py" "$CHECK_REPO" "$CHECK_TEMP"
python3 "$CHECK_REPO/scripts/unpack_dict_packs.py" "$CHECK_REPO/dicts" "$CHECK_TEMP/Lexicons"

xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_TEMP/module-cache" \
    -emit-library -emit-module -module-name MultiSwitcherCore \
    "$CHECK_REPO"/macos/Sources/MultiSwitcherCore/*.swift \
    -emit-module-path "$CHECK_TEMP/MultiSwitcherCore.swiftmodule" \
    -o "$CHECK_TEMP/libMultiSwitcherCore.dylib"

xcrun swiftc -swift-version 6 -module-cache-path "$CHECK_TEMP/module-cache" \
    -I "$CHECK_TEMP" -L "$CHECK_TEMP" -lMultiSwitcherCore \
    -Xlinker -rpath -Xlinker "$CHECK_TEMP" -framework Carbon -framework AppKit \
    "$CHECK_TEMP/Boundary.swift" "$CHECK_TEMP/SmartConvert.swift" "$CHECK_TEMP/LayoutDetector.swift" \
    "$CHECK_TEMP/DynamicKeyMapping.swift" "$CHECK_TEMP/KeyMapping.swift" \
    "$CHECK_TESTS/main.swift" -parse-as-library -o "$CHECK_TEMP/SelectionConversionChecks"

"$CHECK_TEMP/SelectionConversionChecks" "$CHECK_TEMP/Lexicons" "$CHECK_REPO/dicts/themes"
