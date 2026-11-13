# Homebrew and native updates — 2026-11-07

Published tap: https://github.com/SokolovMO/homebrew-apps (commit ba0eb01).
Final installed/public versions: MultiSwitcher 0.4.0 (72), MultiShift 0.3.0 (6).

- Both casks pin the actual immutable ZIP SHA256, include the build number in the
  version, require arm64 and the supported macOS minimum, and declare auto_updates.
- Homebrew 7 removed --no-quarantine. Explicit project-specific consent is
  HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED=1. Without consent, both test apps remained
  quarantined. With consent, structured postflight steps verified their code
  signatures and removed quarantine only from their respective app bundles.
  Homebrew filters other environment variables; the HOMEBREW_ prefix is required.
- Actual isolated Homebrew installs, reinstalls and upgrades passed: MultiSwitcher
  70→72 and MultiShift 4→6. Final executable hashes match the release archives and
  neither opt-in installation retains quarantine. Both final /Applications copies
  were then adopted by Homebrew without replacing their existing contents.
- Actual Sparkle checks, downloads, confirmed installation and relaunch passed:
  MultiSwitcher 70→71→72 and MultiShift 3→4→5→6. Installed executables match the
  verified archives, and deep/strict code-signature checks passed.
- MultiShift now declares ru/en host localizations, so the actual 5→6 offer,
  release notes, progress and Install and Relaunch button rendered in Russian.
- Fixed MultiSwitcher SUUpdateAlert/SUUpdatePermissionPrompt buttons using the
  same native-cell treatment as SUStatus. A regression failed before the fix and
  passed after it. Real Sparkle update-alert fixtures were visually reviewed in
  light/dark; dismissal routed correctly. The fixture creates no updater/download.
- MultiSwitcher profile remained byte-identical. MultiShift operations history
  remained semantically identical (JSON formatting can change). Preference diffs
  in both apps are limited to the Sparkle window frame and last-check timestamp.
- Four MultiSwitcher release tests, five MultiShift release tests, two cask tests,
  InteractionChecks and Homebrew style passed. Signed public feeds/manifests match
  the prepared release; downloaded ZIP SHA256 checks passed for both final builds.
- Existing Vyrex system nginx and active release paths were confirmed first.
  No proxy configuration/restart/reload occurred. All ten other route responses
  and the nginx configuration hash stayed unchanged; nginx configuration test passed.
- Evidence: design/homebrew-updates-2026-11-07/; detailed operational logs and profile
  backups: /tmp/multi-homebrew-qa/. Prior static releases remain on the server.

Scope: tested on this owner's Mac with Homebrew 7.0.11. These apps remain
unnotarized. This is not a clean-machine/all-supported-macOS certification or a
live active-conversion/update-overlap test. Native Sparkle remains the primary
update path; finish work and quit the app before an explicit Homebrew upgrade.

---

# Complete interface package — build 70, 2026-11-06

Published and installed: 0.4.0 (70). ZIP SHA256:
`a407998a704a0d0cc13e3483af2b02c6706b39ef148e883330ca1c6639832baf`.

- Eleven groups of interface issues fixed. Full scope, before/after evidence, exact
  test results and verification limits: design/interface-audit-2026-11-06/REPORT.md.
- Native search editor geometry fixed; real Sparkle native cell retained and RU/EN
  framework language verified using production release metadata. Selected-row text
  contrast, first-page styling, field labels, long values, columns and About fixed.
- 313 core checks, 111 selection assertions, interaction checks and six release
  tests passed. Structural after-matrix: 252 states; final palette matrix: 84 states;
  dense/empty profiles: 35 states each. No claim of every screenshot being independently
  examined or of complete VoiceOver/all-locale/all-OS acceptance.
- Final ZIP/DMG/code-signature/Ed25519/selftests passed. Source archive matched reviewed
  source. Public manifest/feed matched the prepared artifacts. Actual installed binary
  matched the release binary, startup handshake passed and profile remained byte-identical.
