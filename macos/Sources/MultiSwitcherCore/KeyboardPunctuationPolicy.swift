import Foundation

/// Separates punctuation at the end of a captured keyboard token from its word.
/// The source glyph `^` is included because Shift+6 produces `:` in Russian and
/// `^` in the US layout; without splitting it, the spelling check sees `word:`.
public enum KeyboardPunctuationPolicy {
    private static let trailingCharacters: Set<Character> = [
        ",", ".", "!", "?", ";", ":", ")", "`", "[", "]", "^"
    ]

    public static func splitTrailing(from text: String) -> (coreLength: Int, suffix: String) {
        var core = text[...]
        while let last = core.last, trailingCharacters.contains(last) {
            core = core.dropLast()
        }
        return (core.count, String(text.dropFirst(core.count)))
    }
}
