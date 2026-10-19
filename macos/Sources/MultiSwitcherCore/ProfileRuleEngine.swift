import Foundation

public enum ProfileRuleDecision: Equatable, Sendable {
    case none
    case neverConvert
    case alwaysConvert
    case replace(String)
}

/// Evaluates typed local rules while keeping unverified Punto rows on the conservative exact fallback.
public enum ProfileRuleEngine {
    public static func evaluate(typed: String, converted: String, rules: [ProfileRule]) -> ProfileRuleDecision {
        let orderedRules = rules.enumerated().sorted { lhs, rhs in
            func priority(_ origin: ProfileRuleOrigin) -> Int {
                switch origin { case .user: return 0; case .learned: return 1; case .punto: return 2 }
            }
            let lp = priority(lhs.element.origin), rp = priority(rhs.element.origin)
            return lp == rp ? lhs.offset < rhs.offset : lp < rp
        }
        for (_, rule) in orderedRules where rule.enabled && !rule.pattern.isEmpty {
            switch rule.action {
            case .neverConvert:
                if matches(rule.pattern, in: typed, mode: rule.match, caseSensitive: rule.caseSensitive)
                    || matches(rule.pattern, in: converted, mode: rule.match, caseSensitive: rule.caseSensitive) {
                    return .neverConvert
                }
            case .alwaysConvert:
                guard rule.origin == .user else { continue }
                if matches(rule.pattern, in: converted, mode: rule.match, caseSensitive: rule.caseSensitive) {
                    return .alwaysConvert
                }
            case .replace:
                guard rule.origin == .user, let replacement = rule.replacement, !replacement.isEmpty else { continue }
                if matches(rule.pattern, in: typed, mode: rule.match, caseSensitive: rule.caseSensitive) {
                    return .replace(replacement)
                }
            }
        }
        return .none
    }

    public static func isValidPattern(_ pattern: String, mode: ProfileRuleMatch) -> Bool {
        guard !pattern.isEmpty, pattern.count <= 512 else { return false }
        guard mode == .regularExpression else { return true }
        guard pattern.count <= 128, isConservativeRegex(pattern),
              (try? NSRegularExpression(pattern: pattern)) != nil else { return false }
        return true
    }

    public static func matches(_ pattern: String, in candidate: String,
                               mode: ProfileRuleMatch, caseSensitive: Bool) -> Bool {
        guard !pattern.isEmpty, !candidate.isEmpty else { return false }
        if mode == .regularExpression {
            guard pattern.count <= 128, candidate.count <= 1024, isConservativeRegex(pattern) else { return false }
            var options: NSRegularExpression.Options = []
            if !caseSensitive { options.insert(.caseInsensitive) }
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
            let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
            return expression.firstMatch(in: candidate, range: range) != nil
        }

        let lhs = caseSensitive ? candidate.precomposedStringWithCanonicalMapping
                                : candidate.precomposedStringWithCanonicalMapping.lowercased()
        let rhs = caseSensitive ? pattern.precomposedStringWithCanonicalMapping
                                : pattern.precomposedStringWithCanonicalMapping.lowercased()
        switch mode {
        case .exact, .unverifiedPunto:
            return lhs == rhs
        case .prefix:
            return lhs.hasPrefix(rhs)
        case .contains:
            return lhs.contains(rhs)
        case .regularExpression:
            return false
        }
    }

    /// Accept a small, bounded regular-expression subset in the keyboard event path.
    private static func isConservativeRegex(_ pattern: String) -> Bool {
        let characters = Array(pattern)
        guard !characters.isEmpty else { return false }
        var index = 0
        var escaped = false
        var inCharacterClass = false
        var hasAtom = false
        var justQuantified = false
        var quantifierCount = 0

        while index < characters.count {
            let character = characters[index]
            if inCharacterClass {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "]" { inCharacterClass = false; hasAtom = true; justQuantified = false }
                index += 1
                continue
            }

            if escaped {
                // Backreferences and Unicode property groups have context-dependent cost/syntax.
                if character.isNumber || "kgpP".contains(character) { return false }
                escaped = false
                hasAtom = true
                justQuantified = false
                index += 1
                continue
            }

            switch character {
            case "\\":
                escaped = true
            case "[":
                guard !inCharacterClass else { return false }
                inCharacterClass = true
            case "]", "(", ")", "|":
                return false
            case "^":
                guard index == 0 else { return false }
                hasAtom = false
            case "$":
                guard index == characters.count - 1 else { return false }
                hasAtom = false
            case "*", "+", "?", "{":
                guard hasAtom, !justQuantified, quantifierCount < 2 else { return false }
                if character == "{" {
                    var end = index + 1
                    var digits = ""
                    while end < characters.count, characters[end].isNumber {
                        digits.append(characters[end]); end += 1
                    }
                    guard !digits.isEmpty, let lower = Int(digits), lower <= 1000 else { return false }
                    if end < characters.count, characters[end] == "," {
                        end += 1
                        var upperDigits = ""
                        while end < characters.count, characters[end].isNumber {
                            upperDigits.append(characters[end]); end += 1
                        }
                        guard !upperDigits.isEmpty, let upper = Int(upperDigits), upper <= 1000,
                              upper >= lower else { return false }
                    }
                    guard end < characters.count, characters[end] == "}" else { return false }
                    index = end
                }
                quantifierCount += 1
                justQuantified = true
            default:
                hasAtom = true
                justQuantified = false
            }
            index += 1
        }
        return !escaped && !inCharacterClass
    }
}
