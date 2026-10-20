import Foundation

/// Shared, deterministic decisions used by automatic and selection correction.
/// Dictionary access stays injected so tests never depend on AppleSpell availability.
public enum LayoutCorrectionEngine {
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
}
