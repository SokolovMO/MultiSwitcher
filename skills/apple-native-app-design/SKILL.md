---
name: apple-native-app-design
description: Design, implement, or review native macOS app interfaces in SwiftUI or AppKit using current Apple HIG and system-owned components. Use for requests for native Apple appearance, current macOS styling, notifications, dialogs, settings, consistency across sibling apps, or replacing imitation system UI. Not for Apple-inspired websites or backend-only changes.
---

# Apple Native App Design

Deliver a macOS interface that belongs to the target system, with evidence from the real app. User instructions and the requested scope take precedence. Do not expand a small refinement into a framework migration or whole-app redesign.

## Establish what actually renders

Before changing appearance, inspect the source and the actual UI when available:

- Identify the target app/bundle, screen, framework, runtime OS, selected Xcode/SDK, deployment target, and build being viewed. For local macOS, `sw_vers`, `xcodebuild -version`, and `xcrun --sdk macosx --show-sdk-version` are useful. Do not confuse the minimum supported OS with the SDK or runtime.
- Determine whether the problematic surface is system-owned, a standard app component, or custom-drawn. Trace all active branches, including denied permission, errors, foreground/background, and older OS versions. Using AppKit or `NSVisualEffectView` does not by itself make a custom panel a system notification.
- Read any applicable project design decisions. Preserve an explicit brand preference, but identify conflicts when the request is specifically to restore native system appearance.
- Fetch the current official Apple HIG for the component and the actual API/availability documentation before choosing an unfamiliar or version-sensitive implementation. Read only the relevant source links in [references/apple-sources.md](references/apple-sources.md). The skill's creation date is not proof that an API or guideline is still current.

State the renderer and proposed native primitive in one or two sentences. Ask only if the target platform, purpose, or a binding visual choice remains genuinely ambiguous.

## Choose native ownership before styling

Prefer the system component that already has the required behavior:

- Background notification: UserNotifications / `UNUserNotificationCenter`.
- Decision, confirmation, or error: SwiftUI alert/confirmation dialog, or `NSAlert`, attached to its owning window where appropriate.
- Anchored transient controls or information: native popover.
- Settings and structured input: native settings scene, forms, labeled controls, standard buttons and toggles.
- App navigation: native window/title bar, toolbar, sidebar, split view, list or table, chosen for the existing framework.
- Progress and failures inside a task: contextual status/progress/error near that task, rather than a desktop notification for every click.

For notification or alert work, read [references/feedback.md](references/feedback.md) before editing. The examples above are selection criteria, not a mandate to replace functioning components outside scope.

## Let the target OS supply its appearance

Build with the intended current SDK and use documented availability guards for older supported systems. When standard controls unexpectedly differ, verify the actual executable’s linked SDK as well as the selected toolchain; a modern compiler alone does not establish current AppKit rendering. Prefer a classic native fallback on an older OS to a hand-drawn imitation of a newer system.

Keep system typography, semantic colors, control sizes, alignment, spacing, native focus, menus, shortcuts, and locale behavior. Do not impose a universal radius/font/opacity recipe called “Apple design.” Avoid overriding native button cells, painting every control graphite, forcing window backgrounds, or replacing native alert layouts unless the request specifically needs it. Review existing styling hooks: they may run after view creation and undo native appearance.

Standard controls adopt the current design through the framework. Do not pile blur, translucent backgrounds, outlines, shadows, or extra rounded containers onto them. Liquid Glass is not a decorative skin for every content surface. Apply a documented custom effect only when the component's role justifies it and verify its behavior on the target OS.

For app-owned content, custom drawing remains legitimate when native components cannot express the actual task. Explain that local exception and preserve system behavior. An explicitly requested bespoke design can use custom visuals; label them as custom.

Use app-appropriate logo artwork inside app-owned views: correct alpha, no baked Dock halo or duplicate tile. The system notification supplies its own app identity. Do not modify the app's global icon merely to fix an in-app image.

## Keep product decisions consistent

An explicit monochrome or branded palette is a product requirement; native controls do not justify silently dropping it. Prefer supported app accent assets and semantic tokens over replacing native drawing or traversing private framework views. A colored accent is not inherently required by Apple design, and monochrome is not a universal Apple rule.

For a palette change, inconsistent controls, mixed AppKit/SwiftUI UI, or sibling applications, read [references/consistency.md](references/consistency.md). Match common blocks through shared tokens and components, then compare their actual rendered states. Do not promise identical geometry for different product functions.

## Write what fits the task

A status message needs the event and, only if needed, the next action. Put longer recovery detail behind a meaningful action or in the relevant view. Use complete localized messages and preserve variable names. Do not leak English fallback labels into a localized flow.

For diagnostic forms, explain what the check does before its inputs and show its result nearby. Distinguish a local preview from live runtime behavior; keep independent tasks such as a word check and log collection in clearly named groups. Verify both idle and focused field backgrounds.

Use action-specific labels when there is a decision. For a Russian informational acknowledgement, prefer «Понятно» or «Закрыть» as appropriate rather than an accidental English `OK`. Preserve system-provided translations when the system owns the button.

## Verify the real branch, not just a preview

Read [references/verification.md](references/verification.md) for the checks relevant to the changed surface.

A successful build, a source assertion, a mocked notification gateway, or an HTML gallery does not establish native visual correctness. Run the exact app/build and trigger the actual changed path. Capture and inspect the real window or system banner with computer-use tools. A screenshot obtained by caching a detached AppKit view can miss vibrancy, glass, shadows, title bar, and compositing; label it as a component render.

Check supported appearance and accessibility conditions proportionally to the change. If permission, target hardware, or OS access prevents observing the real path, complete the independent work and report that exact limit. Do not present a lookalike as evidence of system delivery. If the observed result still has the reported defect, continue fixing it; do not declare success from passing tests alone.

Report concisely: what now owns the UI, what changed, the actual build/OS and branch observed, evidence, and any unverified path. Distinguish local source, installed app, and published update. A design request does not itself authorize publishing another release. Do not describe “Apple approved” or “pixel perfect” without an actual basis.
