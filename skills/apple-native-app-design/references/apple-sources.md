# Official sources to refresh for the task

Starting points checked on 2026-11-10. This is a source index, not a fixed statement of the latest OS or SDK. Fetch the relevant current pages and API availability when using the skill; do not load the whole list for a small task.

- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos): platform conventions and interaction context.
- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass): current-SDK adoption through standard components, removing interfering custom backgrounds, accessibility behavior.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials): functional layers, standard content materials and restrained use of custom effects.
- [Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications): purpose, concise content, actions, privacy and system-owned identity.
- [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts): decisions and errors.
- [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers): anchored transient UI.
- [UserNotifications](https://developer.apple.com/documentation/usernotifications), [permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications): APIs and delivery authorization.
- [NSAlert](https://developer.apple.com/documentation/appkit/nsalert), [NSPopover](https://developer.apple.com/documentation/appkit/nspopover): AppKit-owned presentation and behavior.
- [SwiftUI](https://developer.apple.com/documentation/swiftui), [AppKit](https://developer.apple.com/documentation/appkit): look up the actual component and its availability; do not guess a newer API from the HIG's visual examples.

Apple documentation pages may offer a Markdown version. If a page renders only a JavaScript notice, use its provided Markdown link or the official documentation JSON endpoint rather than claiming the content was read. Preserve the official source URL in the work record. Use local SDK headers/module interfaces to verify what the selected toolchain actually exposes.

For color and packaging consistency:

- [Color](https://developer.apple.com/design/human-interface-guidelines/color): semantic roles, contrast and adaptation.
- [NSAccentColorName](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaccentcolorname): declaring an app accent asset.
- [controlAccentColor](https://developer.apple.com/documentation/appkit/nscolor/controlaccentcolor): resolved native control accent.
