# MultiSwitcher

A native macOS menu-bar utility for correcting text typed in the wrong keyboard layout. MultiSwitcher is an independent fork based on [RuSwitcher](https://github.com/rashn/RuSwitcher), with its own name, bundle identifier, and icon.

## Status

MultiSwitcher is preparing its first public alpha. The source candidate is 0.3.2 (10); no signed, notarized end-user release has been published. Input integrity, hands-on compatibility on macOS 15/26/27, and update recovery remain release gates. See [Release readiness](RELEASE.md).

## Requirements

- Apple Silicon Mac (arm64)
- macOS 15 or newer
- Accessibility and Input Monitoring permissions for global keyboard monitoring

## Install

When Public Alpha 1 passes its gates and is manually published, download the MultiSwitcher DMG from the repository’s Releases page, drag the app to Applications, and launch it. Tagging a build creates a draft for review; it does not publish or deliver an update until the draft is manually promoted. The planned first alpha tag is `beta-v0.3.2-build10`; stable 1.0 will be a separate release. The website source is in `docs/`; a repository owner must enable GitHub Pages once.

The current source has a custom GitHub Releases update path, but it has not been verified end to end with a signed public release. Sparkle appcast migration is a remaining release gate. A commit or tag alone does not deliver updates. See [RELEASE.md](RELEASE.md) before relying on the updater.

## Build and checks

Requirements: macOS 15 or newer and Swift 6 Command Line Tools.

```sh
swift run --package-path macos MultiSwitcherCoreTests
bash macos/build_app.sh
```

A local arm64 build may use a development or ad-hoc signature; neither is suitable for public distribution. Public releases need an Apple Developer ID certificate, notarization credentials, and the GitHub release environment; see [RELEASE.md](RELEASE.md).

## Privacy

Text conversion runs locally. The release checker contacts GitHub to retrieve version metadata and the selected release asset; typed text and profile data are not included in update requests. Optional crash reports are disabled until the user explicitly opts in, and are available only in builds configured with the reporting service. Read [Privacy](PRIVACY.md), [Security reporting](SECURITY.md), and [Release readiness](RELEASE.md) before installing.

## Feedback

Use the repository's bug-report and feature-request forms. Bug reports request synthetic examples and warn against publishing private text or raw logs. The redacted diagnostic preview is editable; choosing to share copies the reviewed report and opens the GitHub issue form. It is never submitted automatically.

## Source and license

The original RuSwitcher code is available under the MIT License. Its license and attribution are included in the app bundle. See [LICENSE](LICENSE) and [TRADEMARKS.md](TRADEMARKS.md).
