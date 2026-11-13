# multiswitcher — native redesign

Approved reference: `design/approved-concept.jpg`.

## Scope and invariants
- Redesign the existing AppKit application; retain its keyboard engine, rules, dictionary packs, learning, import/export, updater, profile format and permission boundaries.
- Keep user text, dictionary entries, rule patterns, correction output and technical identifiers untouched by presentation casing.
- All owned interface chrome uses lowercase, including localized copy, navigation, popover, alerts and notices. Keyboard designations retain their conventional syntax.
- Keep the application native, with no WebView, Electron or new UI dependencies.

## Screen mapping
| Existing screen | Target |
| --- | --- |
| general | compact grouped controls for enablement, hotkeys, launch and layout pair |
| autocorrection | switches, language context, application exceptions and optional indicator |
| rules | growing native table, unified import/export, quiet source labels |
| learning | candidates and learned rules in the same visual system |
| advanced | manual conversion mode, dictionaries, sound, diagnostics |
| about | version, permissions, updates, recovery and reviewed support |
| new appearance | system/light/dark choice, preview of the actual components |
| native status menu | anchored glass popover with functional nested pages and existing actions |

The concept's statistics page and unimplemented delay slider are not added: they are not current functions. Existing actions remain reachable.

## Design system
- Neutral-only dynamic palette: soft white/light grey and graphite/near black.
- Native visual-effect materials for sidebar, popover and compact notices; opaque accessible fallback when Reduce Transparency is enabled.
- SF system typography at 11/12/13/17/20 pt; semibold only for hierarchy.
- Spacing scale 4/8/12/16/24/32; card radius 14, control radius 7, sidebar selection radius 7.
- Reusable drawn arrow mark, switch, action button, popup control, selected table row, surface and theme manager.
- Foreground contrast and selection shape express state; no colored accent or semantic-color-only status.
- Theme follows macOS by default; manual preference persists and updates all open app windows/popovers/notices.

## Motion
- Short interruptible layer springs for switch thumb and occasional panel feedback.
- Anchored popover uses native animation; content transitions remain under 220 ms.
- Hover and pressed feedback are subtle, with no input-path delay.
- Keyboard conversion remains immediate. Visual confirmation never delays replacement, layout selection, undo or learning.
- Respect Reduce Motion, Reduce Transparency and increased contrast; no display link or permanent animation loop.

## Implementation sequence
1. Preserve and rename project, retain Git history and the existing user profile.
2. Add shared theme, tokens, controls, casing boundary and brand mark.
3. Restyle settings, add appearance choice and consistent layout rules.
4. Replace status presentation with a glass popover driven by existing menu actions.
5. Restyle editor dialogs, notices, context actions and app/status icons.
6. Build with the existing Swift package; run core, reliability and native-map conversion checks.
7. Launch actual app, inspect every page at small and normal sizes, both themes, Cmd+W/Q, keyboard focus and theme changes.
8. Capture real light/dark screenshots and compare with the reference; correct layout/material differences.
9. Audit UI casing without changing user data; sample resource use with settings open and closed.

## Acceptance record
Reviewed on macOS 27.0.1 on 2026-10-23 with repeated actual-window captures and fixes. All seven pages, long-page bottoms, rule dialog, popover, layout submenu and notices were captured in both themes. Core checks: 310 passed; native-layout conversion: 106 assertions passed. Actual table search/selection/arrow checks passed in both themes. Local release/arm64 .app and strict ad-hoc signature verification passed.

Evidence and remaining gates: `design/review-2026-10-23/REPORT.md` and `index.html`. Full XCTest, full-Xcode release packaging, physical menu-bar badge visibility and external-app/VoiceOver accessibility checks remain unconfirmed; do not describe these as passed. Installed production app was not replaced.

## уточнение знака

по выбору пользователя возвращены информативные AЯ / AZ вместо стрелок. в строке меню знак отражает текущую раскладку; светлая и тёмная версии остаются монохромными.
