# Native feedback: choose the surface and own the whole path

Read for notification, toast, popover, alert, permission, or error work.

## System notification

When the request is for a macOS system notification, use UserNotifications. macOS owns the backdrop, position, icon, typography, presentation style, dismissal, Focus behavior and notification history. Supply content, appropriate categories/actions and supported metadata. Do not draw an `NSPanel` or an HTML card and call it a system banner. Do not duplicate the app logo as an attachment or reinsert the app name into every title.

A system notification has a background. A complaint about a gray background does not establish which code path ran. Inspect authorization, delivery outcome, the actual renderer and a screenshot before assigning a cause. Do not promise to remove a system-owned background.

Prefer one current notification per ongoing condition; coalesce updates and withdraw obsolete warnings on recovery. Handle submission/recovery races so late completion cannot leave stale warnings or remove a newer episode. Use meaningful actions, honor presentation settings and avoid unnecessary sound.

For permission not determined/denied, failed delivery, Focus suppression, or a test that has not actually run:

- Keep discoverable status in the relevant existing app/menu surface. Offer a contextual explicit permission/settings action.
- Do not silently substitute a custom desktop notification lookalike or bypass the user's system delivery preferences.
- If a non-system fallback is genuinely required by the product, explain the distinction and implement a clearly app-owned native status surface. A prior request for a system banner is not approval for an imitation overlay.
- Never obtain notification authorization by inventing a successful test. Permission belongs to the user. Follow the environment's approval requirements for the real OS prompt.

The sending app must own the notification center call. A command-line helper with a different bundle context cannot prove the installed app's authorization. A mock gateway can prove routing, cancellation and cleanup; it cannot prove icon appearance or system delivery.

## App-local feedback

Routine actions performed in an open app often need an inline result, selection update, progress indicator, or a short native popover rather than a desktop banner. Select for the real task. Do not persist typed words, private filenames, or other unnecessary sensitive content in Notification Center.

A native `NSPopover` and a manually positioned borderless `NSPanel` with a popover material are different implementations. If native anchoring is suitable, prefer the popover. Respect keyboard focus and avoid activation just to announce a background condition.

## Alerts and sheets

Use system alert/sheet behavior for a decision or error. Preserve native button routing, Return/Escape, default/cancel roles, focus restoration and VoiceOver. Do not replace standard cells or backgrounds just to make an alert “more Apple.” Inspect inherited app-wide styling that can modify native controls on activation or theme changes.

An alert normally includes an app icon; distinguish a system-generated decoration from a baked shadow or a second background in the supplied image. Use clean embedded artwork for app-owned icons, without changing the global Dock icon or hiding a real warning symbol. Do not mistake a transparent-area rendering artifact in a screenshot for the live UI.

Keep urgent blocking errors discoverable. Do not replace them indiscriminately with transient notifications. A sheet should belong to the task's real parent window. Avoid creating detached dialog replicas as the implementation.

## Current official sources

Read the relevant HIG and API pages listed in [apple-sources.md](apple-sources.md). Do not treat this reference as a frozen API specification.
