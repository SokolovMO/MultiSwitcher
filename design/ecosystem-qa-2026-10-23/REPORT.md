# multiswitcher — ecosystem UI verification, 23 October 2026

Implemented and verified first in a standalone preview build. Following the explicit installation request, both new applications are now installed and running from `/Applications`. Installed binaries match the verified archives; strict signature checks pass. 28 temporary build/cache paths were removed and 9 user-data files were unchanged during cleanup. Following a separate explicit confirmation, all six old rollback application bundles were deleted; user-data files were unchanged. See `INSTALLATION.json`. The preview is ad-hoc signed and is not a notarized production release. Business algorithms, dictionaries, rules and learning records were preserved.

## Changes

- Both products now vendor the same `MultiDesignKit.swift` and Core geometry metrics; neither checkout depends on its sibling. One native sidebar owns its actual rail width, row selection, icon positions, label visibility and detail frame. No expanded subtree is hidden underneath the compact panel.
- Sidebar widths 208/60, row 32, gutter 12, finite 260 ms monotonic spring. Reversals start from the displayed progress; the timer stops at rest. Native buttons retain labels, tooltips, keyboard arrows, activation and visible neutral focus. The button remains available in every MultiSwitcher section.
- Content stays top-leading with 24 pt insets; forms use a 608 pt outer container / 560 pt inner width. Tables use available useful width. Settings restore their frame onto a visible screen, support native resize/zoom, and do not resize on section/theme changes. Settings and rule dialogs disable fullscreen.
- Fixed a defect found in the real minimum-size pass: rule-table source was outside the viewport. `RuleScrollView` now allocates all four columns from the actual clip width, with usable minima and a horizontal-scroll fallback. The source column is visible at minimum expanded width.
- The rule dialog remains a compact standalone native form with all original fields and validation, neutral focus/selection, cancel/save, and native return/escape semantics. The permission guide clears the first button’s Return binding so that only the intended “later” action owns Return. Popovers target 340 pt, with settings/help/quit footer; existing actions remain their source of truth. The new help shows real instructions and shortcuts without external navigation. Existing notifications remain native and ordinary corrections acquire no new system notifications.

## Actual-window evidence

Open [the gallery](index.html). `final/` contains 124 real window PNGs and two recordings. The root captures are the first pass; `pass-2/` precedes the final table allocation fix, `pass-3/` precedes the footer help and permission-guide coverage; `pass-4/` precedes the permission-guide Return-binding fix. These are retained to distinguish iterations. Approved reference: `../approved-concept.jpg`.

The final matrix includes all seven sections × two themes × three window sizes × two sidebar states (84 PNGs), plus scroll bottoms, rule dialogs, help, permission guide, menu-bar/popover/submenu, feedback, maximum-size and zoom captures. No screenshot is a generated mockup.

`final/geometry-results.json`: PASS for 20 complete collapse/expand cycles, 20 rapid reversals, containment throughout sampled transitions, adjacent detail geometry, native up/down selection, the reduced-motion code path, stopped timer, and unchanged window frame across navigation/theme changes. Width-only, height-only, minimum/large/normal resize sequences are exercised, including interruption of the sidebar transition.

`final/window-results.json`: PASS for maximum frame within the screen, native zoom within the screen, zoom restoring the previous size, frame autosave enabled, fullscreen disabled. Screen reconnection and negative-origin cases are separately covered by Core tests; physical monitor disconnection was not performed.

Real recordings: `final/sidebar-resize-theme.mov` (about 18 s) and `final/popover-open-close.mov` (3 s). They record native windows, not a simulated UI. The popover recording follows one native window ID: after dismissal the remainder can be black, so it must not be presented as proof that the newly opened popover was recorded. Reopening and click-outside/Escape semantics still need a physical interaction check. Recording frame rate is metadata, not a claim of universally perfect frame pacing.

## Functional checks

- Production preview build and resource validation: PASS; 2 language packs and 8 thematic vocabulary packs validated; `codesign --verify --deep --strict` PASS. Build identity and executable hash: `BUILD-INFO.txt`. The packaged ZIP was extracted separately; strict signature verification passed and its executable matches the tested build byte for byte.
- XCTest: 16 tests, zero failures. Includes correction reliability, rules/layout policy and off-screen window geometry.
- `MultiSwitcherCoreTests`: 310 checks passed, including profile/rule import/export and persistence, dictionaries, learning and correction policy.
- Native selection/keyboard layout suite: 106 assertions, zero failures.
- Actual rules UI search/selection/keyboard smoke: PASS in both themes. Modal forms were opened, captured with focus and cancelled through their actual action.
- Shared source parity is recorded in `shared-source-parity.json`. Logs are in `logs/`; screenshot and recording hashes are in `SHA256SUMS.txt`.

## Acceptance limits

The UI implementation and recorded geometry matrix pass. Full acceptance of every requested system scenario is still open:

- Physical typing/autocorrection in external applications, real hotkey delivery and permission re-grant were not exercised by this isolated review process. It deliberately does not start keyboard monitors, update checks or the permission wizard.
- Modal save/invalid-input interactions were not driven end to end against user records; rule validation and round-trip persistence pass in Core tests. The preview does not add or remove user rules for a screenshot.
- Native VoiceOver speech, physical Tab/Shift+Tab across every control, multiple Spaces, monitor unplug/scaling changes, and system-wide accessibility-setting combinations were not exhaustively exercised. Reduced Motion was exercised through the same runtime branch using a test override, without changing the user's system preference.
- The existing permission guide was opened and captured in both themes with missing-permission flags; review automatically cancels before opening System Settings. This proves the guide UI, not permission re-grant or the entire first-launch workflow.
- Static monochrome checks cover captured states; they cannot prove every possible opened native picker/context menu. Traffic lights and system-owned permission/file panels keep macOS appearance.
- This is a visual/behavioral adaptation of the approved concept to existing features. It does not implement functions that appear only in the concept.

MultiShift has its own independently verified build and [actual-window gallery](/Users/sokolovmo/Documents/MultiShift/docs/ecosystem-qa/index.html). Its final geometry report passes all five sections, both themes, all three sizes and both sidebar states. The authorized companion chat reports 16 XCTest and 46 Python tests passed, with 2 Python skips, plus actual UI PNG-to-JPG and 600×400 resize-copy checks preserving the original and filename case. Physical Shift+drag, VoiceOver, monitor changes and native notification-banner delivery remain unverified; do not infer those from the UI matrix.

Combined ecosystem report: [MultiShift and MultiSwitcher results](/Users/sokolovmo/Documents/MultiShift/docs/ecosystem-qa/REPORT.md).


Обновление меню 24 октября: [общая геометрия, перенос текста и переходы](/Users/sokolovmo/Documents/MultiSwitcher/design/popover-review-2026-10-24/REPORT.md). Установочные ZIP обновлены этим исправлением.
