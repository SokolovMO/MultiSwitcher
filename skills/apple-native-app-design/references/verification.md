# Verification for native appearance

Use the subset relevant to the change. Do not require a global audit for a label fix.

## Establish the artifact

Record the actual app path, bundle ID, version/build, runtime OS, selected SDK and deployment target. For SDK-related rendering defects, inspect the executable’s linked SDK and minimum OS with `otool -l`; verify the packaged accent catalog and plist declaration when accent behavior changed. Identify the code path triggered. Source changes are not proof the installed app contains them. Do not run a second keyboard-monitoring instance against the user's profile merely to take screenshots; use an isolated test mode/profile where available.

## Visual evidence

For a visual implementation, inspect the affected real app surface on the target OS. Obtain composited screenshots through the supported computer-use tools and label the build/path being shown. Use the user's live example or a current system component for the same task as the comparison; do not substitute a hand-drawn Apple-like reference.

Check the changed surface in light/dark appearance when supported. Cover long localized strings and variable content, contrast and text/icon edges. Inspect the relevant accessibility conditions: Reduce Transparency, Increase Contrast, Reduce Motion, text scaling where supported, keyboard focus and VoiceOver names. Do not change the user's global appearance/accessibility settings without authorization; use an isolated preview or report the unavailable live check.

For materials, inspect over both a simple and a visually busy backdrop when possible. A gray bitmap from a detached `NSVisualEffectView` is not reliable evidence of the composited native material. Keep a component render or HTML gallery as an aid, clearly separate from the real UI capture.

## Behavior

- Notification: actual system delivery from the intended app, category/action, no duplicate logo, no unexpected sound, no focus theft, recovery withdrawal and permission/failure routing. Do not repeatedly send the same notification to force attention.
- Alert/sheet: correct parent, button actions, Return/Escape, default/cancel roles, focus restoration and correct locale.
- Popover/menu: real anchoring, dismissal, keyboard navigation, multiple displays and edge placement where relevant.
- Settings/control: native focus, field editing, validation, resizing, persistence and disabled state as appropriate.

For shared screens or palette changes, compare the affected sibling apps under matching theme, locale, activation and control states; see [consistency.md](consistency.md). Inspect the final packaged candidate after the last relevant edit. An older installed updater offering the new version proves availability, not the new updater’s appearance.

Use automated tests for real state-machine/routing regressions. They complement observation; assertion counts do not establish visual acceptance.

## Honest result

Distinguish these states explicitly when applicable:

- source implemented;
- compiled and automated checks passed;
- actual UI path observed (name OS/build and renderer);
- installed version updated;
- release published;
- owner acceptance received.

Do not promote one state into another. If the same visible defect remains, fix it rather than presenting the test result as success. If blocked from a real observation, state the specific missing access/permission/environment and do not claim native delivery or visual correctness. Honor explicit user scope: review-only work reports findings without modifying the app; local design work does not automatically publish a release.
