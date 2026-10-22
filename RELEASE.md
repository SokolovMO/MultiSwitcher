# Public Alpha 1 readiness

Last verified locally: 2026-10-23. This document describes source preparation, not a published release.

## Release state

**Do not publish Public Alpha 1 yet.** `/Applications/MultiSwitcher.app` is freshly launched from Finder as **0.3.11 (52), arm64, ad-hoc signed**. Its executable SHA-256 is `a4da1644cc51d1b4f4d34ade1d2cc023c800fe8696945294f8f6da26e18b7a53`; the app's About page reports `v0.3.11`. The Learning and Rules pages were visually checked in the current large full-screen layout: the Learning card top edge is no longer clipped, and the help text/table fit inside the card; the Rules table remains inside its card. Minimum-size, manual-resize, light/dark mode, and Reduce Motion checks remain open. Accessibility and Input Monitoring remain off by the user's choice; keyboard conversion is therefore paused and has not been input-tested on this build. The optional permission guide explains each permission and that **Later** leaves keyboard features paused; MultiSwitcher does not change macOS privacy settings. Build 52 source checks and hosted CI status are recorded below; CI for the new commit is pending until it is pushed.

Release infrastructure was checked on 2026-10-22: the local keychain has **zero valid code-signing identities**, the repository has **no `multiswitcher-release` GitHub environment**, and the GitHub Pages API returns 404, so the public site is not enabled. The signed-release workflow therefore cannot produce a public build yet. No signing, notarization, Sparkle, or Sentry secret values were inspected or exposed. Trusted Developer ID signing and notarization, a protected release environment, Sparkle keys, and Pages setup remain prerequisites.

Required hands-on checks on **each macOS 15, 26, and 27** before alpha publication:

- Install, present the new optional permission guide, open permissions only after an explicit user action, remove/regrant permissions manually, launch at login, sleep/wake, and quit.
- Confirm automatic correction, Option conversion and exact undo, fast typing, edits, secure input, and no damage to neighboring text in TextEdit, Spotlight, Codex, Cursor, Safari, and agreed supported apps.
- Exercise profile import, backup, restore, learning, and update-preserved profile on a clean user account.
- Measure idle/active CPU, memory, and input latency.
- Verify Developer ID signature, notarization, Gatekeeper, fresh install, update from the prior signed build, and rollback.
- Verify crash-report opt-in/revocation, exact sanitized payload, IP handling/retention, and dSYM symbolication before enabling reporting in a public build.

Historical Build 47 checks passed on Xcode 27.1: the app target compiled, 300 core checks passed, 99 selected-text conversion assertions passed, and 13 XCTest reliability tests passed. For current Build 52, the app target compiles, **306 core checks pass**, and the arm64 installed bundle passes plist, architecture, and `codesign --verify --deep --strict` checks. Its executable hash is recorded above. It is ad-hoc signed, has no dSYM, and is built without Sparkle or crash reporting. Build 52 is freshly launched and its Learning and Rules pages were visually checked at the current large full-screen size. Accessibility and Input Monitoring remain off, so live conversion is paused and unverified. Manual edge-drag resize, small-window/minimum-size, light/dark, and Reduce Motion checks remain open. Short Activity Monitor snapshots from earlier builds are not performance benchmarks. No 30-run input matrix, trusted signed/notarized install, updater-forward test, or rollback test is complete.

The local review bundle used `-debug-info-format none` because this constrained environment blocks SwiftPM's in-build `dsymutil` task with `Operation not permitted`; a separate manual `dsymutil` invocation succeeds. Public and crash-reporting builds must keep the default DWARF setting, upload symbol files, and pass CI on the hosted macOS runner. That configured crash-reporting build has not been verified here.

## Public Alpha 1 scope

- Keep the existing **beta/test channel**. Public Alpha 1 is a release label on that channel, not a third updater channel.
- Use a prerelease tag such as `beta-v<version>-build<build>` after version/build metadata is reviewed and code is merged to `main`.
- Keep the GitHub release as a draft while validating the signed DMG. Publish manually only after every alpha gate above passes.
- Do not call the build `1.0`. Stable 1.0 is a separate release after alpha feedback and open text-integrity issues are resolved.
- Do not claim compatibility with an OS version until hands-on testing is recorded.

## Current distribution mechanism and migration gate

