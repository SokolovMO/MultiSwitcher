# Shared monochrome UI correction — 2026-11-11

The owner requested consistent grayscale appearance in MultiSwitcher and MultiShift,
matching shared settings blocks, clearer diagnostics, and use of Apple design skills.
This continues the previously authorized fixes and independent Sparkle publication.
Unrelated existing working-tree edits were preserved; no blanket staging/reset.

## Causes and changes

- MultiShift lacked a packaged native AccentColor catalog and NSAccentColorName.
  Both apps now compile identical grayscale light/dark accent assets with actool.
- MultiShift's main Mach-O recorded SDK 14 despite being compiled with Xcode 27.2.
  The linker now records actual SDK 27.2 while retaining macOS 14 as its minimum.
  MultiSwitcher retains minimum macOS 15 and actual SDK 27.2.
- Both projects now vendor exactly the same MultiDesignKit.swift. SHA256:
  22e02cec2f55c79ca886366a10aaecd75420dac0c261766c277ce2800d8d5144
- DesignPalette (AppKit) and Mono (SwiftUI) refer to that canonical semantic palette.
  Shared AppKit-backed popups, preference actions, checkboxes and theme choices
  preserve standard menus, target/action routing, focus and accessibility semantics.
- Shared appearance and About/update groups use the same sections, labels, control
  sizes and version/build format. App-specific identity and functionality remain.
- Diagnostic word preview and logging are separate cards. The preview purpose is
  visible before input, the context field has a clearer label, and native text/editor
  backgrounds replace the previous gray editor fill. No correction algorithm changed.
- RU/EN signed release notes use the same system font and neutral underlined links.
- The purple screen-sharing indicator and normal macOS window controls belong to
  the OS. They are not repainted or removed.

## Skills and sources

Re-read the user-specified apple-native-app-design and apple-design; also applied the
installed swiftui-expert-skill and reviewed macos-design-guidelines found using
find-skills. Search evidence is in /private/tmp/multi-style-sync-20261111/skills-*.txt.
No global skill installation was necessary.

- Local native skill: /Users/sokolovmo/.codex/skills/apple-native-app-design/SKILL.md
- Local Apple principles: /Users/sokolovmo/.agents/skills/apple-design/SKILL.md
- SwiftUI Expert: https://skills.sh/avdlee/swiftui-agent-skill/swiftui-expert-skill
  Search reported 36.3K installs; source repository showed 3.9K stars.
- Apple Design: https://skills.sh/emilkowalski/skills/apple-design
  Search reported 287.4K installs; source repository showed 55.7K stars.
- macOS guidelines: https://github.com/ehmo/platform-design-skills/blob/main/skills/macos/SKILL.md
  Search reported 4.5K installs; source repository showed 639 stars.
  Applied relevant layout/focus/dark-mode guidance; the user's explicit grayscale
  preference takes precedence over its generic suggestion to follow a colored accent.
- Apple Color HIG: https://developer.apple.com/design/human-interface-guidelines/color
- Apple native accent declaration:
  https://developer.apple.com/documentation/bundleresources/information-property-list/nsaccentcolorname

## Validation and its limits

- Exact signed ZIP/DMG selftests, mounted-DMG checks and release signatures passed.
- SecureInputChecks passed: native-only routing, permissions/errors, cancellation,
  generic feedback, localization and real NSAlert behavior.
- InteractionChecks passed: selection, deletion, focus, disclosure reversal/resize,
  save failures, 100 refreshes and theme actions.
- MultiShift AppearanceChecks passed all 8 theme/reopen transitions.
- Distribution tests: MultiSwitcher 4 and MultiShift 5 passed, including real signing
  and tamper rejection; verified Sparkle tools used for both, no signature-test skips.
- Final MultiSwitcher binary passed 100 real NSMenu state cycles.
- Real candidate windows were inspected through computer-use screenshots on macOS
  27.2, in isolated profiles without keyboard monitors, updater creation or file work.
  Reviewed light/dark appearance, matching theme controls, About/update groups,
  checkbox target/action changes, native lists and diagnostics. Focused diagnostic
  input kept its native white background. A preview result rendered; this isolated
  review branch does not preload lexicons, so it is not word-recognition acceptance.
- Native-style reports from each exact app bundle confirm an AccentColor asset and
  equal R/G/B values: light 0.14, dark 0.88. Mach-O SDK metadata was independently
  checked. The final source archives contain the same shared UI file as the roots.
- Actual installed updaters offered the published versions with RU notes and enabled
  installation actions. The Switcher updater's neutral source link was visually checked.
- Public appcasts and ZIPs were downloaded and checked against local bytes, SHA256,
  Ed25519 signatures and the installed apps' unchanged public keys. Source/site/installer
  routes, counter endpoint and previous archives remain available. Main / stays 403.
- No reverse-proxy configuration was changed or service restarted.

The final releases are published but were not installed on the owner's Mac by the
agent. Installation dialogs were left open. Until relaunch, update windows still
belong to the previous running app and can retain its older accents. Notarization,
clean-Mac installation, older-OS screenshots, VoiceOver, global increased-contrast/
reduced-transparency settings, physical typing/file processing and owner visual
acceptance are not established by this UI correction. No Apple approval claimed.

Temporary evidence, before-edit backups and artifacts:
/private/tmp/multi-style-sync-20261111/

## MultiSwitcher publication

- Version/build: 0.4.3 (75)
- ZIP: MultiSwitcher-0.4.3-75-arm64.zip
- ZIP SHA256: ed94666f35fbb4a2a546eb5bffc8b82295fbe52304ab102ae4ef48acdf39aa16
- DMG SHA256: f11902ee82e0eb5279dc9e4073f545aca4319f3769bc690de41425991c6d32dc
- Current: /var/www/multiswitcher/releases/build-75-ed94666f35fbb4a2
- Previous: /var/www/multiswitcher/releases/build-74-1b9fb68ad78d7ffa
- Installed at verification: 0.4.2 (74)
- Notarized: false (existing distribution policy unchanged).
