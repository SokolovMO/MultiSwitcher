#!/usr/bin/env python3
"""Stage real app code and extract the small production methods under test."""

from pathlib import Path
import re
import shutil
import sys


def declaration(source: str, signature: str) -> str:
    start = source.index(signature)
    # Ignore braces inside comments/quoted strings when locating a declaration's end.
    masked = re.sub(
        r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"',
        lambda match: " " * len(match.group()),
        source,
        flags=re.DOTALL,
    )
    opening = masked.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        if masked[end] == "{":
            depth += 1
        elif masked[end] == "}":
            depth -= 1
        end += 1
    return source[start:end]


def main() -> None:
    repo, destination = map(Path, sys.argv[1:])
    app = repo / "macos/Sources/MultiSwitcher"
    for name in ("SmartConvert.swift", "DynamicKeyMapping.swift", "KeyMapping.swift"):
        shutil.copyfile(app / name, destination / name)

    settings = (app / "SettingsManager.swift").read_text()
    converter = (app / "TextConverter.swift").read_text()
    detector = (app / "AutoSwitch.swift").read_text()
    template = Path(__file__).with_name("Boundary.swift.in").read_text()
    replacements = {
        "/* SETTINGS_PROPERTIES */": "\n".join(
            declaration(settings, f"var {name}: Bool")
            for name in ("smartConversion", "convertByText")
        ),
        "/* SELECTION_ROUTING */": "@MainActor\n" + declaration(
            converter, "private func convertSelectionText("
        ).replace("private func", "func", 1),
        "/* DETECTOR_HELPERS */": "\n".join(
            declaration(detector, f"static func {name}(_ s: String) -> Bool")
            for name in ("isAllCaps", "hasInternalUppercase")
        ),
    }
    for marker, body in replacements.items():
        assert template.count(marker) == 1, f"Expected exactly one {marker}"
        template = template.replace(marker, body)
    (destination / "Boundary.swift").write_text(template)


if __name__ == "__main__":
    main()
