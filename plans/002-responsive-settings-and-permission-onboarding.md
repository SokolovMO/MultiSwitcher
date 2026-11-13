# Responsive settings and calm permission onboarding

> Current status, 2026-10-23: the user explicitly enabled the required macOS permissions on the maintainer Mac. A single physical TextEdit smoke check confirmed automatic conversion after Space and Option conversion of a selected word. The older permission-off observations below describe earlier builds and are not the current machine state. Cross-app and repeatability testing remains open; see [RELEASE.md](../RELEASE.md).

## User-reported issues

- General settings controls/card edges clipped or overlapped after resizing the window.
- A later macOS 27 screenshot showed the top of the General page too close to the title bar and the trigger card intruding into the next group. The earlier maximized-window pass did not cover this state; treat it as a reopened layout regression.
- First-run permission prompts must explain the required macOS access without making the app feel unsafe or forcing the user into System Settings.
- With Input Monitoring left off, `ghbdtn ` remains unchanged. This is expected: macOS does not deliver keyboard events to MultiSwitcher, so neither automatic conversion nor the Option trigger can run.
- Logs from the installed 0.3.8 (43) also contain earlier cancelled buffer replacements and queue-full outcomes. They must be retested on the current source with permissions enabled by the user; they are not explained by the current permission-off test.

## Source changes

- Measure the adaptive settings card stack again when the content width changes; update the scroll document height so wrapped labels remain reachable.
- Propagate the new scroll viewport width through the document and tab view before measuring wrapped rows; remeasure after permission status and example-preview text changes.
- Keep the document at least as tall as its viewport and every measured page, and log any actual card-frame intersections in debug builds without logging user text.
- Preserve the visible position on resize, keeping the top edge anchored when the user was already at the top.
- Do not show a modal permission guide at launch. Show the missing-permission action in the menu and status in General settings.
- Open the permission guide only after the user selects **Check Permissions…** or **Setup Guide…**. Make **Later** the default button; open System Settings only after an explicit selection.
- Explain that Input Monitoring is required for both automatic correction and manual Option conversion. Leave macOS permission toggles untouched.

## Verification results

- Build 45 compiles for arm64, validates its `Info.plist`, embedded resources and ad-hoc code signature, and includes all language and thematic packs.
- Build 45 is installed at `/Applications/MultiSwitcher.app`; the installed executable matches the verified candidate and the existing profile was retained. Older temporary build bundles were removed.
- The General page was visually inspected in its initial and zoomed sizes. Cards, permission status, and controls remain separated and visible in those two views.
- The permission guide was opened from General settings, read in Russian, and dismissed with **Later**. System Settings did not open; both macOS permission switches remained off.
- 298 deterministic core checks, 99 selected-text assertions, and 13 XCTest reliability tests pass. Live keyboard conversion is intentionally unverified because the current permissions are off.
- Follow-up source adds width-first layout measurement and schedules a fresh fit after the permission status or automatic-example result changes. The core suite now has two document-sizing regression assertions; Xcode 27.1 reports 300 core checks, 99 selected-text assertions, and 13 XCTest reliability tests passing.
- Build 47 is installed at `/Applications/MultiSwitcher.app` as 0.3.8 (47), arm64, ad-hoc signed. Its installed executable matches the verified candidate hash. The Build 46 rollback copy and temporary staging bundle were removed after launch verification.
- On installed Build 47, the latest General-page screenshot state was visually checked at the current large window size: the first card clears the title area, permission text stays inside the card, and the following group remains separated. This closes that screenshot's overlap at this size only.
- Build 52 (0.3.11) was freshly opened from Finder and its About page confirmed the installed version. The Learning card's top edge and its help/table spacing, plus the Rules card and table, were visually checked at the current large full-screen size; the former clipped top edge is no longer present. This is a targeted large-layout check, not minimum-size or manual-resize coverage.
- Build 52 adds top-aligned content measurement for the Learning page and an explicit fit adjustment where the measured content previously exceeded the card by 6 pt. Rules keeps its deliberate 12 pt vertical inset. Six new layout-policy assertions are included in the 306-check Core suite.
- Hosted CI run 39850867325 passes on macOS 15, macOS 26, and the Xcode 27 runner, including the app bundle and Sparkle compile steps. The Xcode 27 runner is preview infrastructure and does not certify hands-on OS compatibility.
- Hosted CI for commit `7ece214` passes on macOS 15, macOS 26, and the Xcode 27 preview runner. This is compile/test coverage, not manual UI or input coverage.
- The installed About page explains that crash-report collection is not configured in this build and reports are not sent automatically. The main page clearly indicates that keyboard actions are paused while the two required permissions are off. The user asked to keep Input Monitoring off; no macOS permission was changed.

## Verification still required

- Verify the settings page at the minimum allowed window size, after manual drag-resize, and in both light and dark mode. The attempted edge drag did not resize the active maximized window in this UI session, so the manual-resize behavior remains open rather than counted as a pass.
- Verify at the minimum allowed window size and after manual edge-drag resize; the current large-window screenshot passes, but the UI automation did not successfully change the maximized window's size.
- Check the first General-page card, long permission copy, scroll reachability, and card spacing in dark mode and at the minimum window size.
- Verify the permission menu row appears only while either required permission is missing.
- With permissions left off, confirm the app and settings stay available and the pause status is clear. This is verified in installed Build 52; do not treat the lack of automatic conversion as a successful input test.
- After the user elects to enable the required permissions, repeat automatic conversion, Option conversion/undo, fast typing, and the reported mixed-language cases in TextEdit, Spotlight, Codex, Cursor, and Safari.
- Run the documented per-OS public-alpha install, update, rollback, and privacy checks; this plan does not waive any Public Alpha 1 release gate.
