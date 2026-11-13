"""Refresh pinned casks from published manifests; verify ZIPs before writing."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
APPS = {
    "multiswitcher": ("MultiSwitcher", "Keyboard layout correction", "15.0"),
    "multishift": ("MultiShift", "File conversion and tools for Finder", "14.0"),
}


def render(token, manifest):
    name, description, minimum = APPS[token]
    version, build = manifest["version"], manifest["build"]
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid release version")
    if type(build) is not int or build < 1:
        raise ValueError("Invalid build number")
    if manifest["architecture"] != "arm64" or manifest["minimum_macos"] != minimum:
        raise ValueError("Unexpected platform requirements")
    expected = f"{name}-{version}-{build}-arm64.zip"
    if manifest["archive"] != expected:
        raise ValueError("Unexpected archive name")
    digest = manifest["sha256"]
    if not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
        raise ValueError("Invalid SHA256")
    size = manifest["bytes"]
    if type(size) is not int or not 0 < size <= 1024**3:
        raise ValueError("Invalid archive size")
    return f'''cask "{token}" do
  version "{version},{build}"
  sha256 "{digest}"

  url "https://sokolovmo.ru/{token}/{name}-#{{version.csv.first}}-#{{version.csv.second}}-arm64.zip"
  name "{name}"
  desc "{description}"
  homepage "https://sokolovmo.ru/{token}/"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :{'sequoia' if minimum == '15.0' else 'sonoma'}

  app "{name}.app"

  if ENV["HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED"] == "1"
    postflight_steps do
      run "/usr/bin/codesign", args: ["--verify", "--deep", "--strict", "{{{{appdir}}}}/{name}.app"]
      run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{{{appdir}}}}/{name}.app"]
    end
  end

  caveats <<~EOS
    This app is not notarized by Apple. To install without quarantine, explicitly use:
      HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED=1 brew install --cask SokolovMO/apps/{token}
    Updates are available inside the app and require confirmation.
    Quit the app after current work finishes before a Homebrew upgrade.
    Uninstalling this cask preserves your settings and history.
  EOS
end
'''


def download(url, destination, limit):
    # Both manifests and immutable archives must stay on the release HTTPS origin.
    with urllib.request.urlopen(url, timeout=90) as response:
        if not response.url.startswith("https://sokolovmo.ru/"):
            raise ValueError("Unexpected download redirect")
        size = 0
        digest = hashlib.sha256()
        with destination.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > limit:
                    raise ValueError("Download exceeds declared size")
                digest.update(chunk)
                output.write(chunk)
    return size, digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if the pinned casks need updating")
    args = parser.parse_args()
    rendered = {}
    with tempfile.TemporaryDirectory(prefix="multi-casks-") as temporary:
        folder = Path(temporary)
        for token in APPS:
            base = f"https://sokolovmo.ru/{token}/"
            manifest_file = folder / f"{token}.json"
            download(base + "latest.json", manifest_file, 65536)
            manifest = json.loads(manifest_file.read_text())
            content = render(token, manifest)
            size, digest = download(base + manifest["archive"], folder / manifest["archive"], manifest["bytes"])
            if (size, digest) != (manifest["bytes"], manifest["sha256"]):
                raise ValueError(f"{token}: archive size/SHA256 mismatch")
            rendered[token] = content
            print(f"Verified {token} {manifest['version']} ({manifest['build']})")
    # A failed second download never leaves a partly refreshed tap.
    stale = [token for token, content in rendered.items()
             if not (ROOT / "Casks" / f"{token}.rb").exists()
             or (ROOT / "Casks" / f"{token}.rb").read_text() != content]
    if args.check:
        if stale:
            raise SystemExit("Casks need refresh: " + ", ".join(stale))
    else:
        (ROOT / "Casks").mkdir(exist_ok=True)
        for token in stale:
            (ROOT / "Casks" / f"{token}.rb").write_text(rendered[token])


if __name__ == "__main__":
    main()
