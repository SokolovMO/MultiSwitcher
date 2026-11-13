#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$project_root/.tools"
if [ ! -d "$project_root/.tools/earshot/.git" ]; then
  git clone https://github.com/Leonxlnx/earshot.git "$project_root/.tools/earshot"
  git -C "$project_root/.tools/earshot" checkout 4ac3d2a
fi
python3.11 -m venv "$project_root/.tools/earshot-venv"
"$project_root/.tools/earshot-venv/bin/pip" install -e "$project_root/.tools/earshot"
"$project_root/.tools/earshot-venv/bin/earshot" doctor
