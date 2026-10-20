import Foundation

/// A compact, immutable word set loaded from a bundled or user-provided word list.
/// Callers pass a single token; tokenization and confidence decisions stay in the
/// correction engine rather than being hidden in the lexicon.
public struct WordLexicon: Sendable {
    private let normalizedWords: Set<String>

    public init(wordList: String) {
        normalizedWords = Set(wordList.split(whereSeparator: \.isNewline).compactMap { line in
            let word = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, !word.hasPrefix("#"), !word.contains(where: \.isWhitespace) else { return nil }
            return Self.normalized(word)
        })
    }

    public var count: Int { normalizedWords.count }

    public func contains(_ word: String) -> Bool {
        normalizedWords.contains(Self.normalized(word))
    }

    private static func normalized(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
    }
}
