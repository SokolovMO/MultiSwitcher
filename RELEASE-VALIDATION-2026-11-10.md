# MultiSwitcher 0.4.1 (73) — 2026-11-10

Published to https://sokolovmo.ru/multiswitcher/ using the existing independent
Sparkle distribution. Built from the actual working tree, including local changes.
No automatic installation was performed on the owner's Mac.

Changes: independent Secure Input observer, native macOS warning with a details
action and a branded fallback panel, concise feedback, clean in-app icon without
external shadow/outline, and Russian «Понятно» acknowledgement.

## Artifacts and continuity

- ZIP: `MultiSwitcher-0.4.1-73-arm64.zip`
- ZIP SHA256: `a00cd320b82f341f6a2f2fa38681f0288ceb891f1f277329fe35a8f391903cff`
- DMG: `MultiSwitcher-0.4.1-73-arm64.dmg`
- DMG SHA256: `1f26e9fee803658e0a86e12423c5c683dda3b27021f165ddebd789e6d0334b43`
- Version/build: 0.4.1 / 73; Apple Silicon, macOS 15+.
- Existing stable code-signing identity and Ed25519 key retained. The builder
  verified the app against the designated requirement of installed build 72.
- ZIP, DMG and appcast signatures verified. ZIP extraction, mounted DMG code
  signature and selftest passed.
- Publication target: `/var/www/multiswitcher/releases/build-73-a00cd320b82f341f`.
  Previous target retained: `/var/www/multiswitcher/releases/site-72-f4ea65af671b1ece`.
- Existing nginx location uses `alias /var/www/multiswitcher/current/`.
  No proxy config change or service restart was performed.

## Validation

- Core executable: 313 checks passed.
- Core XCTest: 23 tests passed.
- Selection conversion: 111 assertions passed.
- Interaction checks passed (focus, selection, deletion, disclosure, refresh/theme).
- Secure Input/notification checks passed: independent observer, delivery gateway,
  explicit permission flow, fallback, details action, cancellation race, cleanup,
  icon, focus, animation interruption, 16 languages and 12 feedback variants.
- Distribution tests: 4 passed, including actual signatures and tampering rejection.
- Manifest tests: 2 passed.
- Signed release binary extracted from ZIP: 100 native NSMenu state cycles passed.
- Installed build 72 performed a real manual Sparkle check and displayed 0.4.1
  with Russian release notes and the enabled «Установить обновление» action.
  The install action was not pressed; the update window was left open.

## Acceptance limits

The update is offered by the actual installed updater. The real 72 -> 73
installation/relaunch, TCC retention, new Notification Center banner delivery,
and physical typing acceptance remain to be exercised after the owner installs.
The notification gateway checks use an isolated test implementation; app feedback
panels are rendered through actual AppKit. No new notarization is claimed.

Build/check logs and artifact copies are under `/private/tmp/multi-release-73-*`,
`/private/tmp/multiswitcher-release-0.4.1-73`, and
`/private/tmp/multiswitcher-release73-public-verification` (temporary storage).
