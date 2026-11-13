import Foundation

/// Presentation-only casing; call before interpolating user data.
public enum InterfaceText {
    public static func chrome(_ text: String) -> String {
        let preserved = ["Option", "Command", "Shift", "Control", "Caps Lock", "Backspace",
                         "Return", "Enter", "Delete", "Escape", "Tab", "Space", "Fn",
                         "iPhone", "iPad", "iMac", "iCloud", "AppleSpell", "AppleScript",
                         "AZ", "AЯ", "ABC", "RU", "EN", "⌘W", "⌘Q", "⌘Z"]
        var result = text
        var replacements: [(String, String)] = []
        for (index, token) in preserved.enumerated() where result.contains(token) {
            let marker = "\u{E000}\(index)\u{E001}"
            let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: token) + "(?![\\p{L}\\p{N}_])"
            if let expression = try? NSRegularExpression(pattern: pattern) {
                result = expression.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: marker)
            }
            replacements.append((marker, token))
        }
        result = result.lowercased()
        for (marker, token) in replacements { result = result.replacingOccurrences(of: marker, with: token) }
        return result
    }
}

