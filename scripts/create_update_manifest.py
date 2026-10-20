#!/usr/bin/env python3
"""Create the non-personal update manifest attached to a GitHub release."""
import argparse
import hashlib
import json
import re
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--repository", required=True, help="owner/name")
    parser.add_argument("--dmg", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", args.version):
        raise SystemExit("Version must be stable numeric version text, such as 1.2.3.")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", args.build_number):
        raise SystemExit("Build number must contain only numeric dot-separated components.")
    expected_tag = f"v{args.version}-build{args.build_number}"
    if args.tag != expected_tag:
        raise SystemExit(f"Release tag must be {expected_tag}.")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repository):
        raise SystemExit("Repository must be in owner/name form.")
    if not args.dmg.is_file() or args.dmg.stat().st_size == 0:
        raise SystemExit("Disk image is missing or empty.")
    manifest = {
        "version": args.version,
        "buildNumber": args.build_number,
        "tag": args.tag,
        "url": (
            f"https://github.com/{args.repository}/releases/download/{args.tag}/"
            f"MultiSwitcher-{args.version}-arm64.dmg"
        ),
        "notes": "See the GitHub release notes for changes.",
        "sha256": sha256(args.dmg),
    }
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
