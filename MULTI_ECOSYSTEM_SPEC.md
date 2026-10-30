# multi ecosystem — canonical native layout specification

Both products independently vendor the same `MultiDesignKit.swift`. No shared business logic, sibling path dependency or external UI dependency. Keep these two files byte-identical; their geometry probe runs against the actual AppKit controls. MultiShift currently compiles its native target directly with swiftc, while MultiSwitcher uses SwiftPM. An external shared package would add build orchestration or a sibling checkout dependency; identical vendored UI source keeps both builds self-contained without sharing business models.

## Geometry

- Sidebar expanded 208 pt; compact 60 pt; rows 32 pt with 4 pt separation and 12 pt rail gutters.
- One continuous phase owns the rail, row frames, selection, icons and detail position. No 200 pt subtree hidden underneath another pane, no clipping mask, no offset workaround.
- A critically damped sidebar profile settles in 260 ms. Reversal continues from the currently rendered phase and velocity, bounded to the rail endpoints. Only one finite timer is alive during a transition; it stops at the endpoint. Reduce Motion immediately places the final geometry.
- Manual collapse resizes the outer window by 148 pt while preserving detail width and window height. Expansion restores the paired width; manual compact resizing updates that pair. Theme and ordinary section navigation preserve frame.
- Available content below 440 pt requests compact navigation; above 464 pt restores the user's expanded preference. This hysteresis uses the equivalent expanded content width during a coordinated window resize, so collapse cannot feed back into itself. Manual compact preference persists independently.
- Forms: top-leading with 24 pt page inset. Compact content 560 pt, ordinary settings 640 pt, complex settings 700 pt; the outer AppKit container adds 48 pt for the same page insets. Tables use the complete detail width. Fonts and icons never scale with window size. Short pages do not change window size. Long pages use vertical scrolling.
- Settings windows (content, logical pt): multiswitcher ideal 880×620, minimum 720×500, maximum 1000×800; multishift ideal 840×580, minimum 700×480, maximum 900×760. Compact widths subtract 148 pt from the corresponding minimum/default/maximum; heights are unchanged. Native resize and zoom remain enabled. Fullscreen is disabled for settings. Restore position/size, then constrain it to an available visible screen.

## Style and behavior

Neutral light/dark palette: canvas .972/.075, sidebar .94/.12, card .99/.105, ink .10/.94, secondary .43/.65. System appearance uses native inheritance. Content retains stable identity while themes change.

Native buttons own keyboard activation, accessibility titles, radio selection and up/down navigation. Icon-only rows keep their original titles for VoiceOver and tooltips. Focus remains visibly outlined. Shared rows and icons have the same frames and response in both products.

Forms retain their fields and validation. Labels align to a single leading grid. Enter confirms, Escape cancels, Tab/Shift+Tab use native editing. Small rule dialogs have content-based geometry and no sidebar. User text, file names, paths, rules and keyboard syntax retain case.

Popover target width is 340 pt, constrained by native NSPopover placement. History uses local scrolling and bounded height. Normal text corrections never acquire a new notification. Long file-operation delivery continues through macOS UNUserNotificationCenter and the existing permission/Focus boundary.

## Acceptance evidence

Capture actual windows at minimum, normal, wide, width-only and height-only states in both themes and both sidebar states. Exercise every settings section, 20 full collapse/expand cycles, rapid reversals, resize during transition and the reduced-motion path. Verify row frames at intermediate phases, detail adjacency, stable window frame on navigation and theme changes, then capture real video of those transitions.

Core conversion, file engine, dictionaries, saved operations and profiles are outside this UI change. Test existing algorithm/file suites separately from actual-window geometry checks. A missing framework, system-permission limit or non-reproduced physical interaction must remain an explicit limit in the result.

## Reference and verification boundary

The approved MultiSwitcher reference is `design/approved-concept.jpg`. Actual-window captures and recordings from the new common runtime live in `design/ecosystem-qa-2026-10-23/`; the `final/` directory is the post-fix pass. Earlier redesign evidence is kept separately in `design/review-2026-10-23/`. Visual review uses captured AppKit/SwiftUI windows, never generated mockups. The canonical shared component is `MultiDesignKit.swift`; Core `MultiInterfaceMetrics.swift` carries independently tested constants and off-screen restoration.


