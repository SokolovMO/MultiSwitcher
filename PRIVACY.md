# MultiSwitcher privacy

Last updated: 2026-10-20

MultiSwitcher processes keyboard events locally to detect layout mismatches and apply the correction you request or enable. It needs macOS Input Monitoring and Accessibility permissions for global shortcuts and text replacement. Secure-input mode is checked before a key event's Unicode text is read into the app's typing buffer; conversion is skipped while secure input is active.

## Text and profile data

- Text conversion and bundled dictionaries run on your Mac. MultiSwitcher does not send typed text, clipboard contents, rules, or learning history to its update service.
- Your profile is stored in your macOS user account under `~/Library/Application Support/MultiSwitcher`. It can contain your rules, learned exclusions, imported history, selected settings, and per-app layout preferences. The app does not encrypt this profile; macOS file permissions restrict access to your account.
- Debug logging is off by default. When enabled, logs describe operation types, lengths, and outcomes. Review the report before sharing it: the support screen shows a sanitized preview and sharing happens only after you choose to continue. Redaction is a safeguard, not a guarantee that every identifier is removed.
- MultiSwitcher has no automatic crash-reporting or analytics service configured. Logs are not uploaded in the background.

## Updates

When automatic update checks are enabled, the app contacts GitHub Releases to check for version metadata. If you choose to install an update, it downloads the release disk image and verifies its hash, app identity, Developer ID signature, and Gatekeeper assessment. GitHub receives the usual network request metadata, such as your IP address. The app does not add text or profile data to these requests.

## Your choices

You can disable automatic update checks and debug logging in settings, remove the app's macOS permissions in System Settings, and delete your local profile or its backups after quitting MultiSwitcher. If you share a diagnostic report, inspect its preview first and remove any remaining information you do not want to send.

## Contact

Report a bug or request a feature through the [MultiSwitcher GitHub issue tracker](https://github.com/SokolovMO/MultiSwitcher/issues). Do not include passwords, private text, clipboard contents, or unredacted logs in public issues.
