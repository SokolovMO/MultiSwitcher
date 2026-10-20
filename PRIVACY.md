# MultiSwitcher privacy

Last updated: 2026-10-21

## Local processing

MultiSwitcher observes keyboard events to detect layout mismatches and may replace text in the focused field. This processing and the bundled dictionaries run on your Mac. The app needs macOS Input Monitoring for global keyboard shortcuts and Accessibility for field inspection or text replacement. Secure input is checked before event text is placed in the typing buffer; correction is skipped while secure input is active.

Your local profile is stored under ~/Library/Application Support/MultiSwitcher. It may include rules, learning state, imported history, settings, per-app layout preferences, and backups. The profile is not encrypted by MultiSwitcher; macOS account file permissions limit access.

## Network activity

- Update checks contact the GitHub Releases API and download release metadata/assets if you choose to update. GitHub receives ordinary request metadata such as your IP address. Typed text, clipboard content, rules, learning history, and profile data are not included in these requests.
- Optional crash reporting is available only in builds configured with a reporting endpoint. It is off by default and Sentry does not initialize until you explicitly enable it. Only unhandled native crash events are eligible. The app strips messages, user/request data, arbitrary context, breadcrumbs, and window data; the remaining event includes exception type, stack frames, app release, and macOS version. Sentry receives normal network metadata, including IP address. The repository owner must configure IP scrubbing, retention, and deletion controls before enabling a public build.
- If crash reporting is not configured in the build, no crash report is sent and the control is unavailable.

## Logs and support reports

Debug logging is off by default. When enabled, logs are intended to contain event type, length, duration, and outcome rather than typed words. The support report redacts common local paths, app identifiers, sensitive key/value fields, URLs, emails, IP addresses, and common credential patterns. This filter cannot guarantee that every personal detail is removed.

The report preview is editable. When you explicitly choose Copy & Open Issue, MultiSwitcher applies redaction again, copies the report to the clipboard, and opens the GitHub bug form. The app does not submit the issue or email the report. Review the copied result before pasting or submitting it; avoid real messages, private URLs, passwords, clipboard data, and raw profile files.

## Permissions and choices

macOS controls Input Monitoring and Accessibility permissions. MultiSwitcher does not reset or change those permissions automatically. If an update or system change removes access, the app can open the relevant System Settings page; you decide whether to re-enable it.

You can disable automatic update checks, choose the stable or existing beta/test channel, turn off debug logging, and revoke crash-report consent. Revocation closes the reporter; queued events dated before or at revocation are rejected, and events with no timestamp are rejected after revocation. Reports already received by Sentry remain subject to configured retention and deletion controls.

## Contact

Report a bug or request a feature through the [MultiSwitcher GitHub issue tracker](https://github.com/SokolovMO/MultiSwitcher/issues). For security issues, see SECURITY.md. Do not include private text, credentials, profiles, or unredacted logs in a public issue.
