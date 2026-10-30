#!/usr/bin/env python3
"""Verify the curated thematic packs and copy their manifest into an app bundle."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: prepare_thematic_lexicons.py SOURCE_DIRECTORY DESTINATION_DIRECTORY")

    source, destination = map(Path, sys.argv[1:])
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("format") != 1 or not manifest.get("license"):
        raise SystemExit("unsupported or incomplete thematic vocabulary manifest")

    seen: set[tuple[str, str]] = set()
    for pack in manifest.get("packs", []):
        pack_id, language = pack.get("id"), pack.get("language")
        key = (pack_id, language)
        if pack_id not in {"technology", "design", "brands", "slang"} or language not in {"en", "ru"}:
            raise SystemExit(f"unsupported thematic pack: {key!r}")
        if key in seen:
            raise SystemExit(f"duplicate thematic pack: {key!r}")
        seen.add(key)
        data = (source / pack["file"]).read_bytes()
        words = data.decode("utf-8").splitlines()
        if len(data) != pack["size"] or hashlib.sha256(data).hexdigest() != pack["sha256"]:
            raise SystemExit(f"size or SHA-256 mismatch: {pack['file']}")
        if len(words) != pack["count"] or len(set(words)) != len(words):
            raise SystemExit(f"word count or uniqueness check failed: {pack['file']}")
        if any(not word or word != word.lower() or re.search(r"\s", word) for word in words):
            raise SystemExit(f"word-list format check failed: {pack['file']}")

    expected = {(theme, language) for theme in ("technology", "design", "brands", "slang") for language in ("en", "ru")}
    if seen != expected:
        raise SystemExit(f"missing themed packs: {sorted(expected - seen)}")

    destination.mkdir(parents=True, exist_ok=True)
    for pack in manifest["packs"]:
        shutil.copyfile(source / pack["file"], destination / pack["file"])
    shutil.copyfile(source / "manifest.json", destination / "manifest.json")
    print(f"Validated {len(manifest['packs'])} thematic vocabulary packs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
