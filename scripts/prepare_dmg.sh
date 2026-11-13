#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.build/release-tools"
python3 -m venv "$TOOLS"
"$TOOLS/bin/python" -m pip install --disable-pip-version-check -r "$ROOT/requirements-release.lock"
