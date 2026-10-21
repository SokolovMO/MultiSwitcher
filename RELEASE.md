# Public Alpha 1 readiness

Last verified: 2026-10-21. This document describes source preparation, not a published release.

## Release state

**Do not publish Public Alpha 1 yet.** The GitHub release list has no public app release. The project source is in draft PR #2 and is not a published installer. Local source metadata is now 0.3.3 (22). The current login keychain reports no code-signing identities; the installed build's strict signature verification returns `CSSMERR_TP_NOT_TRUSTED`. There is no Developer ID certificate or notarization credential available in this environment. The Sparkle 2.10 arm64 app target now compiles with the pinned binary artifact, but a Developer ID-signed bundle and notarized update have not been built or tested end to end.

Required hands-on checks on **each macOS 15, 26, and 27** before alpha publication:

- Install, request permissions, remove/regrant permissions manually, launch at login, sleep/wake, and quit.
- Confirm automatic correction, Option conversion and exact undo, fast typing, edits, secure input, and no damage to neighboring text in TextEdit, Spotlight, Codex, Cursor, Safari, and agreed supported apps.
- Exercise profile import, backup, restore, learning, and update-preserved profile on a clean user account.
- Measure idle/active CPU, memory, and input latency.
- Verify Developer ID signature, notarization, Gatekeeper, fresh install, update from the prior signed build, and rollback.
- Verify crash-report opt-in/revocation, exact sanitized payload, IP handling/retention, and dSYM symbolication before enabling reporting in a public build.

CI compilation on macOS 15/26 and core checks do not substitute for live input on those systems. On the current macOS 27.0.1 Mac, 241 core checks and 85 actual-source automatic/selection conversion assertions pass; the Sparkle appcast validator also passes its 3 checks, and the pinned Sparkle 2.10 arm64 app target compiles. Build 0.3.3 (18) remains installed at `/Applications/MultiSwitcher.app`; strict signature verification reports `CSSMERR_TP_NOT_TRUSTED`, and the login keychain currently has no valid signing identity. Temporary builds use an ad-hoc signature and are not installed because a different signing identity could reset macOS input permissions. Build 22 compiled for arm64 and passed the build script's bundle-integrity check. Its macOS permission warning was dismissed with “Later” without changing settings. The temporary build's live UI smoke test confirmed ⌘W closes Settings and reopening that bundle shows Settings again; ⌘Q closes its UI. On the installed build 18, CUA confirmed ⌘W closes Settings while MultiSwitcher remains running, then ⌘Q removes it from the running-app inventory. I relaunched the installed app and left it running in the menu bar after ⌘W. Source routes W through `NSWindow.close()` and Q through the normal cleanup and terminate path. No TCC permissions were changed. The retained 0.3.2 (10) rollback copy also fails strict signature trust verification; keep it as recovery material, but do not count rollback as verified until the signing identity/trust issue is resolved. Updater and crash reporting are disabled in the installed review build, and it has no dSYM. The profile migrated from schema 1 to 2 on first launch: all 20 learning rows remain, and the 19 imported cancellation counts were preserved in the separate imported-history field. Profile snapshots before and after migration are stored under `~/Library/Application Support/MultiSwitcher/backups/20261021-0.3.3-build18/`; profile snapshot checksums match their sources. After debug logging was turned off, matching profile and preferences snapshots were added under `schema2-after-debug-disabled/`; the debug preference is `false`, and both copied file hashes match the live files. One process snapshot showed 0.0% CPU and 78,384 KB resident memory; another, with Settings open, showed 106,752 KB. These are point-in-time readings, not sustained performance results. The conversion checks use real bundled dictionaries, the production automatic detector, and native RU/US keyboard maps with in-memory settings; they do not prove standalone Option event delivery or text replacement in Telegram. Automated tests do not replace physical keyboard input or the 30-run app matrix.

The local review bundle used `-debug-info-format none` because this constrained environment blocks SwiftPM's in-build `dsymutil` task with `Operation not permitted`; a separate manual `dsymutil` invocation succeeds. Public and crash-reporting builds must keep the default DWARF setting, upload symbol files, and pass CI on the hosted macOS runner. That configured crash-reporting build has not been verified here.

