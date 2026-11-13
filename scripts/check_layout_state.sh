#!/usr/bin/env bash
# Exercise the real NSMenu and application controller on an isolated profile.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
OUT="$(mktemp -d /private/tmp/multiswitcher-native-menu.XXXXXX)"
APP="${1:-}"
if [[ -z "$APP" ]]; then
    MULTISWITCHER_SIGN_IDENTITY=- MULTISWITCHER_BUILD_ROOT="$OUT/build" \
        bash "$ROOT/macos/build_app.sh"
    APP="$OUT/build/MultiSwitcher.app"
fi
python3 - "$APP" "$OUT" <<'CHECK'
import json,os,subprocess,sys
from pathlib import Path
app,root=map(Path,sys.argv[1:])
env=dict(os.environ,MULTI_AUDIT_DATA_ROOT=str(root/'profile'),MULTI_AUDIT_SCENARIO='native')
with (root/'runtime.log').open('w') as log:
    subprocess.run([str(app/'Contents/MacOS/MultiSwitcher')],env=env,stdout=log,stderr=log,timeout=90,check=True)
report=json.loads((root/'profile/native-results.json').read_text())
assert report['cycles']==100 and report['failures']==[] and not report['trackingAfterClose'],report
print('Native NSMenu: 100 state cycles passed; evidence:',root)
CHECK