Sparkle 2.10.0 is pinned in `macos/Package.swift`. Distribution builds embed the matching framework and configure EdDSA feed and archive verification. The release workflow uses the same signed feed for stable and beta builds, validates the generated XML and signatures, creates a draft, then waits for manual publication. Every Pages deployment restores the signed `appcast.xml` from the newest published release; the release-triggered copy retries briefly while GitHub makes its asset available. The Sparkle branch compiles in hosted CI; a persistent private key and clean notarized install/update/rollback test are still required before distribution.

The GitHub Pages workflow deploys `docs/` from `main`. A repository owner must enable **Settings → Pages → Build and deployment → GitHub Actions** once. The page discovers the latest published arm64 DMG; draft releases remain unavailable to visitors.

## One-time release configuration

Create the protected GitHub Actions environment `multiswitcher-release`; require a reviewer and permit only reviewed release tags. Keep secrets environment-scoped.

Required for signed release workflow:

- `APPLE_DEVELOPER_CERTIFICATE_P12_BASE64`
- `APPLE_DEVELOPER_CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `MULTISWITCHER_DEVELOPER_TEAM_ID` variable
- `MULTISWITCHER_DEVELOPER_ID_SIGNING_IDENTITY` variable

Crash reporting is optional. Leave all four values empty to produce a build with crash reporting unavailable. If enabled, configure all four; partial configuration is rejected:

- `MULTISWITCHER_SENTRY_DSN` variable
- `MULTISWITCHER_SENTRY_ORG_SLUG` and `MULTISWITCHER_SENTRY_PROJECT_SLUG` variables
- `MULTISWITCHER_SENTRY_AUTH_TOKEN` secret with only debug-symbol upload permission

Required Sparkle updater configuration:

- generate one persistent EdDSA key pair with Sparkle's `generate_keys` tool;
- set its base64 public key as `MULTISWITCHER_SPARKLE_PUBLIC_KEY`;
- export the private key once to a local file with Sparkle's `generate_keys -x <file>`, base64-encode that file locally, and store the result as `MULTISWITCHER_SPARKLE_PRIVATE_KEY_BASE64` in the protected release environment;
- never print the private key or put its raw file in the repository, a build artifact, or workflow output. The workflow decodes it only into the appcast generator's standard input.

Never place signing certificates, private keys, passwords, API tokens, user profiles, or Punto data in the repository, workflow output, website, issue, or chat. The source workflow cannot configure repository rules, required reviewers, Pages settings, Apple Developer enrollment, or Sentry retention/IP scrubbing.

## Release procedure

1. Merge reviewed code to `main`; require passing macOS 15 and 26 CI jobs, and review the macOS 27 `xcode-27` preview job.
2. Confirm the matching hands-on test logs for macOS 15, 26, and 27 and review known limitations.
3. Increment `CFBundleVersion`; keep the first public release below 1.0.
4. Create `beta-v<version>-build<build>` pointing to the reviewed `main` commit. The workflow verifies the tag and creates a draft prerelease with the signed DMG and manifest.
5. Install that exact signed build on a clean Apple Silicon account. Verify signature, notarization, permissions, profile preservation, and a forward update from the preceding signed build; exercise rollback.
6. Verify the download page finds the published asset after it is manually published. Confirm crash-report configuration and privacy disclosures match the actual payload.
7. Publish the draft manually. A Git commit or tag alone does not distribute an update; a published, signed release and working updater are required.

## Data, reports, and support

Conversion and bundled dictionaries run locally. Update checks send ordinary network metadata to GitHub, not typed text or profile data. Crash reports are disabled by default and initialize only after explicit consent in configured builds. Revoking consent closes the reporter and rejects events with a timestamp at or before revocation; an event with no timestamp is rejected when a revocation date exists.

Debug logs are off by default. The support action redacts common paths, app IDs, sensitive key/value fields, URLs, emails, IP addresses, and common token formats; the preview is editable and redacted again after edits. Only after the user chooses to share does the app copy the report and open the GitHub issue form. Nothing is submitted automatically. Redaction is defense in depth, not a guarantee; the user must review the final report.

## Stable 1.0 gate

In addition to the alpha checks, 1.0 requires a public support page and tested update/rollback channel, completed appcast migration or an explicitly reviewed updater decision, no open text/clipboard/learning corruption issues, documented compatibility, accessibility review, and measured resource targets. Public feedback should be triaged and fixes released through reviewed commits and signed builds. There is no response-time commitment.

## Current source revision: 0.3.11 (52), installed for local validation; hosted CI pending

- Build 52 fixes the Learning page card clipping by explicitly measuring top-aligned content and fitting its table/help region within the card. Rules retains a measured 12 pt vertical inset. Six layout-policy regressions raise the Core suite to 306 passing checks.
- The fresh Finder launch confirms the installed bundle is Build 52; the About page reports 0.3.11. Learning and Rules were inspected at the current large full-screen size. Minimum-size, manual resize, light/dark appearance, and Reduce Motion remain unverified.
- Build 52 was compiled ad-hoc and installed at `/Applications/MultiSwitcher.app`. CI for the current source commit must run after pushing.

## Historical Build 47 validation

- Build 47 fixes a settings remeasurement gap: the scroll viewport width is propagated before reading wrapped-card fit sizes, dynamic permission and example result text schedules a fresh measurement, and the document height accounts for its viewport and all settings pages. Debug builds record card-frame collisions without user text.
- A later screenshot reopened the General-page top-margin/card-boundary issue after the earlier Build 46 pass. Build 47 was installed and the screenshot state was visually checked; that overlap is not present at the current large window size. Small-window and manual-resize coverage remains open.

- Build 46 moves initial and page-change scrolling to the next main-loop turn after the window, selected tab, and scroll document finish layout. Settings forms remain centered and capped at 980 points on large displays, while using available width on smaller windows. Build 47's installed screenshot check closes the latest large-window regression only.
- Build 46 clarifies the English and Russian permission guide: it explains each permission's concrete role, lets users choose **Later**, and states that text correction runs locally. No permissions are changed by the app. The installed candidate's code bundle is verified; all three CI jobs passed for PR commit `1d3d259`.

- Build 45 adds adaptive remeasurement of constraint-based settings cards when the window or sidebar changes size, updates the document height and preserves the scroll position. The installed General page was visually checked at its initial and zoomed sizes; manual resize and minimum-width/minimum-height checks remain required.
- Build 45 removes the launch-time permission dialog. The status stays visible in General settings, and the menu offers a permission check only when access is missing. The guide appears after an explicit click, explains that both automatic and Option conversion need keyboard access, and defaults to **Later**. UI verification confirmed that choosing **Later** closes the guide without opening System Settings. No TCC permission was changed.
- Build 45 is installed at `/Applications/MultiSwitcher.app` as an arm64 local build with an ad-hoc signature. Its executable hash matches the verified candidate, the profile was preserved, and duplicate temporary bundles were removed. Automatic and Option input were not validated because the current Accessibility and Input Monitoring states are both off by the user's choice.
- The CI matrix now also targets the `xcode-27` public-preview runner for macOS 27. The official runner image is preview software; its CI result is supplemental and does not certify release support or replace hands-on testing.

- Build 44 corrected the settings document's initial height and scroll position and added the current macOS 27 “Device Control & Data Access” label with legacy paths for macOS 15–26. Build 45 extends its behavior for resize-driven wrapping and uses a user-opened permission guide.

- Adds a persisted threshold for automatic layout transitions: switch after one confirmed word or two consecutive confirmed words. Two remains the default, and the selection is captured with each word-boundary snapshot.
- Stores bundled word lists as sorted flat arrays and uses binary search instead of `Set<String>` to reduce dictionary lookup memory. The 80 MB resident-memory target has not yet been measured against the installed app.
- Uses clearer monochrome card edges, more visible graphite selection, and a consistent 12/16 pt card-spacing scale. Exception-list containers now have a fixed intrinsic height and vertical compression resistance to stop the overlap recorded in the supplied layout audit. Source compilation passes; live visual checks for light/dark appearance, small window sizes, VoiceOver, and keyboard navigation remain open.
- Allows a pending automatic replacement to recover a typed suffix only if the captured input is still an exact prefix and the number of fresh key events matches the generation change. It rejects stale text, count mismatches, composed characters, empty suffixes, and oversized recovery. If an input event contains multi-character, composed, unsafe, or truncated Unicode, the keyboard monitor invalidates its word snapshot before conversion can use physical-key guesses. This source-level protection still needs live typing validation.
- Keeps verbose logging off by default and explains the opt-in setting. Upgrades preserve each user's saved debug-log preference.
- Core checks: 298 passed. XCTest reliability suite: 13 passed. Selection conversion checks: 99 passed. These are deterministic source-level checks, not live keyboard validation. The selection harness also reported AppleSpell/XPC unavailable; its packaged local dictionaries still passed.
- Build 37 adds privacy-safe operation IDs and queue-depth/capacity diagnostics across buffer and Accessibility replacement, distinguishes queue refusal, process change, stale context, and adapter rejection, and standardizes settings-control spacing. Its local arm64 bundle passed plist, architecture, lexicon, and code-bundle verification. It has an ad-hoc signature and no DWARF; crash reporting is disabled.
- Build 38 narrows automatic-rule cache invalidation to actual conversion-rule changes, avoids a second rule lookup inside the automatic detector, lays out the rule-editor toolbar in three adaptive Auto Layout rows, and adds coverage for rule revisions and duplicate rule evaluation. The 0.3.8 (38) bundle passes plist, arm64, resource, and code-bundle integrity checks; it remains ad-hoc signed and uninstalled.
- Build 39 prepares the compiled automatic-rule snapshot on a utility queue before keyboard monitoring starts. It adds regression cases for `want djn ctqxfc → want вот сейчас` and for mixed Russian/English phrases.
- Build 40 also prewarms the snapshot after profile rule changes and legacy-rule changes. That keeps both startup and edited rules away from the first subsequent word-boundary callback. The build is ad-hoc signed and remains uninstalled pending a trusted signature and live-input verification.
- Build 41 shortens settings navigation to a 70 ms fade to 84% opacity and a 90 ms fade-in, both eased out. The existing generation guard and Reduce Motion instant transition remain; the 220 ms expand/restore animation is unchanged. Source-level verification passes, but the feel check still needs a live window.
- Build 42 adds a temporary auto-conversion example checker to Advanced settings. It uses the automatic detector, current rules/dictionaries and context threshold, shows predicted text and next layout separately, and suppresses decision logging for the preview. Examples stay in the open settings view and are not persisted. Live layout and small-window visual checks remain required.
- No signing identity, notarized build, reliable Instruments trace, measured CPU baseline, or live multi-app test matrix is available in this workspace yet.

## Historical notes from a prior local reliability candidate: 0.3.4 (27)

- Adds reviewed technical, interface-design, brand, and slang entries as separate local lexicon packs; slang is used to preserve valid forms rather than normalize them.
- Uses the actual selection converter for mixed RU/EN regression cases and keeps ambiguous two-letter fragments unchanged until context is strong enough.
- Tracks the exact direction of copy/paste conversion toggles so only a confirmed return to the original text can count as one manual-learning cycle. Two cycles create a review candidate; confirmation is still explicit.
- Serializes automatic Accessibility edits, manual Option edits, exact undo, and injected-buffer replacements through one bounded FIFO. A queued edit is revalidated against the captured process and input context before it starts; changed or unsupported fields are left untouched.
- Routes terminal whole-line conversion through that same FIFO. A committed buffer replacement now records its exact converted/undone direction and operation ID, so automatic undo evidence cannot silently miss the first return-to-source toggle.
- Keeps learning and layout updates behind the confirmed replacement completion, and avoids a false learning event when an Option operation fails or its snapshot became stale.
- Refreshes the open Learning table when a candidate or automatic cancellation changes the profile.
- Keeps new manual Option learning candidates above imported Punto history, labels imported history distinctly, and explains that a candidate requires a deliberate confirmation before it becomes an exception.
- Allows queued repeat Option toggles to continue only when the prior successful toggle advanced the field generation for the same operation and no physical input, app, or context changed; this prevents fast intentional toggles from being discarded as stale.
- Checks the active process on TextConverter's main actor instead of reading `NSWorkspace.frontmostApplication` from the injection queue. An application-activation notification also invalidates pending word-boundary snapshots; this addresses logged automatic conversions that were being cancelled before insertion. Live validation in the installed app is still required.
- Restores the Settings window's last size and position. ⌘W closes Settings while leaving the menu-bar app running; ⌘Q quits the app. Live smoke checks previously confirmed both behaviors; they were not repeated on build 26.
- Keeps imported Punto training history separate from new local evidence.
- Build 27 compiled for arm64 and passed bundle-integrity verification. The 241 Core checks passed against its source; the 85 deterministic actual-source conversion assertions and 3 appcast-validator checks are historical results. These checks do not replace physical keyboard input, Accessibility replacement tests, or the 30-run app matrix.
- Sparkle 2.10.0 is pinned for release builds, its framework is embedded in the app bundle, and the signed appcast validator checks the current version, channel, download URL, archive signature, and signed-feed trailer.
- Crash reporting stays disabled when the four Sentry configuration values are all absent; the release workflow rejects partial configuration.
