#!/bin/bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 /path/to/MultiSwitcher.app /path/to/output.dmg" >&2
  exit 2
fi
APP_SOURCE="$1"
OUTPUT_DMG="$2"
[[ -d "$APP_SOURCE" && "$APP_SOURCE" == *.app ]] || { echo "A .app bundle is required." >&2; exit 1; }
[[ ! -e "$OUTPUT_DMG" ]] || { echo "Refusing to overwrite existing disk image: $OUTPUT_DMG" >&2; exit 1; }
/bin/mkdir -p "$(/usr/bin/dirname "$OUTPUT_DMG")"
STAGING="$(/usr/bin/mktemp -d "${TMPDIR:-/private/tmp}/multiswitcher-dmg.XXXXXX")"
trap '/bin/rm -rf "$STAGING"' EXIT
/usr/bin/ditto "$APP_SOURCE" "$STAGING/MultiSwitcher.app"
/bin/ln -s /Applications "$STAGING/Applications"
/usr/bin/hdiutil create -volname "MultiSwitcher" -srcfolder "$STAGING" -ov -format UDZO "$OUTPUT_DMG"
/usr/bin/hdiutil verify "$OUTPUT_DMG"
echo "Created verified disk image: $OUTPUT_DMG"
