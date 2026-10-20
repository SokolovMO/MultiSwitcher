# MultiSwitcher privacy

Last updated: 2026-10-20

MultiSwitcher processes keyboard events locally to detect layout mismatches and apply the correction you request or enable. It needs macOS Input Monitoring and Accessibility permissions for global shortcuts and text replacement. Secure-input mode is checked before a key event's Unicode text is read into the app's typing buffer; conversion is skipped while secure input is active.

## Text and profile data

- Text conversion and bundled dictionaries run on your Mac. MultiSwitcher does not send typed text, clipboard contents, rules, or learning history to its update service.
- Your profile is stored in your macOS user account under `~/Library/Application Support/MultiSwitcher`. It can contain your rules, learned exclusions, imported history, selected settings, and per-app layout preferences. The app does not encrypt this profile; macOS file permissions restrict access to your account.
- Debug logging is off by default. When enabled, logs describe operation types, lengths, and outcomes. Review the report before sharing it: the support screen shows a sanitized preview and sharing happens only after you choose to continue. Redaction is a safeguard, not a guarantee that every identifier is removed.
- Optional crash reporting uses Sentry only in builds configured for the service, and starts only after the user enables **Send crash reports** in About. It sends only unhandled crash events, with the exception type, stack frames, app version/build, macOS version, and limited technical runtime context. It removes exception messages, user/request data, arbitrary app context, threads, and breadcrumbs. Screenshot and view-hierarchy collection remain disabled at the SDK defaults; memory introspection is also disabled. It never reads or sends typed text, clipboard contents, windows, profile data, rules, dictionaries, or debug logs. Sentry receives normal network metadata, including the request IP address. If no Sentry DSN is configured in the build, the control is unavailable and no report is sent.
- Consent is off by default and can be revoked in About. Revocation closes the reporter and drops any event dated before revocation if it is encountered later. Reports already received by Sentry remain subject to the project's configured retention and deletion controls.

## Updates

When automatic update checks are enabled, the app contacts the GitHub Releases API to check for stable or beta version metadata. If you choose to install an update, it downloads the release disk image and verifies its hash, app identity, Developer ID signature, and Gatekeeper assessment. GitHub receives the usual network request metadata, such as your IP address. The app does not add text or profile data to these requests.

## Your choices

You can disable automatic update checks, choose the stable or beta update channel, revoke crash-report consent, and disable debug logging in settings. You can also remove the app's macOS permissions in System Settings and delete your local profile or its backups after quitting MultiSwitcher. If you share a diagnostic report manually, inspect its preview first and remove any remaining information you do not want to send.

## Contact

Report a bug or request a feature through the [MultiSwitcher GitHub issue tracker](https://github.com/SokolovMO/MultiSwitcher/issues). Do not include passwords, private text, clipboard contents, or unredacted logs in public issues.
