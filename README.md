# MultiSwitcher

A native macOS menu-bar utility for correcting text typed in the wrong keyboard layout. MultiSwitcher is an independent fork based on [RuSwitcher](https://github.com/rashn/RuSwitcher), with its own name, bundle identifier, and icon.

## Status

MultiSwitcher is in public release preparation. There is no signed, notarized end-user release yet. The current source branch has automated core checks and an arm64 build, but live typing compatibility and the advertised macOS support matrix still need release testing. See [Release readiness](RELEASE.md).

## Requirements

- Apple Silicon Mac (arm64)
- macOS 15 or newer
- Accessibility and Input Monitoring permissions for global keyboard monitoring

## Install

Once a signed and notarized GitHub release is published, download the MultiSwitcher DMG from the repository’s Releases page, drag the app to Applications, and launch it. The app explains the required macOS permissions on first run. Tagging a build creates a draft for review; it does not publish or deliver an update until the draft is manually promoted.

When release updates are configured, MultiSwitcher checks GitHub Releases no more than once a day (this can be disabled in About) and offers a manual check from the menu-bar menu. The in-app update path is implemented but has not been verified end to end with a signed public release; see [RELEASE.md](RELEASE.md) before relying on it.

## Build and checks

Requirements: macOS 15 or newer and Swift 6 Command Line Tools.

```sh
swift run --package-path macos MultiSwitcherCoreTests
bash macos/build_app.sh
```

A local arm64 build may use a development or ad-hoc signature; neither is suitable for public distribution. Public releases need an Apple Developer ID certificate, notarization credentials, and the GitHub release environment; see [RELEASE.md](RELEASE.md).

## Privacy

Text conversion runs locally. The release checker contacts GitHub only to retrieve version metadata and the selected release asset; typed text and profile data are not included in update requests. Debug logs are not uploaded automatically. Read [Privacy](PRIVACY.md), [Security reporting](SECURITY.md), and [Release readiness](RELEASE.md) before installing.

## Feedback

Use the repository's bug-report and feature-request forms. Bug reports request synthetic examples and warn against publishing private text or raw logs. A sanitized diagnostic preview is available in Settings when you choose to share a report.

## Source and license

The original RuSwitcher code is available under the MIT License. Its license and attribution are included in the app bundle. See [LICENSE](LICENSE) and [TRADEMARKS.md](TRADEMARKS.md).
