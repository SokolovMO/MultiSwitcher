# 001 — Make settings navigation feel immediate

- **Status**: Implemented in source build 41; ordinary and zoomed settings views were visually checked on build 45; Reduce Motion feel check pending
- **Branch**: `codex/multiswitcher-033-reliability`
- **Severity**: MEDIUM
- **Category**: Purpose, easing, and frequency
- **Estimated scope**: 1 file, about 15 lines

## Problem

Changing a settings page runs two animations in sequence. Sidebar navigation is used repeatedly, so the 250 ms fade can make the app feel slow even though each individual animation is below 300 ms. The pane also fades down to 72% opacity before the page changes, which makes the transition more noticeable than its purpose requires.

Values before implementation in build 40:

```swift
private enum SettingsMotionMetrics {
    static let pageFadeOut: TimeInterval = 0.09
    static let pageFadeIn: TimeInterval = 0.16
    static let expandPage: TimeInterval = 0.22
}
```

Navigation previously used `.easeInEaseOut`, faded the pane to `0.72`, swapped the page after the first group, then ran the second group.

## Target

Keep page changes reversible and brief: use a 70 ms fade-out to 84% opacity, swap the page, then a 90 ms fade-in to full opacity. Use `.easeOut` for both phases. Total transition time is 160 ms. Keep the existing generation guard and the current instant transition when Reduce Motion is enabled.

```swift
private enum SettingsMotionMetrics {
    static let pageFadeOut: TimeInterval = 0.07
    static let pageFadeIn: TimeInterval = 0.09
    static let expandPage: TimeInterval = 0.22
}
```

```swift
context.duration = SettingsMotionMetrics.pageFadeOut
context.timingFunction = CAMediaTimingFunction(name: .easeOut)
paneScrollView.animator().alphaValue = 0.84
```

Apply the same `.easeOut` timing function to the fade-in. Preserve the 220 ms expand/restore transition; it communicates the sidebar's spatial change and already respects Reduce Motion. Do not animate keyboard conversion, rule matching, or text replacement.

## Repo conventions to follow

- Keep timings in `SettingsMotionMetrics` in `SettingsWindowController.swift`.
- Keep the existing `reduceMotion` check and `pageTransitionGeneration` cancellation guard.
- Continue using opacity for page feedback and direct pointer tracking for sidebar resizing.
- Use the system appearance and semantic colors; do not add a motion dependency or decorative color effects.

## Implementation

Implemented in source build 41: the page fade constants are 70 ms and 90 ms; both navigation phases use `.easeOut`; intermediate pane opacity is 0.84. The expand animation and notice fades were left unchanged.

## Boundaries

- Do not change keyboard monitoring, correction decisions, text replacement, or learning.
- Do not add animation to high-frequency keyboard actions.
- Do not remove the Reduce Motion behavior or generation guard.
- Do not alter the layout structure or system control appearance in this motion-only plan.

## Verification

- **Mechanical**: XCTest passes in source; Build 41 bundle verification is recorded in `RELEASE.md` after the build completes.
- **Feel check pending**: Build 47 is installed locally, but page-switch and expand/restore motion have not been evaluated with repeated live interaction or Reduce Motion. The app is ad-hoc signed; there is no trusted signing identity, so this is not a public-release visual sign-off.
- **Done when**: navigation takes no more than 160 ms in the normal setting, stays responsive when interrupted, and the Reduce Motion path has no animated movement. Code is updated; only the live feel check remains.
