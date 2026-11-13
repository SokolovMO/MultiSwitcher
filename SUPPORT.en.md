<p align="right"><a href="SUPPORT.md">Русский</a> · <b>English</b></p>

# Help with MultiSwitcher

Reports in Russian and English are welcome. Start with the [download page](https://sokolovmo.ru/multiswitcher/)
and [installation guide](README.en.md#install).

## Correction or shortcuts do not work

1. Confirm that automatic correction is enabled in the menu or General settings.
2. Open **Setup Guide…** and check both required macOS permissions.
3. Check whether the app is paused or the current application is excluded.
4. If the menu reports Secure Input, follow the recovery instructions below.
5. Reproduce with synthetic text such as `ghbdtn` in a new TextEdit document.

Behavior can differ between applications, protected fields, and editable web
controls. Include the affected app and field type when reporting a problem.

## macOS permissions


MultiSwitcher does not interrupt first launch with a permissions dialog or change macOS privacy settings in the background. When keyboard access is missing, **Check Permissions…** appears in the menu-bar menu and a status with **Setup Guide…** appears in General settings. The guide explains each permission before offering to open System Settings; **Later** is the default choice. You can leave either permission off and keep using the app and its settings, but automatic correction and the manual Option shortcut remain paused until both permissions are enabled.

The first path is **System Settings → Privacy & Security → Accessibility → MultiSwitcher** on macOS 15–26, and **System Settings → Privacy & Security → Device Control & Data Access → MultiSwitcher** on macOS 27. The second path is **System Settings → Privacy & Security → Input Monitoring → MultiSwitcher**. MultiSwitcher uses the first permission to work with text in supported fields and Input Monitoring to receive keyboard events for layout detection and shortcuts. If you enable both after choosing **Open Settings**, MultiSwitcher restarts once to apply keyboard monitoring. macOS remains in control of both switches.

macOS Secure Input can temporarily block both automatic and manual correction, even with both permissions enabled. MultiSwitcher checks this independently of keyboard events. The menu shows which app holds Secure Input; select that row for recovery instructions. A prolonged block sends a quiet native macOS notification with the app icon and a Details action. **Advanced → Test notification** requests notification permission when needed; it is never requested automatically during password entry. If permission is missing or delivery fails, the status remains visible in Advanced settings and the menu; no imitation desktop banner is shown. macOS controls banner appearance and Focus. Recovery removes the warning from Notification Center automatically. Leave the password field in the named app; if the block persists, quit that app completely and reopen it. Short password entry does not trigger the automatic notice. Learning and pause feedback use coalesced native notifications with generic text; typed words are never stored in Notification Center.


## Downloads and updates

Use the [official download page](https://sokolovmo.ru/multiswitcher/). Updates are
hosted on the same server; an empty GitHub Releases page does not mean there is
no download. The app is independently signed and is not Apple-notarized.

For updates, use **Check for Updates** from the menu or About settings. If you
installed with Homebrew, see [adoption and upgrade instructions](homebrew-tap/README.md).
Do not delete your profile or force-replace an existing installation to solve an
update problem. Report the version/build and error message first.

## Report an issue

Use [Bug report](https://github.com/SokolovMO/MultiSwitcher/issues/new?template=bug_report.yml)
or [Feature request](https://github.com/SokolovMO/MultiSwitcher/issues/new?template=feature_request.yml).
Include the app version/build, macOS version, affected app, reproduction steps,
and expected versus actual behavior.

The app can prepare an editable, redacted diagnostic preview. Review it before
copying anything into a report. Redaction cannot guarantee that every private
detail has been removed. Never share passwords, real messages, clipboard contents,
private profiles, signing keys, or raw logs.

For vulnerabilities, use the [security policy](SECURITY.en.md). There is no guaranteed
support response time. Known release checks and limits are recorded in
[RELEASE.md](RELEASE.md) and the linked validation records.
