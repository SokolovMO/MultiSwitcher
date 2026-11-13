import Foundation

/// Conservative automatic-layout handling for a single hyphenated token.
/// Both sides are checked by segments so `rfr-nj` can map to `как-то` without
/// treating the hyphen itself as punctuation or accepting arbitrary compounds.
public enum HyphenatedTokenPolicy {
    public enum Decision: Equatable, Sendable {
        case convert
        case keep
        case undecided
    }

    /// Keep malformed runs in one captured token so the detector can reject the
    /// whole candidate instead of resetting and correcting only its final fragment.
    public static func shouldTrackHyphen(after previousCharacter: Character?) -> Bool {
        previousCharacter?.isLetter == true || previousCharacter == "-"
    }

    public static func decide(
        typed: String,
        converted: String,
        currentLanguage: String,
        targetLanguage: String,
        isValidWord: (String, String) -> Bool
    ) -> Decision {
        let typedParts = typed.split(separator: "-", omittingEmptySubsequences: false)
        let convertedParts = converted.split(separator: "-", omittingEmptySubsequences: false)
        guard typed.contains("-"), typedParts.count == convertedParts.count,
              typedParts.count >= 2,
              zip(typedParts, convertedParts).allSatisfy({ $0.count == $1.count }),
              typedParts.allSatisfy(isEligibleSegment),
              convertedParts.allSatisfy(isEligibleSegment) else {
            return .undecided
        }

        let sourceValid = typedParts.allSatisfy {
            isValidSegment(String($0), language: currentLanguage, isValidWord: isValidWord)
        }
        let targetValid = convertedParts.allSatisfy {
            isValidSegment(String($0), language: targetLanguage, isValidWord: isValidWord)
        }

        if targetValid && !sourceValid { return .convert }
        if sourceValid { return .keep }
        return .undecided
    }

    private static func isEligibleSegment(_ segment: Substring) -> Bool {
        segment.count >= 2 && segment.allSatisfy(\.isLetter)
    }

    private static func isValidSegment(
        _ word: String,
        language: String,
        isValidWord: (String, String) -> Bool
    ) -> Bool {
        if word.count == 2 {
            return ShortWords.common(language)?.contains(word.lowercased()) == true
        }
        return isValidWord(word.lowercased(), String(language.prefix(2)).lowercased())
    }
}
