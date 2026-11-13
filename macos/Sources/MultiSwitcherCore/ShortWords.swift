import Foundation

/// Curated high-frequency short words used as a positive signal for automatic
/// layout correction. Two-letter spell-check results are too permissive to trust.
public enum ShortWords {
    private static let russian: Set<String> = [
        "не", "ты", "на", "он", "мы", "вы", "да", "но", "за", "бы", "же", "из",
        "ну", "по", "то", "от", "их", "ее", "её", "со", "ли", "ни", "об", "ей",
        "во", "им", "ко", "те", "та", "уж", "ок", "эй",
    ]
    private static let english: Set<String> = [
        "to", "it", "of", "is", "in", "we", "me", "he", "my", "on", "do", "no",
        "be", "so", "go", "if", "up", "at", "as", "an", "us", "or", "by", "am",
        "ok", "hi", "oh", "ah", "um", "mr", "ya",
        // These English tokens map to common Russian words and are intentionally kept.
        "vs", "dj", "kb", "jr", "bp", "ye", "ds",
    ]

    public static func common(_ language: String) -> Set<String>? {
        switch String(language.prefix(2)).lowercased() {
        case "ru": return russian
        case "en": return english
        default: return nil
        }
    }
}

public enum ShortWordDecision: Equatable, Sendable {
    case convert
    case keep
    case undecided
}

public enum ShortWordPolicy {
    /// Converts only when the target form is a known frequent word and the source
    /// form is not. Common source words are protected symmetrically against ping-pong.
    public static func decide(typed: String, converted: String,
                              currentLanguage: String, otherLanguage: String) -> ShortWordDecision {
        guard typed.count == 2, converted.count == 2,
              let current = ShortWords.common(currentLanguage),
              let other = ShortWords.common(otherLanguage) else { return .undecided }
        if current.contains(typed.lowercased()) { return .keep }
        return other.contains(converted.lowercased()) ? .convert : .undecided
    }
}
