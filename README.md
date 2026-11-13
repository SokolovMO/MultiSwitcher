# MultiSwitcher

A native macOS menu-bar utility for correcting text typed in the wrong keyboard layout. The project is developed and distributed as MultiSwitcher.

## Status

MultiSwitcher is preparing its first public alpha. Release readiness, signing requirements, and remaining validation gates are tracked in [Release readiness](RELEASE.md). Local development builds are not public releases.

## Requirements

- Apple Silicon Mac (arm64)
- macOS 15 or newer
- Accessibility and Input Monitoring permissions for global keyboard conversion

## macOS permissions

MultiSwitcher does not interrupt first launch with a permissions dialog or change macOS privacy settings in the background. When keyboard access is missing, **Check Permissions…** appears in the menu-bar menu and a status with **Setup Guide…** appears in General settings. The guide explains each permission before offering to open System Settings; **Later** is the default choice. You can leave either permission off and keep using the app and its settings, but automatic correction and the manual Option shortcut remain paused until both permissions are enabled.

The first path is **System Settings → Privacy & Security → Accessibility → MultiSwitcher** on macOS 15–26, and **System Settings → Privacy & Security → Device Control & Data Access → MultiSwitcher** on macOS 27. The second path is **System Settings → Privacy & Security → Input Monitoring → MultiSwitcher**. MultiSwitcher uses the first permission to work with text in supported fields and Input Monitoring to receive keyboard events for layout detection and shortcuts. If you enable both after choosing **Open Settings**, MultiSwitcher restarts once to apply keyboard monitoring. macOS remains in control of both switches.

macOS Secure Input can temporarily block both automatic and manual correction, even with both permissions enabled. MultiSwitcher checks this independently of keyboard events. The menu shows which app holds Secure Input; select that row for recovery instructions. A prolonged block sends a quiet native macOS notification with the app icon and a Details action. **Advanced → Test notification** requests notification permission when needed; it is never requested automatically during password entry. If permission is missing or delivery fails, the status remains visible in Advanced settings and the menu; no imitation desktop banner is shown. macOS controls banner appearance and Focus. Recovery removes the warning from Notification Center automatically. Leave the password field in the named app; if the block persists, quit that app completely and reopen it. Short password entry does not trigger the automatic notice. Learning and pause feedback use coalesced native notifications with generic text; typed words are never stored in Notification Center.

## Install

Download the drag-to-Applications DMG (or optional ZIP), or use the installation command at https://sokolovmo.ru/multiswitcher/ .
This independent distribution is not Apple-notarized; macOS may require allowing
the first launch in Privacy & Security. The installer checks the archive and app,
keeps the previous copy, and clears quarantine only on the verified MultiSwitcher.

Updates use embedded Sparkle with Ed25519-signed feeds and ZIP archives hosted on
our own server. Check manually in the menu or Settings → About, or leave automatic
checks enabled. Installation requires confirmation. No Apple Developer account,
GitHub App, Pages, or release dashboard is required. See [DISTRIBUTION.md](DISTRIBUTION.md).

## Build and checks

Requirements: macOS 15 or newer and Swift 6 Command Line Tools.

```sh
swift run --package-path macos MultiSwitcherCoreTests
bash macos/build_app.sh
```

With Command Line Tools alone, local builds fall back to the existing `.icns` when `actool` is unavailable. Builds with release integrations require full Xcode and the complete asset catalog. The native redesign review, real screenshots, checks and remaining validation limits are recorded in [the design review](design/review-2026-10-23/REPORT.md).

Public builds reuse the existing local MultiSwitcher Stable Code Signing certificate.
It is independent of Apple's paid developer program. Keep the signing key and the
separate Ed25519 seed backed up; changing the code-signing identity may affect macOS
privacy permissions. Physical installation and forward-update acceptance remain separate checks.

## Privacy

Text conversion runs locally. The release checker contacts sokolovmo.ru over HTTPS for the signed update feed and selected ZIP; typed text and profile data are not included in update requests. Optional crash reports are disabled until the user explicitly opts in, and are available only in builds configured with the reporting service. Read [Privacy](PRIVACY.md), [Security reporting](SECURITY.md), and [Release readiness](RELEASE.md) before installing.

## Feedback

Use the repository's bug-report and feature-request forms. Bug reports request synthetic examples and warn against publishing private text or raw logs. The redacted diagnostic preview is editable; choosing to share copies the reviewed report and opens the GitHub issue form. It is never submitted automatically.

## Source and license

The application code is available under the MIT License. Its license is included in the app bundle. See [LICENSE](LICENSE).