## Final window and surface contract — 24 October 2026

The useful settings maximum is enforced by NSWindow.contentMaxSize. NSWindow owns dimensions; neither SwiftUI intrinsic size nor sidebar animation may increase them. Min and max shrink to the current display's visible working area after subtracting native titlebar/toolbar chrome. Restored oversized/offscreen frames are clamped without altering business preferences. Settings zoom targets ideal size; Switcher rules/learning zoom may use the useful maximum. The editor has its own 1440×960 maximum and native resize. It uses a vertical preview/inspector arrangement below 840 pt when a small working area requires it. Native window frame/corners remain system-owned.

Radius tokens live in identical Core MultiInterfaceMetrics: xs=6, sm=9, md=10, lg=14, xl=16, panel=18. Controls and navigation use sm, continuous table containers md, settings cards and inline feedback lg. App marks retain proportional icon geometry; native toggles and progress tracks use radius derived from track height. System controls keep native geometry. Text cells inside tables are not individually rounded. Border and clip use the same surface path. The theme-preview inset is clipped by its own rounded parent.

Spacing tokens: 4/8/12/16/20/24/32. Card padding is 16 horizontally and 12 vertically in AppKit; SwiftUI grouped cards use 16; group gap 12 or 16 by content semantics, page inset 24. No per-window UI magnification is introduced. Fonts and symbols stay at their optical point size while the window changes.

Short settings are top-leading at a bounded readable width. Long settings scroll vertically; rules and learning keep the available viewport and local table scrolling. Sidebar icons use an 18 pt aspect-fit slot; labels fade without changing symbol size. Overlay scrolling preserves the compact slot.

QA review processes use isolated settings/profile directories and never start input monitoring. SwiftUI geometry preferences are collected only under MULTI_ECOSYSTEM_REVIEW; they add no AppKit responder views. WindowServer captures, native backing renders and unavailable physical scenarios are reported separately. A relaunch check saves the native autosave frame, terminates the process and checks restoration in a fresh process.

Sources remain independently vendored: MultiDesignKit, MultiPopoverKit and Core metrics must match byte-for-byte. There is no sibling repository dependency. Functional engines, dictionaries, rule semantics and operation identifiers remain separate. The existing notification policy is unchanged; QA does not send real system notifications.

The shared MultiBoundedWindow owns role limits through both content and frame APIs, including after SwiftUI attempts to reset them. UI callbacks enter MainActor explicitly. Secondary guidance in Switcher learning and automatic-conversion preview is disclosed on demand; validation and results remain inline.

## First correction pool — implementation contract

The permanent MultiSwitcher AЯ artwork lives in MultiDesignKit.MultiBrandIcon. Runtime headers, sidebar, help and application icon use the same renderer; scripts/generate_app_icon.sh exports its ICNS and 10 AppIcon representations. Neither input source nor theme changes the application mark. Dynamic layout badges remain separate.

LayoutPresentationState is a presentation snapshot of selected source ID, language and enabled sources. Existing input-source notifications refresh it; the open popover retains its submenu path and updates checkmarks by source ID, including same-language sources. The store never selects layouts or persists preferences.

MultiPopoverKit retains rows by stable action/operation identity, preserves focus and scroll, and skips redundant size changes. History has a 250 pt viewport ceiling. Its 200 ms cubic ease-out resize updates native content size and body/footer geometry together, with 160 ms opacity feedback using the shared ease-out curve. There are no bitmap snapshots or deferred second resize queue. Unchanged model refreshes cannot cancel an active resize. Reduce Motion applies final geometry immediately. Native popover opening/closing remains system-owned.

MultiInstructionCard and MultiActionButtonStyle are shared by MultiShift welcome and MultiSwitcher help. Help is a nonmodal native window, uses the permanent AЯ icon and reads the actual configured shortcuts when presented. User settings, dictionaries and functional engines remain outside the UI change.

On macOS 27, NSWorkspace verification showed that selecting the precomposed tiled image through CFBundleIconName introduced a second surrounding plate. The bundle deliberately selects the canonical MultiSwitcher.icns through CFBundleIconFile instead; the complete AppIcon catalog remains generated from the same master. There is no dangling CFBundleIconName and no custom FinderInfo icon. System icon lighting remains owned by macOS; global icon caches are untouched.
