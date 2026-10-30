import Foundation

/// Shared, deterministic decisions used by automatic and selection correction.
/// Dictionary access stays injected so tests never depend on AppleSpell availability.
public enum LayoutCorrectionEngine {
    public enum DictionaryDecision: Equatable, Sendable {
        case convert
        case keepBecauseTargetIsNotAWord
        case keepBecauseSourceIsAWord
        case undecidedBecauseTargetDictionaryIsUnavailable
    }

    /// Shared conservative dictionary decision for automatic correction. Keeping the
    /// result distinct from dictionary availability prevents a missing/unready
    /// dictionary from being mistaken for proof that a candidate is misspelled.
    public static func dictionaryDecision(
        typed: String,
        converted: String,
        currentLanguage: String,
        targetLanguage: String,
        isLanguageAvailable: (String) -> Bool,
        isValidWord: (String, String) -> Bool
    ) -> DictionaryDecision {
        guard isLanguageAvailable(targetLanguage) else {
            return .undecidedBecauseTargetDictionaryIsUnavailable
        }
        guard isValidWord(converted, targetLanguage) else {
            return .keepBecauseTargetIsNotAWord
        }
        if isLanguageAvailable(currentLanguage), isValidWord(typed, currentLanguage) {
            return .keepBecauseSourceIsAWord
        }
        return .convert
    }

    /// Curated technical and product names that spell-check dictionaries often reject.
    /// Exact canonical forms are used for output so layout correction does not produce
    /// variants such as `iphone` or `GitHub` with damaged capitalization.
    public static let trustedTerms: [String] = [
        "iPhone", "iPad", "iMac", "iCloud", "iMessage", "macOS", "MacBook", "AirPods",
        "GitHub", "GitLab", "YouTube", "OpenAI", "ChatGPT", "WhatsApp", "LinkedIn",
        "JavaScript", "TypeScript", "AppKit", "SwiftUI", "AppleScript", "Figma", "Cursor",
        "Codex", "Google", "Chrome", "Xcode", "Notion", "Telegram", "Slack",
    ]

    public enum TrustedTermDecision: Equatable, Sendable {
        case preserve
        case convert(String)
    }

    /// Returns the canonical spelling for a trusted product or technical term.
    public static func canonicalTrustedTerm(for text: String) -> String? {
        trustedTerms.first { $0.caseInsensitiveCompare(text) == .orderedSame }
    }

    /// Preserve a trusted term in place, or return its canonical spelling when the
    /// opposite-layout candidate is a trusted term. All-caps/code protection remains
    /// the caller's responsibility so acronyms such as `IPHONE` are not rewritten.
    public static func trustedTermDecision(typed: String, converted: String) -> TrustedTermDecision? {
        if canonicalTrustedTerm(for: typed) != nil {
            return .preserve
        }
        if let canonical = canonicalTrustedTerm(for: converted) {
            return .convert(canonical)
        }
        return nil
    }

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
        currentWordWasConfirmed: Bool,
        hasAmbiguousShortWordCorrection: Bool = false
    ) -> Bool {
        guard currentWordWasConfirmed, original != corrected else { return false }
        return hasAmbiguousShortWordCorrection || original.split(whereSeparator: \.isWhitespace).contains { token in
            token.count == 1 && token.first?.isLetter == true
        }
    }

    /// A recognized product name should not flip the language of a sentence. Keep the
    /// user's current Russian input source when the prefix contains clear Russian context.
    public static func shouldPreserveInputLanguageForTrustedName(
        corrected: String,
        prefix: String,
        currentLanguage: String
    ) -> Bool {
        guard String(currentLanguage.prefix(2)).lowercased() == "ru",
              canonicalTrustedTerm(for: corrected) != nil else { return false }
        let words = prefix.split { !$0.isLetter }
        let russianWords = words.filter { word in
            word.contains { (0x0400...0x04FF).contains($0.unicodeScalars.first?.value ?? 0) }
                && word.allSatisfy { (0x0400...0x04FF).contains($0.unicodeScalars.first?.value ?? 0) }
        }
        let latinWords = words.filter { word in
            word.contains { (0x0041...0x007A).contains($0.unicodeScalars.first?.value ?? 0) }
        }
        return russianWords.count >= 2 && latinWords.isEmpty
    }

    /// A single dictionary-confirmed foreign word inside an otherwise single-script
    /// RU/EN phrase should repair the token without changing the user's input source.
    /// The user can switch layouts explicitly; mixed or unsupported context stays neutral.
    public static func shouldPreserveInputLanguageForContextualWord(
        corrected: String,
        prefix: String,
        currentLanguage: String,
        targetLanguage: String,
        targetIsConfirmedWord: Bool,
        requiredConsecutiveTargetWords: Int = 2,
        isKnownTargetWord: (String, String) -> Bool = { _, _ in false }
    ) -> Bool {
        guard targetIsConfirmedWord, !corrected.isEmpty else { return false }
        let current = String(currentLanguage.prefix(2)).lowercased()
        let target = String(targetLanguage.prefix(2)).lowercased()
        guard (current == "ru" && target == "en") || (current == "en" && target == "ru") else {
            return false
        }

        // Only recent context can describe the language the user is writing now.
        // Bounding this scan also keeps the keyboard path independent of a long field.
        let recentContext = String(prefix.precomposedStringWithCanonicalMapping.suffix(256))
        let words = Array(recentContext.split { !$0.isLetter }.suffix(5))
        guard !words.isEmpty else { return false }

        func isConfirmedTargetWord(_ word: String) -> Bool {
            let scalars = Array(word.unicodeScalars)
            return !scalars.isEmpty
                && scalars.allSatisfy { isWordScalar($0, language: target) }
                && isKnownTargetWord(word, target)
        }

        // Include the word currently being corrected when looking for a language
        // transition. The threshold is configurable, but bounded to one or two
        // words so this stays predictable and cheap on the keyboard path.
        let trailingConfirmedTargetWords = words.reversed().prefix {
            isConfirmedTargetWord(String($0))
        }.count
        let currentWordConfirmsTargetLanguage = targetIsConfirmedWord
            && isConfirmedTargetWord(corrected)
        let requiredRun = min(2, max(1, requiredConsecutiveTargetWords))
        if trailingConfirmedTargetWords + (currentWordConfirmsTargetLanguage ? 1 : 0) >= requiredRun {
            return false
        }

        // A language transition is confirmed only by a contiguous run at the end of
        // the context. Two target-language words elsewhere in the sentence are not a
        // signal: e.g. "привет hello привет there language" must keep Russian active.
        let hasCurrentLanguageContext = words.contains { word in
            let scalars = Array(word.unicodeScalars)
            return !scalars.isEmpty && scalars.allSatisfy { isWordScalar($0, language: current) }
        }
        return hasCurrentLanguageContext
    }

    private static func isWordScalar(_ scalar: Unicode.Scalar, language: String) -> Bool {
        switch language {
        case "ru":
            return (0x0400...0x052F).contains(scalar.value)
                || (0x2DE0...0x2DFF).contains(scalar.value)
                || (0xA640...0xA69F).contains(scalar.value)
        case "en":
            return (0x0041...0x024F).contains(scalar.value)
                || (0x1E00...0x1EFF).contains(scalar.value)
        default:
            return false
        }
    }
}
