# Release and update pipeline

The intended distribution is an Apple Silicon macOS app in a signed and notarized DMG on GitHub Releases. The custom in-app updater is designed to verify the manifest, DMG hash, bundle identity, Developer ID team signature, and Gatekeeper assessment; end-to-end installation is still a release gate.

## Current status

**Status checked 2026-10-20: there is no public app release. Do not describe the current build as production-ready.**

- The public repository has no published releases.
- The current implementation is on draft PR #2 and has not reached main.
- The previous PR commit passed core checks and an arm64 build on macOS 15 and 26. The current updater, consent, and symbol-upload changes are awaiting a fresh CI run. CI does not test real keyboard input in Spotlight, Cursor, browsers, or other apps.
- The current source passes 34 core checks and builds for arm64 with an ad-hoc signature. That signature is not suitable for public distribution.
- No Developer ID identity is available in the current build environment. A Developer ID build, notarization, clean install, and in-app update from a previous signed build remain unverified.
- The source now supports an optional Sentry crash-reporting integration. It is disabled until explicit in-app consent and a DSN is configured in the release build. This checkout has no DSN, so automatic reports are not active yet.

Treat this as **release-candidate preparation**. Do not publish a stable DMG until the gates below pass.

## One-time GitHub configuration

Create a GitHub Actions environment named multiswitcher-release.

- Add the project owner as a required reviewer for each deployment.
- Restrict deployment tags to `v*` and `beta-v*`.
- Store all signing credentials as environment-scoped secrets, not repository-wide secrets.

Environment variables:

- MULTISWITCHER_DEVELOPER_TEAM_ID: the 10-character Apple Developer Team ID.
- MULTISWITCHER_DEVELOPER_ID_SIGNING_IDENTITY: exact Developer ID Application identity from security find-identity.
- MULTISWITCHER_SENTRY_DSN: public Sentry project DSN. Configure IP scrubbing and a short retention period in the Sentry project. This is an ingestion address, not an authentication token; it must not be confused with a Sentry auth token.
- MULTISWITCHER_SENTRY_ORG_SLUG and MULTISWITCHER_SENTRY_PROJECT_SLUG: the Sentry organization and project slugs used to upload matching debug symbols.

Environment secrets:

- APPLE_DEVELOPER_CERTIFICATE_P12_BASE64: base64-encoded Developer ID Application certificate and private key.
- APPLE_DEVELOPER_CERTIFICATE_PASSWORD: password for that PKCS#12 file.
- APPLE_ID: Apple Account used for notarization.
- APPLE_APP_SPECIFIC_PASSWORD: app-specific password used by notarytool.
- MULTISWITCHER_SENTRY_AUTH_TOKEN: narrowly scoped Sentry token with permission to upload debug files to this project. The release workflow uses it only to upload the matching dSYM; it is never embedded in the app.

The workflow uses a temporary keychain and removes it and the imported certificate file after the job. Keep an offline backup of the signing certificate and its password. Never put certificates, private keys, passwords, or tokens in the repository, issue tracker, chat, or workflow logs. Keep the same Team ID for future updates.

Also configure repository rules in GitHub settings:

- Protect main: require pull requests, prevent force pushes and deletion, and require checks (macos-15) and checks (macos-26).
- Protect v* tags from unauthorized creation, update, or deletion.
- Enable private vulnerability reporting if available.

The source workflow cannot safely configure these repository-level settings.

## Publishing a release

1. Merge reviewed code into main.
2. Update CFBundleShortVersionString and increment CFBundleVersion in macos/Info.plist. Keep the first public release below 1.0 until product gates pass.
3. Run core checks and arm64 build. Verify menu, permissions, import and restore, secure-input behavior, and text replacement on every macOS version advertised as supported.
4. For the public beta, create and push `beta-v0.3.0-build8` at reviewed code already contained in main. The workflow verifies the version/build, marks the GitHub draft as a prerelease, and builds the app with the beta updater channel. For stable 1.0, use `v1.0.0-buildN` after all stable gates pass.
5. The workflow signs the app, notarizes and staples the app and DMG, checks Gatekeeper, and creates a draft release with the DMG and channel-specific `version.json`. Stable users query the latest full release; beta users query published beta releases and will also accept a newer stable release. Drafts are not delivered as updates.
6. Install the draft on a clean Apple Silicon Mac. Complete the smoke checklist, including updating an app installed in /Applications. Publish the draft only after every gate passes.
7. From the installed release, check for updates, install the next signed build, restart, and verify profile and permissions. Test rollback before promoting updater changes.

A local or ad-hoc build cannot serve as the first in-app update source. Install the first signed release manually. macOS may request Input Monitoring and Accessibility permissions again after the signing identity changes.

## Support and user reports

Issue forms request synthetic examples, app and macOS versions, affected app, and action. Debug logging is off by default. A diagnostic report is local and shared only after the user previews it. Configured release builds can send crash type, stack frames, and app/macOS versions to Sentry only after the user opts in; text, clipboard, profile, windows, and dictionaries are filtered out. The user can revoke consent in About. Configure Sentry data scrubbing and retention before publishing a build with reporting enabled. There is no support-time guarantee. See PRIVACY.md and SECURITY.md.

Do not request real messages, URLs with private data, clipboard content, profiles, passwords, or raw logs in public issues.

## Release checklist

### Signing and delivery

- [ ] The release environment requires a reviewer and accepts only reviewed `v*` and `beta-v*` tags.
- [ ] Signing credentials are environment-scoped, not repository-wide.
- [ ] The tag points to code merged into main and matches app version/build.
- [ ] The workflow creates a draft; a human publishes only after QA.
- [ ] App and DMG pass strict signature, notarization, stapler, and Gatekeeper checks.
- [ ] version.json SHA-256 matches the exact uploaded DMG.
- [ ] Fresh installation works and a recovery backup is available.
- [ ] In-app update is verified from the preceding signed build in /Applications and a user-owned Applications folder; failed updates leave the old app launchable.
- [ ] Profile migration, import, backup, restore, and rollback pass on a clean account.

### Product and compatibility

- [ ] Live input passes in Spotlight, native fields, Safari and Chrome, chat apps, Cursor/Codex, Finder or System Settings search, and supported terminals.
- [ ] Option conversion and exact undo, automatic correction, fast typing, punctuation, secure input, app exclusions, and permission recovery are verified.
- [ ] Each advertised macOS version has hands-on testing; CI compilation is not live-input testing.
- [ ] Idle CPU, memory, battery, and fast-typing responsiveness are measured on the signed release.
- [ ] Release notes explain behavior changes, permission changes, known limitations, and recovery.
- [ ] Bundled FrequencyWords and curated vocabulary notices are present in the app.
- [ ] The first beta installs with the beta channel selected, can switch to stable, and does not offer draft or wrong-channel releases.
- [ ] Crash reporting is off on first launch; opt-in and revoke are tested, including the exact sanitized event payload and Sentry IP/retention settings.
- [ ] The matching release dSYM is uploaded to Sentry and a test crash resolves to MultiSwitcher source frames.

A public beta can be published after signing, notarization, privacy, installation, and basic input smoke checks pass. A stable 1.0 release requires the full product gates above. Until then, do not claim that every supported app or macOS version, or in-app updates, has been verified.
