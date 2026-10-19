import Foundation

public struct TextReplacementPlan: Equatable, Sendable {
    public let range: NSRange
    public let replacementSelection: NSRange
    public let replacesExistingSelection: Bool

    public init(range: NSRange, replacementSelection: NSRange, replacesExistingSelection: Bool) {
        self.range = range
        self.replacementSelection = replacementSelection
        self.replacesExistingSelection = replacesExistingSelection
    }
}

public enum TextReplacementPlanner {
    private static let wordCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "_"))

    /// Prefer the user's selection. Otherwise find the last contiguous word before
    /// the caret, skipping trailing spaces and punctuation while leaving them untouched.
    public static func plan(
        text: String,
        selection: NSRange,
        includeKeyboardPunctuation: Bool = false
    ) -> TextReplacementPlan? {
        let source = text as NSString
        guard selection.location != NSNotFound,
              selection.location >= 0,
              selection.location <= source.length else { return nil }

        if selection.length > 0 {
            guard NSMaxRange(selection) <= source.length else { return nil }
            return TextReplacementPlan(
                range: selection,
                replacementSelection: NSRange(location: selection.location, length: 0),
                replacesExistingSelection: true
            )
        }

        let caret = selection.location
        guard caret > 0 else { return nil }
        let prefix = NSRange(location: 0, length: caret)
        let lastWordUnit = source.rangeOfCharacter(from: wordCharacters, options: .backwards, range: prefix)
        guard lastWordUnit.location != NSNotFound else { return nil }
        let end = NSMaxRange(lastWordUnit)
        let beforeEnd = NSRange(location: 0, length: end)
        let priorNonWord = source.rangeOfCharacter(from: wordCharacters.inverted, options: .backwards, range: beforeEnd)
        let start = priorNonWord.location == NSNotFound ? 0 : NSMaxRange(priorNonWord)
        var expandedStart = start
        if includeKeyboardPunctuation {
            // In the US layout these punctuation keys can represent Russian letters
            // in the other layout. Include them only when they join two word fragments;
            // trailing punctuation remains outside the candidate and is preserved.
            let joiners: Set<unichar> = [46, 44, 59, 58] // . , ; :
            while expandedStart >= 2,
                  joiners.contains(source.character(at: expandedStart - 1)),
                  isWordCharacter(source.character(at: expandedStart - 2)) {
                expandedStart -= 2
                while expandedStart > 0 && isWordCharacter(source.character(at: expandedStart - 1)) {
                    expandedStart -= 1
                }
            }
        }
        let range = NSRange(location: expandedStart, length: end - expandedStart)
        guard range.length > 0, NSMaxRange(range) <= source.length else { return nil }

        let suffixDistance = caret - NSMaxRange(range)
        let replacementCaret = range.location + suffixDistance
        return TextReplacementPlan(
            range: range,
            replacementSelection: NSRange(location: replacementCaret, length: 0),
            replacesExistingSelection: false
        )
    }

    /// Plans an exact suffix replacement while preserving the rest of the field.
    /// Used when confirmed context repairs a pending one-letter word with its neighbor.
    public static func planExactSuffix(text: String, selection: NSRange, suffix: String) -> TextReplacementPlan? {
        let source = text as NSString
        guard !suffix.isEmpty, selection.length == 0,
              selection.location == source.length else { return nil }
        let length = (suffix as NSString).length
        guard length <= source.length else { return nil }
        let range = NSRange(location: source.length - length, length: length)
        guard source.substring(with: range) == suffix else { return nil }
        return TextReplacementPlan(
            range: range,
            replacementSelection: NSRange(location: range.location, length: 0),
            replacesExistingSelection: false
        )
    }

    private static func isWordCharacter(_ value: unichar) -> Bool {
        if value == 95 { return true }
        guard let scalar = UnicodeScalar(value) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    public static func replacing(text: String, plan: TextReplacementPlan, with replacement: String) -> String? {
        let source = text as NSString
        guard plan.range.location >= 0, NSMaxRange(plan.range) <= source.length else { return nil }
        return source.replacingCharacters(in: plan.range, with: replacement)
    }

    public static func selectionAfterReplacement(
        plan: TextReplacementPlan,
        replacement: String
    ) -> NSRange {
        if plan.replacesExistingSelection {
            return NSRange(location: plan.range.location, length: (replacement as NSString).length)
        }
        let trailingDistance = plan.replacementSelection.location >= plan.range.location
            ? plan.replacementSelection.location - plan.range.location
            : 0
        return NSRange(
            location: plan.range.location + (replacement as NSString).length + trailingDistance,
            length: 0
        )
    }
}
