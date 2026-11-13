import Foundation

/// Recognizes Spotlight independently of a localized window title or the frontmost app.
public enum SpotlightTargetClassifier {
    public static let bundleIdentifier = "com.apple.Spotlight"
    /// On this macOS 27 machine, live inspection with Spotlight open reported the
    /// focused AXTextField under Apple's Siri/Campo process while the prior app stayed
    /// frontmost. Treat Campo as Spotlight only for a text/search role; AX checks below
    /// still have to verify the field's value, selection and editability.
    public static let campoBundleIdentifier = "com.apple.campo"

    public static func isSpotlight(
        frontmostBundleIdentifier: String?,
        windowOwnerNames: [String],
        windowOwnerBundleIdentifiers: [String] = [],
        focusedElementBundleIdentifier: String? = nil,
        focusedElementRole: String? = nil
    ) -> Bool {
        let focusedRoleIsSearchField = focusedElementRole == "AXTextField"
            || focusedElementRole == "AXSearchField"
        if focusedRoleIsSearchField,
           [bundleIdentifier, "com.apple.systemuiserver", campoBundleIdentifier]
            .contains(focusedElementBundleIdentifier ?? "") {
            return true
        }
        if frontmostBundleIdentifier == bundleIdentifier
            || windowOwnerBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }
        return windowOwnerNames.contains {
            $0.localizedCaseInsensitiveCompare("Spotlight") == .orderedSame
        }
    }
}
