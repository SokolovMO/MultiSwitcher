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
    private static let protectedTextExpression = try? NSRegularExpression(
        pattern: #"(?i)```[\s\S]*?```|`[^`\r\n]*`|\b(?:https?://|ftp://|www\.)[^\s]+|\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b|(?:^|\s)(?:/|~/)[^\s]+"#
    )

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
        let lineStart = lineStart(in: source, upTo: caret)
        guard caret > lineStart else { return nil }
        let prefix = NSRange(location: lineStart, length: caret - lineStart)
        let lastWordUnit = source.rangeOfCharacter(from: wordCharacters, options: .backwards, range: prefix)
        guard lastWordUnit.location != NSNotFound else { return nil }
        let end = NSMaxRange(lastWordUnit)
        let beforeEnd = NSRange(location: lineStart, length: end - lineStart)
        let priorNonWord = source.rangeOfCharacter(from: wordCharacters.inverted, options: .backwards, range: beforeEnd)
        let start = priorNonWord.location == NSNotFound ? lineStart : NSMaxRange(priorNonWord)
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
        guard range.length > 0, NSMaxRange(range) <= source.length,
              !isProtected(range, in: text) else { return nil }

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

    /// Finds a recently captured, boundary-terminated line suffix after typing has
    /// continued. It rejects selections, suffixes embedded in a longer word, stale
    /// text far from the caret, and snapshots that do not end at a word boundary.
    /// Newer text remains untouched and the resulting caret stays at its current
    /// position relative to that text.
    public static func planCapturedSuffix(
        text: String,
        selection: NSRange,
        suffix: String,
        maximumDistance: Int = 256
    ) -> TextReplacementPlan? {
        let source = text as NSString
        guard !suffix.isEmpty, selection.length == 0,
              selection.location != NSNotFound, selection.location >= 0,
              selection.location <= source.length, maximumDistance >= 0 else { return nil }

        let suffixLength = (suffix as NSString).length
        guard suffixLength > 0, suffixLength <= selection.location,
              !suffix.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) }),
              isWhitespace((suffix as NSString).character(at: suffixLength - 1)) else { return nil }

        let caret = selection.location
        let currentLineStart = lineStart(in: source, upTo: caret)
        guard caret > currentLineStart else { return nil }
        var searchRange = NSRange(location: currentLineStart, length: caret - currentLineStart)
        while searchRange.length > 0 {
            let found = source.range(of: suffix, options: .backwards, range: searchRange)
            guard found.location != NSNotFound else { return nil }
            let end = NSMaxRange(found)
            if caret - end > maximumDistance { return nil }

            let leftIsBoundary = found.location == 0 || !isWordCharacter(source.character(at: found.location - 1))
            if leftIsBoundary && !isProtected(found, in: text) {
                return TextReplacementPlan(
                    range: found,
                    replacementSelection: NSRange(location: found.location + caret - end, length: 0),
                    replacesExistingSelection: false
                )
            }
            searchRange.length = found.location
        }
        return nil
    }

    /// Finds the exact word captured at a recent word boundary even if the user has
    /// already started typing the next word. The collapsed selection must remain in
    /// the same field, the captured token must still have a word boundary after it,
    /// and the token must be close to the caret. The replacement plan keeps the
    /// current caret position after the text length changes.
    public static func planCapturedToken(
        text: String,
        selection: NSRange,
        token: String,
        boundaryCount: Int = 1,
        maximumDistance: Int = 256
    ) -> TextReplacementPlan? {
        let source = text as NSString
        guard !token.isEmpty, selection.length == 0,
              selection.location != NSNotFound, selection.location >= 0,
              selection.location <= source.length, boundaryCount > 0,
              maximumDistance >= 0 else { return nil }

        let caret = selection.location
        let tokenLength = (token as NSString).length
        guard tokenLength > 0, tokenLength <= caret else { return nil }
        let currentLineStart = lineStart(in: source, upTo: caret)
        guard caret > currentLineStart else { return nil }
        var searchRange = NSRange(location: currentLineStart, length: caret - currentLineStart)

        while searchRange.length > 0 {
            let found = source.range(of: token, options: .backwards, range: searchRange)
            guard found.location != NSNotFound else { return nil }
            let end = NSMaxRange(found)
            if caret - end > maximumDistance { return nil }

            let leftIsBoundary = found.location == 0 || !isWordCharacter(source.character(at: found.location - 1))
            var cursor = end
            var spaces = 0
            while cursor < caret {
                let value = source.character(at: cursor)
                if isHorizontalWhitespace(value) {
                    spaces += 1
                    cursor += 1
                } else if spaces == 0 && isBoundaryPunctuation(value) {
                    cursor += 1
                } else {
                    break
                }
            }

            if leftIsBoundary && spaces >= boundaryCount && !isProtected(found, in: text) {
                return TextReplacementPlan(
                    range: found,
                    replacementSelection: NSRange(
                        location: found.location + caret - end,
                        length: 0
                    ),
                    replacesExistingSelection: false
                )
            }
            searchRange.length = found.location
        }
        return nil
    }

    private static func isWordCharacter(_ value: unichar) -> Bool {
        if value == 95 { return true }
        guard let scalar = UnicodeScalar(value) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    private static func isWhitespace(_ value: unichar) -> Bool {
        guard let scalar = UnicodeScalar(value) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isBoundaryPunctuation(_ value: unichar) -> Bool {
        guard let scalar = UnicodeScalar(value) else { return false }
        return CharacterSet(charactersIn: ",.;:!?)]}\"'»”»").contains(scalar)
    }

    private static func isHorizontalWhitespace(_ value: unichar) -> Bool {
        guard let scalar = UnicodeScalar(value) else { return false }
        return CharacterSet.whitespaces.contains(scalar)
    }

    private static func lineStart(in source: NSString, upTo caret: Int) -> Int {
        guard caret > 0 else { return 0 }
        let range = NSRange(location: 0, length: min(caret, source.length))
        let separator = source.rangeOfCharacter(from: .newlines, options: .backwards, range: range)
        return separator.location == NSNotFound ? 0 : NSMaxRange(separator)
    }

    private static func isProtected(_ candidate: NSRange, in text: String) -> Bool {
        guard candidate.length > 0, let expression = protectedTextExpression else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return expression.matches(in: text, range: range).contains { match in
            match.range.location < NSMaxRange(candidate)
                && candidate.location < NSMaxRange(match.range)
        }
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
