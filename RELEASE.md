# Release and update pipeline

The release workflow builds an arm64 app, runs the core checks, signs it with Developer ID, submits the app and disk image for Apple notarization, staples the tickets, and publishes the DMG plus `version.json` to GitHub Releases. The app checks the latest release manifest and verifies the downloaded DMG hash, bundle identifier, Team ID signature, and Gatekeeper assessment before replacing the installed app.

## One-time GitHub configuration

Add these repository variables:

- `MULTISWITCHER_DEVELOPER_TEAM_ID`: the 10-character Apple Developer Team ID.
- `MULTISWITCHER_DEVELOPER_ID_SIGNING_IDENTITY`: the exact `Developer ID Application: …` identity shown by `security find-identity`.

Add these Actions secrets:

- `APPLE_DEVELOPER_CERTIFICATE_P12_BASE64`: base64-encoded Developer ID Application certificate and private key.
- `APPLE_DEVELOPER_CERTIFICATE_PASSWORD`: password for that PKCS#12 file.
- `APPLE_ID`: Apple ID used for notarization.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for notarization.

The workflow creates a temporary keychain and removes it at the end. Never put certificate files or passwords in the repository. Keep a secure offline backup of the signing certificate and its password; updates must continue using the same Team ID.

## Publishing a release

1. Set `CFBundleShortVersionString` and increment `CFBundleVersion` in `macos/Info.plist`.
2. Run the core checks and an arm64 build locally. Manually verify real typing, Option undo, Spotlight, secure input, permissions, and installation on each macOS version advertised as supported.
3. Push a build-specific tag such as `v1.0.0-build42`. The workflow checks it against both `CFBundleShortVersionString` and `CFBundleVersion`, then creates a **draft** release. It fails closed if any signing or notarization secret is missing.
4. Install the draft DMG on a clean Apple Silicon Mac and run the complete release smoke checklist. Only then publish the draft as the latest stable release. Publishing is a deliberate promotion step; a tag push never reaches users by itself.
5. Install the promoted release and verify an in-app update from the previous signed release, including the exact manifest build number and asset hash.

A local self-signed development build cannot serve as the first in-app-update source for a Developer ID release. Install the first signed release manually; macOS may ask the user to confirm permissions again after the signing identity changes.

## Release checklist

- [ ] The published tag matches the app version and build number.
- [ ] The workflow produced a draft first; a human published it only after signing, notarization, and smoke checks passed.
- [ ] Core checks and arm64 build pass on the release commit.
- [ ] DMG and app pass strict signature and Gatekeeper checks after notarization.
- [ ] Release manifest SHA-256 matches the exact uploaded DMG.
- [ ] Fresh install and update from the previous public version work on Apple Silicon.
- [ ] Update-check tests confirm higher marketing versions and higher builds are detected; an older build is never offered.
- [ ] Real input scenarios pass in Spotlight, native fields, browsers, chat apps, and terminals.
- [ ] Permission recovery, secure-input exclusions, profile import/restore, and uninstall behavior are verified.
- [ ] macOS versions are listed as supported only after hands-on testing on those versions.
