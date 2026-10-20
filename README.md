# MultiSwitcher

A native macOS menu-bar utility for correcting text typed in the wrong keyboard layout. MultiSwitcher is an independent fork based on [RuSwitcher](https://github.com/rashn/RuSwitcher), with its own name, bundle identifier, and icon.

## Status

The app is under active development. Automated core checks and an arm64 app build are available in this repository. Application-field compatibility and the supported macOS release matrix still require manual validation before calling the project production-ready.

## Requirements

- Apple Silicon Mac (arm64)
- macOS 15 or newer
- Accessibility and Input Monitoring permissions for global keyboard monitoring

## Install

Once a signed and notarized GitHub release is published, download the MultiSwitcher DMG from the repository’s Releases page, drag the app to Applications, and launch it. The app explains the required macOS permissions on first run. Tagging a build creates a draft for review; it does not publish or deliver an update until the draft is manually promoted.

When release updates are configured, MultiSwitcher checks GitHub Releases no more than once a day (this can be disabled in About) and offers a manual check from the menu-bar menu. Updates are installed only after checking the download hash, bundle identity, Developer ID signature, and Gatekeeper assessment.

## Build and checks

Requirements: macOS 15 or newer and Swift 6 Command Line Tools.

```sh
swift run --package-path macos MultiSwitcherCoreTests
bash macos/build_app.sh
```

The local build is arm64 and signed with the configured local signing identity. A public release additionally needs an Apple Developer ID certificate, notarization credentials, and GitHub Actions secrets; see [RELEASE.md](RELEASE.md).

## Privacy

Text conversion runs locally. The release checker contacts GitHub only to retrieve version metadata and the selected release asset; typed text and profile data are not included in update requests. See [PRIVACY.md](PRIVACY.md) for local profile, diagnostics, permissions, and issue-reporting details.

## Feedback

Use the repository's bug-report and feature-request forms. Bug reports request synthetic examples and warn against publishing private text or raw logs. A sanitized diagnostic preview is available in Settings when you choose to share a report.

## Source and license

The original RuSwitcher code is available under the MIT License. Its license and attribution are included in the app bundle. See [LICENSE](LICENSE) and [TRADEMARKS.md](TRADEMARKS.md).
