import Foundation

public enum AppendedInputRejectionReason: String, Equatable, Sendable {
    case historyExpired = "history-expired"
    case countOutOfRange = "count-out-of-range"
    case generationMismatch = "generation-mismatch"
    case missingCharacter = "missing-character"
    case suffixCountMismatch = "suffix-count-mismatch"
    case unsupportedCharacter = "unsupported-character"
}

public enum AppendedInputDecision: Equatable, Sendable {
    case preserve(String)
    case reject(AppendedInputRejectionReason)
}

public enum KeyboardUnicodeDisposition: Equatable, Sendable {
    case keyCodeOnly
    case character(Character)
    case invalidate
}

/// Validates the exact printable text entered after an automatic-conversion boundary.
/// Non-text edits are not represented in this suffix and invalidate the generation.
public enum AppendedInputPolicy {
    /// An event must describe exactly one grapheme. If a remote/input-method event
    /// carries several characters at once, tracking only its first Character would
    /// make a later replacement silently drop the rest of that event.
    public static func singleCharacter(in text: String) -> Character? {
        guard text.count == 1 else { return nil }
        return text.first
    }

    /// Classify event text before it enters the tracked word buffer. An event with
    /// no Unicode payload may use its physical key code; present but multi-character,
    /// composed, truncated, or unsafe text must invalidate the current snapshot.
    public static func classifyUnicodeEvent(
        text: String?,
        wasTruncated: Bool = false
    ) -> KeyboardUnicodeDisposition {
        guard !wasTruncated else { return .invalidate }
        guard let text, !text.isEmpty else { return .keyCodeOnly }
        guard let character = singleCharacter(in: text),
              isSafePrintableCharacter(character) else { return .invalidate }
        return .character(character)
    }

    public static func decide(
        generationDelta: UInt64,
        trackedKeyCount: Int,
        suffix: String?,
        historyAvailable: Bool = true,
        maximumKeyCount: Int = 64
    ) -> AppendedInputDecision {
        guard historyAvailable else { return .reject(.historyExpired) }
        guard trackedKeyCount >= 0, trackedKeyCount <= maximumKeyCount else {
            return .reject(.countOutOfRange)
        }
        guard generationDelta == UInt64(trackedKeyCount) else {
            return .reject(.generationMismatch)
        }
        guard let suffix else { return .reject(.missingCharacter) }
        guard suffix.count == trackedKeyCount else { return .reject(.suffixCountMismatch) }
        guard suffix.allSatisfy(isSafePrintableCharacter) else {
            return .reject(.unsupportedCharacter)
        }
        return .preserve(suffix)
    }

    public static func isSafePrintableCharacter(_ character: Character) -> Bool {
        isSafeSingleScalarText(character)
    }

    /// Validate a typed suffix reconstructed from the captured key buffer when a
    /// platform keyboard event did not provide a complete Unicode character. The
    /// caller must prove that the captured line prefix is unchanged and that every
    /// key event since the boundary is still represented in the buffer.
    public static func canPreserveRecoveredTypedSuffix(
        generationDelta: UInt64,
        recoveredKeyCount: Int,
        suffix: String?,
        capturedPrefixMatches: Bool,
        allKeyEventsAreRecoverable: Bool = true,
        maximumKeyCount: Int = 64
    ) -> Bool {
        guard allKeyEventsAreRecoverable,
              capturedPrefixMatches,
              recoveredKeyCount >= 0,
              recoveredKeyCount <= maximumKeyCount,
              generationDelta == UInt64(recoveredKeyCount),
              let suffix,
              (recoveredKeyCount == 0) == suffix.isEmpty,
              suffix.count <= recoveredKeyCount else { return false }
        return suffix.allSatisfy(isSafePrintableCharacter)
    }

    public static func canPreserveTypedSuffix(
        generationDelta: UInt64,
        trackedKeyCount: Int,
        suffix: String,
        maximumKeyCount: Int = 64
    ) -> Bool {
        if case .preserve = decide(
            generationDelta: generationDelta,
            trackedKeyCount: trackedKeyCount,
            suffix: suffix,
            maximumKeyCount: maximumKeyCount
        ) {
            return true
        }
        return false
    }

    private static func isSafeSingleScalarText(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber,
             .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol:
            return true
        case .spaceSeparator:
            return scalar.value == 0x20
        default:
            return false
        }
    }
}
