# Improvement plans

| # | Plan | Severity | Status |
|---|---|---:|---|
| 001 | [Make settings navigation feel immediate](001-settings-navigation-motion.md) | Medium | Source implemented; Reduce Motion feel check pending |
| 002 | [Responsive settings and calm permission onboarding](002-responsive-settings-and-permission-onboarding.md) | High | Build 52 installed; one user-confirmed TextEdit auto/Option smoke test passes; Learning and Rules pages pass at the current large full-screen size; minimum-size, manual-resize, dark-mode, Reduce Motion, and cross-app input checks remain open |
| 003 | [multiswitcher + multishift — первый пул правок](003-first-ui-correction-pool.md) | P0–P3 | Implemented; automated/native validation passed; [QA evidence and manual boundaries](../docs/ui-first-pool-2026-10-24/QA.md); installed apps unchanged |

## Order

Plan 003 defines the next requested correction pool: p0 icon/state → p1 window/sidebar geometry → p2 history/motion → p3 help → full validation. Its sidebar requirement supersedes the earlier unchanged-window-frame collapse check. Existing plans 001–002 remain historical context; no installed app replacement is authorized by plan 003.

1. Verify the adaptive layout at minimum width and height, and in both light and dark appearances.
2. Complete the live input matrix on macOS 15, 26, and 27. Required permissions were enabled for the current TextEdit smoke test; confirm permission state per test machine and leave access optional in user onboarding.
3. Complete plan 001's visual feel check in normal and Reduce Motion modes.
