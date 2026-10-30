import AppKit

/// macOS utility typography. Explicit sizes avoid iOS-sized semantic defaults.
enum SystemTypography {
    static func size(_ style: NSFont.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 22
        case .title1: return 21
        case .title2: return 19
        case .title3: return 17
        case .headline: return 13
        case .body: return 12
        case .subheadline: return 12
        case .footnote: return 11
        case .caption1, .caption2: return 11
        default: return 12
        }
    }
    static func font(_ style: NSFont.TextStyle, weight: NSFont.Weight? = nil) -> NSFont {
        .systemFont(ofSize: size(style), weight: weight ?? .regular)
    }
    static func monospaced(_ style: NSFont.TextStyle, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size(style), weight: weight)
    }
}
