# Public Alpha 1 readiness

Last verified: 2026-10-21. This document describes source preparation, not a published release.

## Release state

**Do not publish Public Alpha 1 yet.** The GitHub release list has no public app release. The project source is in draft PR #2 and is not a published installer. Current app metadata is 0.3.2 (10), and the local environment has no valid Developer ID identity. The current updater is a custom GitHub-release updater; migration to signed Sparkle appcasts is not complete. A public Pages site and release workflow are prepared in source, but Pages must be enabled in repository settings and no notarized update has been tested end to end.

Required hands-on checks on **each macOS 15, 26, and 27** before alpha publication:

- Install, request permissions, remove/regrant permissions manually, launch at login, sleep/wake, and quit.
- Confirm automatic correction, Option conversion and exact undo, fast typing, edits, secure input, and no damage to neighboring text in TextEdit, Spotlight, Codex, Cursor, Safari, and agreed supported apps.
- Exercise profile import, backup, restore, learning, and update-preserved profile on a clean user account.
- Measure idle/active CPU, memory, and input latency.
- Verify Developer ID signature, notarization, Gatekeeper, fresh install, update from the prior signed build, and rollback.
- Verify crash-report opt-in/revocation, exact sanitized payload, IP handling/retention, and dSYM symbolication before enabling reporting in a public build.

CI compilation on macOS 15/26 and core checks do not substitute for live input on those systems. On the current macOS 27.0.1 Mac, 195 core checks and 51 actual-source selection-conversion assertions pass. A release arm64 app bundle builds and passes strict signature verification with the existing local stable signing identity outside the sandbox. Developer ID and notarization credentials remain unavailable; this local signature is not a public distribution signature. The selection checks use real bundled dictionaries and native RU/US keyboard maps, with in-memory settings; they do not prove Option event delivery or text replacement in Telegram.

## Public Alpha 1 scope

- Keep the existing **beta/test channel**. Public Alpha 1 is a release label on that channel, not a third updater channel.
- Use a prerelease tag such as `beta-v0.3.2-build10` after version/build metadata is incremented and reviewed code is merged to `main`.
- Keep the GitHub release as a draft while validating the signed DMG. Publish manually only after every alpha gate above passes.
- Do not call the build `1.0`. Stable 1.0 is a separate release after alpha feedback and open text-integrity issues are resolved.
- Do not claim compatibility with an OS version until hands-on testing is recorded.

## Current distribution mechanism and migration gate

The current code checks GitHub Releases, validates manifest structure, HTTPS asset locations, SHA-256, bundle identity, Developer ID team signature, and Gatekeeper before replacing the app. The current JSON manifest itself is not cryptographically signed. This code has **not** been tested end to end from one notarized public build to another, and its install/rollback path is not accepted as a production updater yet.

The target is the latest reviewed production release of Sparkle 2.x with EdDSA-signed appcasts for stable and the existing beta channel. Pin the exact version when integration begins and verify it against the [official Sparkle documentation](https://sparkle-project.org/documentation/). Sparkle integration requires a persistent key pair: keep the private key only in the protected release environment, embed its matching public key, generate and validate appcasts in release automation, and test cross-channel behavior. Do not generate a new key for each release. Do not enable Sparkle or publish a feed until the key is provisioned and the signed update has passed a clean install/update/rollback test.

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

Optional crash reporting configuration (release reporting stays unavailable without it):

- `MULTISWITCHER_SENTRY_DSN` variable
- `MULTISWITCHER_SENTRY_ORG_SLUG` and `MULTISWITCHER_SENTRY_PROJECT_SLUG` variables
- `MULTISWITCHER_SENTRY_AUTH_TOKEN` secret with only debug-symbol upload permission

Future Sparkle updater configuration:

- persistent Sparkle private key as an environment secret;
- matching public key embedded in the app;
- release automation that builds both feeds and signs every update item.

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

## Local selection fix: 0.3.2 (10)

- Adds lowercase `openrouter` to the versioned brand vocabulary.
- Smart selected-text conversion preserves already correct names and the case of mapped names.
- Manual conversion can map one unknown alphabetic token only after a nonempty selection is verified; automatic and synthesized whole-line correction remain conservative.
- Clipboard selection verification compares the process, AX element, UTF-16 selection range, copied text and live selection before paste. Unsupported AX selection verification does not enable the unknown-word override.
- Run `bash scripts/check_selection_conversion.sh` for 51 deterministic actual-source assertions. This check runs in CI alongside the 195 core checks; live Telegram confirmation remains separate.
