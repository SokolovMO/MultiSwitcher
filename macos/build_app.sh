#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_DIR="$(cd "$PROJECT_DIR/.." && pwd -P)"
APP_NAME="MultiSwitcher"
INFO_PLIST="$PROJECT_DIR/Info.plist"
SIGN_IDENTITY="${MULTISWITCHER_SIGN_IDENTITY:-MultiSwitcher Stable Code Signing}"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    IDENTITIES=$(/usr/bin/security find-identity -v -p codesigning)
    if [[ "$SIGN_IDENTITY" =~ ^[[:xdigit:]]{40}$ ]]; then
        /usr/bin/awk -v identity="$SIGN_IDENTITY" '$2 == identity { found = 1 } END { exit !found }' <<<"$IDENTITIES" || {
            echo "Signing identity fingerprint is unavailable in the configured keychains: $SIGN_IDENTITY" >&2
            exit 1
        }
    else
        MATCHING_IDENTITIES=$(/usr/bin/awk -v name="\"$SIGN_IDENTITY\"" 'index($0, name) { print $2 }' <<<"$IDENTITIES")
        if [[ -z "$MATCHING_IDENTITIES" ]]; then
            echo "Signing identity is unavailable in the configured keychains: $SIGN_IDENTITY" >&2
            exit 1
        fi
        if [[ "$MATCHING_IDENTITIES" == *$'\n'* ]]; then
            echo "Multiple signing identities are named '$SIGN_IDENTITY'; set MULTISWITCHER_SIGN_IDENTITY to one SHA-1 fingerprint." >&2
            exit 1
        fi
        # Sign by the unique fingerprint. codesign can otherwise reject a common name
        # when similarly named certificate-only entries also exist in other keychains.
        SIGN_IDENTITY="$MATCHING_IDENTITIES"
    fi
fi

if [[ -n "${MULTISWITCHER_BUILD_ROOT:-}" ]]; then
    BUILD_ROOT="$MULTISWITCHER_BUILD_ROOT"
    if [[ -e "$BUILD_ROOT" ]]; then
        echo "Build destination already exists: $BUILD_ROOT" >&2
        exit 1
    fi
    mkdir -m 700 -p "$BUILD_ROOT"
else
    BUILD_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/multiswitcher-build.XXXXXX")"
fi
BUILD_ROOT="$(cd "$BUILD_ROOT" && pwd -P)"

# A build inside the synced source tree can acquire File Provider metadata
# after codesign, invalidating the app bundle. Always stage somewhere else.
case "$BUILD_ROOT/" in
    "$REPO_DIR/"*)
        echo "Build destination must be outside the source tree: $BUILD_ROOT" >&2
        exit 1
        ;;
esac

APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")

