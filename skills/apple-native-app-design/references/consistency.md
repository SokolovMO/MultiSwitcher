# Consistency across native components and sibling apps

Read for palette corrections, mismatched standard controls, mixed AppKit/SwiftUI interfaces, or shared screens across apps. Apply only to the requested surfaces.

## Establish the product contract

Read existing design decisions and the user's latest instructions. Identify shared semantic roles: canvas, sidebar, content surface, primary and secondary text, divider, selection, accent, input and focus. Preserve theme, locale, casing and accessibility requirements without modifying user content.

Keep those roles in one canonical palette. Reuse the same component for equivalent tasks when practical. In independently distributed repositories, identical vendored source is acceptable: record its owner and check parity so it does not silently drift. Avoid a framework migration or a new dependency solely to share a few controls.

For common blocks such as Appearance, About, Updates and deletion preferences, align grouping, label wording, typography, control size, spacing, and action hierarchy. Product-specific content may differ. Similar screenshots or matching numeric tokens alone do not establish matching behavior or rendering.

## Diagnose before repainting

When the same standard control looks different, inspect:

- Actual framework/control type, bezel or button style, control size, default-action role, enabled state, window activation and effective appearance.
- SwiftUI tint inheritance versus AppKit accent resolution. A SwiftUI `.tint` does not establish that native NSButton checkboxes, progress indicators or updater windows use that color.
- App asset catalog compilation and `NSAccentColorName` in the exact packaged app. For a requested neutral app accent, use supported light/dark color assets and verify the resolved native accent from the app's own process. Do not change global macOS accent settings.
- Actual Mach-O metadata: `otool -l <app>/Contents/MacOS/<executable>` exposes `LC_BUILD_VERSION` and its `minos` and `sdk`. Selected Xcode/SDK, minimum supported OS and linked SDK are separate facts. Unexpected legacy rendering may come from incorrect linked SDK metadata; correct the build pipeline rather than painting a newer-looking control over it. Verify availability and older-OS compatibility before changing linker settings; never hardcode a future SDK version into the skill.
- Styling hooks that run after construction, including field-editor backgrounds, custom button cells, forced window fills and private framework traversal.

Use the narrowest correction that preserves standard menu tracking, focus, Return/Escape, disabled state, selection and accessibility. AppKit-backed SwiftUI controls can be appropriate for a demonstrated parity gap; check binding updates, target/action, intrinsic sizing, labels and enabled state. Do not bridge every control preemptively.

## Define ownership boundaries

A product accent can style app-owned standard controls through documented mechanisms. Screen-sharing/privacy indicators, window traffic lights and Notification Center surfaces remain system-owned; do not hide, recolor or imitate them to satisfy a branding request. Explain a visible system-owned exception when relevant.

For Sparkle, distinguish native updater controls from HTML release-note content. Use a consistent readable font and neutral, visibly underlined links in notes when monochrome is required; provide light/dark colors. Avoid replacing Sparkle's private cells or turning all actions into equally prominent buttons. App accent packaging and actual SDK metadata should be checked before considering custom UI.

An updater window shown by an installed old build still belongs to that old build. A new feed can change release notes, but publishing cannot retroactively change its executable or accent assets. State when the fix takes effect, and verify the new build's own updater path when feasible.

## Compare actual states

Compare equivalent screens in both apps under the same theme, locale, activation and control state. Cover the changed cases: idle/focused fields, on/off checkboxes and switches, selected/expanded menus, primary/secondary actions, and disabled controls. Include narrow-window and long-copy cases where layout changed.

For diagnostics, keep purpose, input and output adjacent. Clearly separate independent actions such as a local word preview and log collection. A gray focused field may be a field-editor override, not a disabled state; inspect it before assigning a cause. Do not claim a local preview proves production typing or file operations.

If real screenshots still show the reported inconsistency, continue investigating. Equal RGB values, identical source files, build success and unit tests are supporting evidence, not substitutes for the visual comparison. Keep any unverified path explicit.
