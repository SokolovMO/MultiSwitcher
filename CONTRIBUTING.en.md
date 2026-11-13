<p align="right"><a href="CONTRIBUTING.md">Русский</a> · <b>English</b></p>

# Contributing to MultiSwitcher

Thank you for helping improve Russian and English typing on macOS.
Issues and pull requests in **Russian or English** are welcome.

## Start with the problem

Search [existing issues](https://github.com/SokolovMO/MultiSwitcher/issues) first.
Use the bug or feature form and keep each report focused on one problem.
For a large change, open an issue before implementation so scope can be discussed.
Use synthetic text, a minimal reproduction, and the app version/build and macOS version.
See [SUPPORT.md](SUPPORT.en.md) for troubleshooting and [SECURITY.md](SECURITY.en.md)
for private vulnerability reporting.

## Set up locally

Use an Apple Silicon Mac with macOS 15+ and Swift 6 Command Line Tools.
Full Xcode is needed for release integrations and the complete asset catalog.

```sh
git clone https://github.com/SokolovMO/MultiSwitcher.git
cd MultiSwitcher
git switch -c fix/describe-the-change
swift run --package-path macos MultiSwitcherCoreTests
bash macos/build_app.sh
```

## Where things live

- `macos/Sources/MultiSwitcher/` — AppKit interface, keyboard monitoring, and app integration.
- `macos/Sources/MultiSwitcherCore/` — correction policies, profiles, rules, and local storage.
- `macos/Tests/` — core tests and native interaction checks.
- `dicts/` — dictionary packs and their licensing; `dicts/themes/` contains thematic lists.
- `scripts/` — validation and distribution tools.
- `design/` — interface review evidence; `legacy-ui/` preserves the previous interface.
- `homebrew-tap/` — cask source and update tooling.

## Keep changes focused

Use existing components and system-owned macOS controls. Keep Russian and English
copy in sync. Follow the surrounding Swift style, preserve unrelated edits, and
avoid new dependencies unless the problem requires them.

Keyboard replacement code must preserve undo behavior, clipboard restoration,
secure-input handling, permission boundaries, and per-app exclusions. Keep
synthetic examples in regressions; never add real typed text or profile data.

## Validate what changed

Run the core checks for a behavior change:

```sh
swift run --package-path macos MultiSwitcherCoreTests
swift test --package-path macos
```

For selected-text conversion and app integration, also run:

```sh
bash scripts/check_selection_conversion.sh
bash macos/build_app.sh
```

For UI changes, attach light/dark screenshots with synthetic data and describe
keyboard and resize checks. Some interaction checks require a logged-in macOS
session and granted permissions. A green build does not prove physical typing,
clean-Mac installation, accessibility, or update acceptance.

Documentation-only changes need working links and a visual check of the rendered
Markdown; they do not need a full app rebuild.

## Send a pull request

Describe the user-visible problem, the resulting behavior, and how you checked it.
Keep the diff small enough to review. Use a short descriptive commit subject
(for example, `fix: restore clipboard after conversion`). The maintainer reviews
and decides when to merge.

Do not commit signing certificates, private keys, tokens, `.env` files, personal
profiles, raw diagnostic logs, or build output. Keep original license notices.
Follow the [Code of Conduct](CODE_OF_CONDUCT.en.md).
