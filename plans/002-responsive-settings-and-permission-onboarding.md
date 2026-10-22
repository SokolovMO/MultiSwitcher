# Responsive settings and calm permission onboarding

## User-reported issues

- General settings controls/card edges clipped or overlapped after resizing the window.
- First-run permission prompts must explain the required macOS access without making the app feel unsafe or forcing the user into System Settings.
- With Input Monitoring left off, `ghbdtn ` remains unchanged. This is expected: macOS does not deliver keyboard events to MultiSwitcher, so neither automatic conversion nor the Option trigger can run.
- Logs from the installed 0.3.8 (43) also contain earlier cancelled buffer replacements and queue-full outcomes. They must be retested on the current source with permissions enabled by the user; they are not explained by the current permission-off test.

## Source changes

- Measure the adaptive settings card stack again when the content width changes; update the scroll document height so wrapped labels remain reachable.
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

## Verification still required

- Verify the settings page at the minimum allowed window size, after manual drag-resize, and in both light and dark mode. The attempted edge drag did not resize the active maximized window in this UI session, so the manual-resize behavior remains open rather than counted as a pass.
- Verify the permission menu row appears only while either required permission is missing.
- With permissions left off, confirm the app and settings stay available and the pause status is clear. This is verified in the candidate UI; do not treat the lack of automatic conversion as a successful input test.
- After the user elects to enable the required permissions, repeat automatic conversion, Option conversion/undo, fast typing, and the reported mixed-language cases in TextEdit, Spotlight, Codex, Cursor, and Safari.
- Run the documented per-OS public-alpha install, update, rollback, and privacy checks; this plan does not waive any Public Alpha 1 release gate.