## Public Alpha 1 scope

- Keep the existing **beta/test channel**. Public Alpha 1 is a release label on that channel, not a third updater channel.
- Use a prerelease tag such as `beta-v0.3.3-build22` after version/build metadata is reviewed and code is merged to `main`.
- Keep the GitHub release as a draft while validating the signed DMG. Publish manually only after every alpha gate above passes.
- Do not call the build `1.0`. Stable 1.0 is a separate release after alpha feedback and open text-integrity issues are resolved.
- Do not claim compatibility with an OS version until hands-on testing is recorded.

## Current distribution mechanism and migration gate

Sparkle 2.10.0 is pinned in `macos/Package.swift`. Distribution builds embed the matching framework and configure EdDSA feed and archive verification. The release workflow uses the same signed feed for stable and beta builds, validates the generated XML and signatures, creates a draft, then waits for manual publication. Every Pages deployment restores the signed `appcast.xml` from the newest published release; the release-triggered copy retries briefly while GitHub makes its asset available. A Sparkle private key must be provisioned before any release run; a commit or draft release does not make the feed public. This integration still needs a hosted CI compile and a clean notarized install/update/rollback test.

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

1. Merge reviewed code to `main`; require passing macOS 15 and 26 CI jobs.
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

## Local reliability candidate: 0.3.3 (22)

- Adds reviewed technical, interface-design, brand, and slang entries as separate local lexicon packs; slang is used to preserve valid forms rather than normalize them.
- Uses the actual selection converter for mixed RU/EN regression cases and keeps ambiguous two-letter fragments unchanged until context is strong enough.
- Tracks the exact direction of copy/paste conversion toggles so only a confirmed return to the original text can count as one manual-learning cycle. Two cycles create a review candidate; confirmation is still explicit.
- Serializes automatic Accessibility edits, manual Option edits, exact undo, and injected-buffer replacements through one bounded FIFO. A queued edit is revalidated against the captured process and input context before it starts; changed or unsupported fields are left untouched.
- Routes terminal whole-line conversion through that same FIFO. A committed buffer replacement now records its exact converted/undone direction and operation ID, so automatic undo evidence cannot silently miss the first return-to-source toggle.
- Keeps learning and layout updates behind the confirmed replacement completion, and avoids a false learning event when an Option operation fails or its snapshot became stale.
- Refreshes the open Learning table when a candidate or automatic cancellation changes the profile.
- Keeps new manual Option learning candidates above imported Punto history, labels imported history distinctly, and explains that a candidate requires a deliberate confirmation before it becomes an exception.
- Allows queued repeat Option toggles to continue only when the prior successful toggle advanced the field generation for the same operation and no physical input, app, or context changed; this prevents fast intentional toggles from being discarded as stale.
- Restores the Settings window's last size and position. Build 22 routes ⌘W through a window-scoped local monitor and directly closes the window; the menu item also has an explicit Command mask. A live UI smoke test confirmed that ⌘W closes Settings and that reopening the same bundle shows Settings again. On the installed build 18, ⌘W left MultiSwitcher running in the menu bar and ⌘Q removed it from the running-app inventory; the installed app was relaunched afterward and left running with Settings closed. Source routes ⌘Q through app cleanup and termination.
- Keeps imported Punto training history separate from new local evidence.
- `bash scripts/check_selection_conversion.sh` runs 85 deterministic actual-source assertions across automatic decisions and selected-text conversion; `MultiSwitcherCoreTests` runs 241 checks, including rebased queued Option toggles, manual learning review ordering, and ten Option toggles persisted through a profile reload. Build 22 compiled for arm64 and passed the build script's ad-hoc bundle integrity check, but was not installed. The appcast validator passes 3 checks. These checks do not replace physical keyboard input, Accessibility replacement tests, or the 30-run app matrix.
- Sparkle 2.10.0 is pinned for release builds, its framework is embedded in the app bundle, and the signed appcast validator checks the current version, channel, download URL, archive signature, and signed-feed trailer.
- Crash reporting stays disabled when the four Sentry configuration values are all absent; the release workflow rejects partial configuration.
