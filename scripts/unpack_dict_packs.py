#!/usr/bin/env python3
"""Validate and unpack the repository's raw-DEFLATE FrequencyWords packs."""

from __future__ import annotations

import hashlib
import json
import re
import sys
import zlib
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: unpack_dict_packs.py DICT_DIRECTORY OUTPUT_DIRECTORY")

    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("format") != 1:
        raise SystemExit("unsupported dictionary manifest format")

    destination.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for pack in manifest.get("packs", []):
        lang = pack.get("lang")
        if lang not in {"en", "ru"}:
            raise SystemExit(f"unsupported dictionary language: {lang!r}")
        compressed = (source / pack["file"]).read_bytes()
        if len(compressed) != pack["size"]:
            raise SystemExit(f"unexpected size for {pack['file']}")
        if hashlib.sha256(compressed).hexdigest() != pack["sha256"]:
            raise SystemExit(f"checksum mismatch for {pack['file']}")

        try:
            decoded = zlib.decompress(compressed, wbits=-zlib.MAX_WBITS).decode("utf-8")
        except (zlib.error, UnicodeDecodeError) as error:
            raise SystemExit(f"cannot decode {pack['file']}: {error}") from error
        words = decoded.splitlines()
        if len(words) != pack["count"] or len(set(words)) != len(words):
            raise SystemExit(f"word count or uniqueness check failed for {pack['file']}")
        if any(not word or word != word.lower() or re.search(r"\s", word) for word in words):
            raise SystemExit(f"word-list format check failed for {pack['file']}")

        output = destination / f"{lang}.words"
        output.write_text("\n".join(words) + "\n", encoding="utf-8")
        written.append(output)

    if {path.stem for path in written} != {"en", "ru"}:
        raise SystemExit("both English and Russian packs are required")
    print(f"Validated and unpacked {len(written)} language packs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