ENABLE_UPDATES="${MULTISWITCHER_ENABLE_UPDATES:-0}"
UPDATE_REPO="${MULTISWITCHER_GITHUB_REPOSITORY:-}"
DEVELOPER_TEAM_ID="${MULTISWITCHER_DEVELOPER_TEAM_ID:-}"
if [[ "$ENABLE_UPDATES" == "1" ]]; then
    [[ "$UPDATE_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
        echo "Set MULTISWITCHER_GITHUB_REPOSITORY to owner/repository for release builds." >&2
        exit 1
    }
    [[ "$DEVELOPER_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || {
        echo "Set MULTISWITCHER_DEVELOPER_TEAM_ID to the 10-character Apple Developer Team ID." >&2
        exit 1
    }
fi
echo "Building $APP_NAME $VERSION ($BUILD_NUMBER) for arm64"
echo "Staging directory: $BUILD_ROOT"

mkdir -p "$BUILD_ROOT/module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/module-cache"

SWIFT_OPTIONS=(
    --package-path "$PROJECT_DIR"
    --scratch-path "$BUILD_ROOT/swiftpm"
    --cache-path "$BUILD_ROOT/cache"
    --config-path "$BUILD_ROOT/config"
    --security-path "$BUILD_ROOT/security"
    --disable-sandbox
    --disable-dependency-cache
    --manifest-cache local
    -Xswiftc -module-cache-path
    -Xswiftc "$BUILD_ROOT/module-cache"
    -c release
    --arch arm64
)

swift build "${SWIFT_OPTIONS[@]}" --product "$APP_NAME"
BIN_DIR="$(swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"
BIN_PATH="$BIN_DIR/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "Built executable is missing: $BIN_PATH" >&2
    exit 1
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/Licenses"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
if [[ "$ENABLE_UPDATES" == "1" ]]; then
    INFO="$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :MSUpdateFeedURL string https://github.com/$UPDATE_REPO/releases/latest/download/version.json" "$INFO"
    /usr/libexec/PlistBuddy -c "Add :MSReleaseBaseURL string https://github.com/$UPDATE_REPO/releases/download" "$INFO"
    /usr/libexec/PlistBuddy -c "Add :MSReleasesURL string https://github.com/$UPDATE_REPO/releases" "$INFO"
    /usr/libexec/PlistBuddy -c "Add :MSDeveloperTeamID string $DEVELOPER_TEAM_ID" "$INFO"
fi
cp "$PROJECT_DIR/MultiSwitcher.icns" "$APP_BUNDLE/Contents/Resources/MultiSwitcher.icns"
cp "$PROJECT_DIR/icons/layout-ru.svg" "$APP_BUNDLE/Contents/Resources/MultiSwitcher-Layout-RU.svg"
cp "$PROJECT_DIR/icons/layout-us.svg" "$APP_BUNDLE/Contents/Resources/MultiSwitcher-Layout-US.svg"
cp "$PROJECT_DIR/icons/layout-disabled.svg" "$APP_BUNDLE/Contents/Resources/MultiSwitcher-Layout-Disabled.svg"
cp "$PROJECT_DIR/icons/app-icon-az.svg" "$APP_BUNDLE/Contents/Resources/MultiSwitcher-AppIcon-AZ.svg"
cp "$PROJECT_DIR/icons/app-icon-disabled.svg" "$APP_BUNDLE/Contents/Resources/MultiSwitcher-AppIcon-Disabled.svg"
cp "$REPO_DIR/LICENSE" "$APP_BUNDLE/Contents/Resources/Licenses/RuSwitcher-MIT.txt"
cp "$REPO_DIR/TRADEMARKS.md" "$APP_BUNDLE/Contents/Resources/Licenses/RuSwitcher-Attribution.md"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

ARCHS="$(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")"
if [[ "$ARCHS" != arm64 ]]; then
    echo "Expected arm64-only executable, got: $ARCHS" >&2
    exit 1
fi
plutil -lint "$APP_BUNDLE/Contents/Info.plist"

# The staging directory is local; clear inherited source-file attributes once,
# before signing. Developer ID releases use Apple's secure timestamp service.
xattr -cr "$APP_BUNDLE"
SIGN_TIMESTAMP_ARGS=(--timestamp=none)
if [[ "${MULTISWITCHER_CODESIGN_TIMESTAMP:-0}" == "1" ]]; then
    SIGN_TIMESTAMP_ARGS=(--timestamp)
fi
codesign --force --sign "$SIGN_IDENTITY" "${SIGN_TIMESTAMP_ARGS[@]}" \
    --entitlements "$PROJECT_DIR/MultiSwitcher.entitlements" \
    --options runtime "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

{
    echo "Product: $APP_NAME"
    echo "Version: $VERSION ($BUILD_NUMBER)"
    echo "Architecture: $ARCHS"
    echo "Bundle identifier: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
    echo "Signing identity: $SIGN_IDENTITY"
    echo "Updater configured: $ENABLE_UPDATES"
    echo "Executable SHA-256: $(shasum -a 256 "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | awk '{print $1}')"
} > "$BUILD_ROOT/BUILD-INFO.txt"

echo "Verified app: $APP_BUNDLE"
echo "Build record: $BUILD_ROOT/BUILD-INFO.txt"
