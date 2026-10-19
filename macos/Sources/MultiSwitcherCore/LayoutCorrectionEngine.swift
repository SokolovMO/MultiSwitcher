import Foundation

/// Shared, deterministic decisions used by automatic and selection correction.
/// Dictionary access stays injected so tests never depend on AppleSpell availability.
public enum LayoutCorrectionEngine {
    public struct Candidate: Equatable, Sendable {
        public let text: String
        public let language: String
        public let changesLayout: Bool

        public init(text: String, language: String, changesLayout: Bool) {
            self.text = text
            self.language = language
            self.changesLayout = changesLayout
        }
    }

    public static func isMixedScript(_ text: String) -> Bool {
        var hasLatin = false
        var hasCyrillic = false
        for scalar in text.unicodeScalars {
            if (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) {
                hasLatin = true
            } else if (0x0400...0x04FF).contains(scalar.value) {
                hasCyrillic = true
            }
        }
        return hasLatin && hasCyrillic
    }

    /// Selects a single dictionary-confirmed direction for mixed-script input.
    /// The caller constructs candidates with the installed keyboard-layout pair.
    public static func uniqueMixedCandidate(
        typed: String,
        currentLanguage: String,
        oppositeLanguage: String,
        currentCandidate: String,
        oppositeCandidate: String,
        isValidWord: (String, String) -> Bool
    ) -> Candidate? {
        guard isMixedScript(typed) else { return nil }
        let currentValid = currentCandidate != typed && isValidWord(currentCandidate, currentLanguage)
        let oppositeValid = oppositeCandidate != typed && isValidWord(oppositeCandidate, oppositeLanguage)
        guard currentValid != oppositeValid else { return nil }

        if currentValid {
            return Candidate(text: currentCandidate, language: currentLanguage, changesLayout: false)
        }
        return Candidate(text: oppositeCandidate, language: oppositeLanguage, changesLayout: true)
    }

    /// Context may repair a short leading word only after a later word was independently
    /// confirmed for correction. This prevents single letters from acting as a signal.
    public static func shouldApplyContextualRewrite(
        original: String,
        corrected: String,
        currentWordWasConfirmed: Bool
    ) -> Bool {
        guard currentWordWasConfirmed, original != corrected else { return false }
        return original.split(whereSeparator: \.isWhitespace).contains { token in
            token.count == 1 && token.first?.isLetter == true
        }
    }
}