- Installed through the reviewed installer from build 68; the old app was retained.
  Real 68→70 Sparkle installation is not claimed; the real 67→68 test remains below.
  After launch both permissions stayed true and keyboard monitoring started.
- Other eight site-route responses unchanged; nginx configuration unchanged and valid;
  no proxy reload/restart. Previous static release 69 retained for rollback.

---

# Sparkle button appearance — build 69, 2026-11-06

Published 0.4.0 (69), ZIP SHA256:
`282e44df502755aff753d1e98dfaa4a09df3fc1910732671e2136f20c87e045b`.

- Sparkle SUStatus action uses the existing graphite dialog cell. It follows title,
  enabled state and Return key changes; target/action and control size are preserved.
  The native bezel/accent no longer mixes with a graphite text tint. Title drawing
  stays on one line with native-sized button padding.
- Real SPUStandardUserDriver ready-to-install UI was rendered with the production
  palette/cell in a separate preview without an updater or install operation. Light
  and dark images, including the complete Russian title, passed visual review. The
  original Sparkle action handler fired after activating the styled button.
- Interaction checks and all five release tests passed. Final ZIP/mounted-DMG
  selftests, signatures, installed-app signing requirement and signed-feed checks passed.
  The final archived DesignSystem.swift is byte-identical to the reviewed source.
- Production source changes since 68 are limited to DesignSystem.swift and build
  metadata. Published using the existing static deployment script without proxy changes.
- Preview evidence: /tmp/multiswitcher-updater-light.png,
  /tmp/multiswitcher-updater-dark.png, /tmp/multiswitcher-updater-preview.swift.
  Release evidence: /tmp/multiswitcher-release-build69-publish/ and
  /tmp/multiswitcher-build69-publish.log. Earlier local build-69 directories were
  unpublished intermediate artifacts and must not be used for deployment.
- Installed owner app remains build 68. A 68→69 update window is rendered by 68;
  the revised button is used by build 69 for subsequent update windows. No claim
  of an actual installed 68→69 Sparkle run is made in this change.

---

# Search fix and real Sparkle update — 2026-11-06

Published and installed: **0.4.0 (68)**, Apple Silicon, macOS 15+.
ZIP SHA256: `153017514c7ae1657478ec2f6312c6af4f46fb0beb6c68a6c1c3a624e5321343`.

- Fixed GraphiteSearchField: a replacement NSSearchFieldCell defaults to noneditable
  and nonselectable. Restore both properties; Rules and Learning share this control.
- Core: 313 checks; selected-text conversion: 111 assertions; all five release
  tests (including real signing and tampering); interaction focus/input checks passed.
- ZIP and mounted DMG selftests, code signatures, installed-app signing requirement,
  archive/feed Ed25519 signatures and 100 native NSMenu cycles passed for build 68.
- Baseline preparation: the prior installed build 64 had no Sparkle feed. The verified
  published installer installed build 67, retained build 64 at
  /Applications/.multiswitcher-previous-71012.app and confirmed successful startup.
- Actual forward update: in build 67, Settings → About → Technical information →
  Check for Updates displayed build 68. Sparkle downloaded, installed and relaunched
  build 68 through its own UI. Installed executable matches the release executable;
  deep/strict codesign verification passed with normal keychain access.
- After update, Rules search received pointer focus; entering apple through paste
  filtered the table to the two matching rules. No rules were edited or removed.
- Profile remained byte-for-byte identical across baseline installation and Sparkle
  update; rules and learning also compared equal. Startup logs confirm accessibility
  and inputMonitoring true, enabled event tap and successful monitoring.
- Public manifest/feed equal the prepared release. Nine prior route responses were
  unchanged. nginx configuration checksum is unchanged and nginx -t passed; no reload
  or restart was performed. previous retains site-67-9aa24a3900098458.
