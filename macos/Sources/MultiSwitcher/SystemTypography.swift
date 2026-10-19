import AppKit

/// Semantic system typography for custom AppKit controls.
/// Preferred text styles follow the user's macOS font-size and accessibility settings.
enum SystemTypography {
    static func font(_ style: NSFont.TextStyle, weight: NSFont.Weight? = nil) -> NSFont {
        let preferred = NSFont.preferredFont(forTextStyle: style)
        guard let weight else { return preferred }
        return NSFont.systemFont(ofSize: preferred.pointSize, weight: weight)
    }

    static func monospaced(_ style: NSFont.TextStyle, weight: NSFont.Weight = .regular) -> NSFont {
        let preferred = NSFont.preferredFont(forTextStyle: style)
        return NSFont.monospacedSystemFont(ofSize: preferred.pointSize, weight: weight)
    }
}
