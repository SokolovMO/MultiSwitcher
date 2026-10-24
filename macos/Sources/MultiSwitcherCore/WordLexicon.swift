import Foundation

/// A compact, immutable word set loaded from a bundled or user-provided word list.
/// Callers pass a single token; tokenization and confidence decisions stay in the
/// correction engine rather than being hidden in the lexicon.
public struct WordLexicon: Sendable {
    // A sorted flat array uses less resident memory than Set<String> for the large
    // bundled RU/EN lists. Binary search keeps lookups logarithmic and allocation-free.
    private let normalizedWords: [String]

    public init(wordList: String) {
        var words: [String] = wordList.split(whereSeparator: \.isNewline).compactMap { line in
            let word = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, !word.hasPrefix("#"), !word.contains(where: \.isWhitespace) else { return nil }
            return Self.normalized(word)
        }
        words.sort()

        // De-duplicate in place to avoid constructing a second large hash table.
        var writeIndex = 0
        for readIndex in words.indices {
            if writeIndex == 0 || words[writeIndex - 1] != words[readIndex] {
                if writeIndex != readIndex { words[writeIndex] = words[readIndex] }
                writeIndex += 1
            }
        }
        if writeIndex < words.count {
            words.removeLast(words.count - writeIndex)
        }
        normalizedWords = words
    }

    public var count: Int { normalizedWords.count }

    public func contains(_ word: String) -> Bool {
        let target = Self.normalized(word)
        var lowerBound = 0
        var upperBound = normalizedWords.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if normalizedWords[middle] < target {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound < normalizedWords.count && normalizedWords[lowerBound] == target
    }

    private static func normalized(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
    }
}
