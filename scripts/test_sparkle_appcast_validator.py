#!/usr/bin/env python3
"""Small regression checks for the signed-feed release gate."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("validate_sparkle_appcast.py")
VALID_FEED = b'''<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel><title>MultiSwitcher</title><item>
    <sparkle:version>12</sparkle:version>
    <sparkle:shortVersionString>0.3.3</sparkle:shortVersionString>
    <sparkle:channel>beta</sparkle:channel>
    <enclosure url="https://github.com/SokolovMO/MultiSwitcher/releases/download/beta-v0.3.3-build18/MultiSwitcher-0.3.3-arm64.dmg"
      length="12345" type="application/octet-stream" sparkle:edSignature="ZHVtbXk=" />
  </item></channel>
</rss><!-- sparkle-signatures:
edSignature: ZHVtbXk=
length: 260
-->
'''


class SparkleAppcastValidatorTests(unittest.TestCase):
    def validate(self, feed: bytes) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory(prefix="multiswitcher-appcast-test-") as temp_dir:
            appcast = Path(temp_dir) / "appcast.xml"
            appcast.write_bytes(feed)
            return subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--appcast",
                    str(appcast),
                    "--version",
                    "0.3.3",
                    "--build-number",
                    "12",
                    "--tag",
                    "beta-v0.3.3-build18",
                    "--repository",
                    "SokolovMO/MultiSwitcher",
                    "--channel",
                    "beta",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

    def test_accepts_current_signed_beta_item(self) -> None:
        result = self.validate(VALID_FEED)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("channel=beta", result.stdout)

    def test_rejects_unsigned_feed(self) -> None:
        result = self.validate(VALID_FEED.replace(b"<!-- sparkle-signatures:", b"<!-- removed-signature:"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("signed-feed trailer", result.stderr)

    def test_rejects_missing_archive_signature(self) -> None:
        result = self.validate(VALID_FEED.replace(b" sparkle:edSignature=\"ZHVtbXk=\"", b""))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("EdDSA archive signature", result.stderr)


if __name__ == "__main__":
    unittest.main()