- Evidence: /tmp/multiswitcher-update-test68/, /tmp/multiswitcher-build68.log,
  /tmp/multiswitcher-release-build68/, /private/tmp/multiswitcher-native-menu.Ybj7SL/.
- Physical cross-app keyboard conversion, exact clipboard behavior during a live
  conversion/update overlap, and the full supported-OS matrix remain unverified.

---

# Release validation — 2026-11-06

Published: https://sokolovmo.ru/multiswitcher/ . Current 0.4.0 (66), arm64,
minimum macOS 15. ZIP SHA256:
`ee9204890a44a59509b7a22ff7cf35f4fb7d70cdf12f25c594b169d43a4c8c74`.

- Core: 313 checks passed. Selected text: 109 assertions passed.
- Interaction checks passed after removing the legacy renderer from the target.
- Five release tests passed, including real Sparkle signing and tamper rejection.
- Built with the existing MultiSwitcher Stable Code Signing certificate. The new
  ZIP-extracted app matches the installed app's designated signing requirement.
- Hardened runtime remains enabled. Owner explicitly approved on 2026-11-06 only
  disable-library-validation for independent Sparkle builds; separate entitlements
  are selected by MULTISWITCHER_INDEPENDENT_DISTRIBUTION=1.
- ZIP extraction, deep/strict code signature verification, dictionary/updater
  selftest, ZIP Ed25519 signature and signed-feed verification passed.
- Public install.sh --verify-only downloaded and checked build 66 without writing
  /Applications. Public feed signature and metadata bytes match the prepared build.
- The actual configured release binary passed 100 native NSMenu state cycles,
  update-action presence and page transitions. Light/dark native menu captures
  succeeded through WindowServer; tracking ended correctly. Evidence:
  /private/tmp/multiswitcher-native-menu.y6YLlj/profile/native-results.json .
- StatusPopoverController, MultiPopoverView and MultiPopoverRow symbols are absent
  from the release executable. Their source and historical tests are in legacy-ui,
  outside the application target. All UI audit paths now use NSMenu as well.
- An earlier build-65 UI screenshot audit opened the legacy custom popover on the
  owner's desktop. That temporary process was closed. Its legacy learning fixture
  reported FAIL; this is not counted as full Learning-page acceptance. Current
  targeted interaction checks pass. No claim of full UI/physical-input acceptance.
- Page tested at 1440/768/390px. No video/decorative motion on this install sheet.
- Existing nginx on Vyrex was inspected and backed up at
  /var/backups/multiswitcher/20261106T031345Z/nginx-sokolovmo.ru . Only
  /multiswitcher/ was added, nginx -t passed before/after and nginx was reloaded.
  Sixteen prior routes, including MultiShift and its feed, kept status/body hashes.
- Build 66 publication changed only the atomic current symlink, without nginx reload.
  Previous build 65 archives/source are retained. New release directory:
  /var/www/multiswitcher/releases/build-66-ee9204890a44a595 .
- The installed /Applications/MultiSwitcher.app stays at build 64. Its working
  process was not replaced or stopped. Temporary audit instances were closed.
- Full pre-change project backup, including Git and dirty files:
  /tmp/MultiSwitcher-before-independent-20261106.tar.gz . Four untouched pre-existing
  dirty source/test files were compared byte-for-byte against it and preserved.
  SettingsWindowController was edited only for the update section; prior UI edits
  were retained. Source changes are uncommitted.

Not certified: a complete /Applications installation, installer startup handshake,
actual forward Sparkle A→B install/relaunch, permission/profile preservation across
that update, physical keyboard/clipboard cross-app acceptance and every supported OS.

Local logs: /tmp/multiswitcher-public-build66.log,
/tmp/multiswitcher-native66-menu.log, /tmp/multiswitcher-native66-interactions.log,
/tmp/multiswitcher-independent-core.log, /tmp/multiswitcher-independent-selection.log.
