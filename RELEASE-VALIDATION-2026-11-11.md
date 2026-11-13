# MultiSwitcher 0.4.2 (74) — 2026-11-11

Published https://sokolovmo.ru/multiswitcher/ from the actual working tree.
User explicitly authorized native UI corrections and publication for both apps.
Skills applied: apple-native-app-design and apple-design; native AppKit/UserNotifications
ownership takes precedence over the web styling recipes. Existing unrelated changes preserved.

## UI changes

- Removed custom notification panels, including the permission-denied fallback.
  Secure Input and generic learning feedback use UNUserNotificationCenter.
- Permission and submission failure status is available in settings and the status menu.
  Permission is requested only by the explicit test/configure action.
- Learning notifications contain generic text, never the typed word; queued feedback
  is serialized and coalesced. Secure Input episodes have individual cancellable IDs.
- NSAlert owns dialog backgrounds, button cells, layout and keyboard interaction.
  Clean embedded app artwork and Russian acknowledgement remain.
- Removed the tint layer over NSVisualEffectView, custom popup drawing, custom
  alert button cells and traversal/recoloring of Sparkle windows.
- Shared SwiftUI actions use native bordered/borderedProminent styles.

## Artifact and publication

- ZIP: MultiSwitcher-0.4.2-74-arm64.zip
- SHA256: 1b9fb68ad78d7ffa3f46ad83605c65a72106000862d2155eb30b1ebfdd908ede
- DMG SHA256: e0ed68dc5cac13e9428545c27c98a927bfd7d96f928534ef371f4933576119a6
- Target: /var/www/multiswitcher/releases/build-74-1b9fb68ad78d7ffa
- Previous: /var/www/multiswitcher/releases/build-73-a00cd320b82f341f
- Existing code-signing identity and Sparkle public key retained.
- Signed appcast includes specific RU/EN release notes; no key rotation.
- Public appcast and ZIP downloaded and verified, matching local bytes and installed
  SUPublicEDKey. Public page, source, installer, download counter and previous archives
  remain available. Existing reverse proxy unchanged; no service restarted.
- Not notarized; Apple Silicon / macOS 15+ as before.

## Verification

- Exact ZIP and mounted DMG: signatures, bundled resources and selftest passed.
- Core executable: 313 checks; selection conversion: 111 assertions.
- SecureInputChecks: native-only routing, denied/undetermined/error cases without
  overlays, cancellation/recovery, generic/coalesced feedback, 16 languages,
  real modal NSAlert/native button behavior passed.
- InteractionChecks: selection, deletion, focus, disclosures, resize, save failure,
  100 refreshes and theme actions passed.
- Exact release app: 100 real NSMenu state cycles passed.
- Distribution: 4 tests including actual signing and tampering rejection passed.
- Actual candidate was opened with an isolated profile and no keyboard monitor/updater.
  On macOS 27.2, real settings controls were inspected through computer-use screenshots.
  The native dialog AX tree exposed Russian «понятно» and the correct recovery text;
  its screenshot was blank, so visual dialog acceptance is NOT established.
- Test-notification action was invoked. The computer-use tool timed out accessing
  Notification Center/SystemUIServer; the actual MultiSwitcher system banner and
  permission prompt were not observed. No custom substitute was shown.
- Actual installed 0.4.1 (73) queried Sparkle and offered 0.4.2 with Russian notes
  and an enabled install button. Update dialog left open; install not pressed.

## Remaining acceptance

Real system banner appearance, clean-Mac installation, actual 73 -> 74 install/relaunch,
permission retention, physical typing, older macOS versions, and global accessibility
appearance settings are not established by the tests above. No owner acceptance claimed.

Evidence/artifacts: /private/tmp/multi-native-fix-20261111/ (temporary storage).

## Post-install verification

The owner subsequently reported installing both Sparkle updates and allowing
notifications. Rechecked /Applications/MultiSwitcher.app: 0.4.2 (74).
The running app's About view reports 0.4.2 (74), and Advanced settings reports
«системные уведомления разрешены». Accessibility/Input Monitoring readiness is
still shown as ready, and the previously observed trigger/layout/login-item
settings remain visible. This establishes the completed owner-operated update
and relaunch, not physical typing or visual system-banner acceptance.
