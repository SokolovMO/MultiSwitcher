#!/usr/bin/env python3
"""Reject unsigned, malformed, stale, or misrouted Sparkle release feeds."""

from __future__ import annotations

import argparse
import re
import sys
from typing import NoReturn
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ED_SIGNATURE = f"{{{SPARKLE_NS}}}edSignature"
CHANNEL = f"{{{SPARKLE_NS}}}channel"
VERSION = f"{{{SPARKLE_NS}}}version"
SHORT_VERSION = f"{{{SPARKLE_NS}}}shortVersionString"
SIGNED_FEED_TRAILER = re.compile(
    rb"<!--\s*sparkle-signatures:\s*edSignature:\s*([A-Za-z0-9+/=]+)\s+"
    rb"length:\s*(\d+)\s*-->\s*$"
)


def fail(message: str) -> NoReturn:
    print(f"Appcast validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--appcast", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--channel", choices=("stable", "beta"), required=True)
    args = parser.parse_args()

    raw = args.appcast.read_bytes()
    trailer = SIGNED_FEED_TRAILER.search(raw)
    if trailer is None or int(trailer.group(2)) <= 0:
        fail("missing Sparkle signed-feed trailer")

    try:
        root = ET.fromstring(raw)
    except ET.ParseError as error:
        fail(f"invalid RSS/XML: {error}")
    if root.tag != "rss":
        fail("root element is not RSS")
    channel = root.find("channel")
    if channel is None:
        fail("RSS channel is missing")

    expected_asset = (
        f"https://github.com/{args.repository}/releases/download/{args.tag}/"
    )
    matching_items = [
        item for item in channel.findall("item")
        if item.findtext(VERSION) == args.build_number
        and item.findtext(SHORT_VERSION) == args.version
    ]
    if len(matching_items) != 1:
        fail("expected exactly one item for the current app version and build")

    item = matching_items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        fail("current update item has no enclosure")
    url = enclosure.get("url", "")
    if not url.startswith(expected_asset) or not url.lower().endswith(".dmg"):
        fail("current update enclosure does not point to this release's HTTPS DMG")
    if not enclosure.get(ED_SIGNATURE):
        fail("current update enclosure has no EdDSA archive signature")
    if not enclosure.get("length", "").isdigit() or int(enclosure.get("length", "0")) <= 0:
        fail("current update enclosure has no valid archive length")

    published_channel = item.findtext(CHANNEL)
    if args.channel == "beta" and published_channel != "beta":
        fail("beta release item is missing its beta channel")
    if args.channel == "stable" and published_channel == "beta":
        fail("stable release item is incorrectly marked as beta")

    print(
        f"Validated signed Sparkle appcast: {args.version} ({args.build_number}), "
        f"channel={args.channel}, items={len(channel.findall('item'))}"
    )


if __name__ == "__main__":
    main()
