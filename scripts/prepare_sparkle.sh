#!/bin/bash
# Digest is reviewed before configuration; an unverified archive is never linked.
set -euo pipefail
MULTISWITCHER_SPARKLE_ARCHIVE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
[[ "$MULTISWITCHER_SPARKLE_ARCHIVE_SHA256" =~ ^[a-f0-9]{64}$ ]]
DEST="${MULTISWITCHER_SPARKLE_DEST:-${RUNNER_TEMP:-/tmp}/multiswitcher-sparkle-2.10.0}"
mkdir -p "$DEST"
curl --fail --location --proto '=https' --tlsv1.2 \
  https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz -o "$DEST/archive.tar.xz"
printf '%s  %s\n' "$MULTISWITCHER_SPARKLE_ARCHIVE_SHA256" "$DEST/archive.tar.xz" | shasum -a 256 -c -
tar -xf "$DEST/archive.tar.xz" -C "$DEST"
test -d "$DEST/Sparkle.framework"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'MULTISWITCHER_SPARKLE_FRAMEWORK=%s/Sparkle.framework\n' "$DEST" >> "$GITHUB_ENV"
fi
