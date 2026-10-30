import Foundation

public enum ProfileRuleDecision: Equatable, Sendable {
    case none
    case neverConvert
    case alwaysConvert
    case replace(String)
}

fileprivate struct PreparedProfileRule: @unchecked Sendable {
    let rule: ProfileRule
    let normalizedPattern: String
    let regularExpression: NSRegularExpression?
}

/// Immutable, pre-normalized rules for repeated decisions on the keyboard path.
/// Rebuild this only when the profile or legacy rule lists change.
public struct CompiledProfileRules: @unchecked Sendable {
    fileprivate let byOrigin: [ProfileRuleOrigin: [PreparedProfileRule]]

    fileprivate init(_ rules: [ProfileRule]) {
        var grouped: [ProfileRuleOrigin: [PreparedProfileRule]] = [:]
        for rule in rules where rule.enabled && !rule.pattern.isEmpty {
            let canonical = rule.pattern.precomposedStringWithCanonicalMapping
            var expression: NSRegularExpression?
            if rule.match == .regularExpression,
               rule.pattern.count <= 128,
               ProfileRuleEngine.isConservativeRegex(rule.pattern) {
                var options: NSRegularExpression.Options = []
                if !rule.caseSensitive { options.insert(.caseInsensitive) }
                expression = try? NSRegularExpression(pattern: rule.pattern, options: options)
            }
            grouped[rule.origin, default: []].append(PreparedProfileRule(
                rule: rule,
                normalizedPattern: rule.caseSensitive ? canonical : canonical.lowercased(),
                regularExpression: expression
            ))
        }
        byOrigin = grouped
    }
}

/// Evaluates typed local rules while keeping unverified Punto rows on the conservative exact fallback.
public enum ProfileRuleEngine {
    private struct NormalizedCandidate {
        let original: String
        let folded: String

        init(_ text: String) {
            original = text.precomposedStringWithCanonicalMapping
            folded = original.lowercased()
        }

        func value(caseSensitive: Bool) -> String { caseSensitive ? original : folded }
    }

    public static func compile(_ rules: [ProfileRule]) -> CompiledProfileRules {
        CompiledProfileRules(rules)
    }

    public static func evaluate(typed: String, converted: String, rules: [ProfileRule]) -> ProfileRuleDecision {
        evaluate(typed: typed, converted: converted, rules: compile(rules))
    }

    public static func evaluate(typed: String, converted: String,
                                rules: CompiledProfileRules) -> ProfileRuleDecision {
        let typedCandidate = NormalizedCandidate(typed)
        let convertedCandidate = NormalizedCandidate(converted)
        // A no-convert rule for the desired output (for example, "chrono24")
        // must not mask a more specific replacement for the typed source. Keep
        // no-convert rules on the typed source authoritative, then let a matching
        // user replacement take precedence over output-side rules.
        let hasMatchingUserReplacement = (rules.byOrigin[.user] ?? []).contains { prepared in
            guard prepared.rule.action == .replace,
                  let replacement = prepared.rule.replacement, !replacement.isEmpty else { return false }
            return matches(prepared, candidate: typedCandidate)
        }
        for origin in [ProfileRuleOrigin.user, .learned, .punto] {
            for prepared in rules.byOrigin[origin] ?? [] {
                let rule = prepared.rule
                switch rule.action {
                case .neverConvert:
                    if matches(prepared, candidate: typedCandidate)
                        || (!hasMatchingUserReplacement && matches(prepared, candidate: convertedCandidate)) {
                        return .neverConvert
                    }
                case .alwaysConvert:
                    guard rule.origin == .user else { continue }
                    if matches(prepared, candidate: convertedCandidate) {
                        return .alwaysConvert
                    }
                case .replace:
                    guard rule.origin == .user, let replacement = rule.replacement, !replacement.isEmpty else { continue }
                    if matches(prepared, candidate: typedCandidate) {
                        return .replace(replacement)
                    }
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

    private static func matches(_ prepared: PreparedProfileRule,
                                candidate: NormalizedCandidate) -> Bool {
        let rule = prepared.rule
        switch rule.match {
        case .exact, .unverifiedPunto:
            return candidate.value(caseSensitive: rule.caseSensitive) == prepared.normalizedPattern
        case .prefix:
            return candidate.value(caseSensitive: rule.caseSensitive).hasPrefix(prepared.normalizedPattern)
        case .contains:
            return candidate.value(caseSensitive: rule.caseSensitive).contains(prepared.normalizedPattern)
        case .regularExpression:
            guard let expression = prepared.regularExpression,
                  candidate.original.count <= 1024 else { return false }
            let range = NSRange(candidate.original.startIndex..<candidate.original.endIndex, in: candidate.original)
            return expression.firstMatch(in: candidate.original, range: range) != nil
        }
    }

    /// Accept a small, bounded regular-expression subset in the keyboard event path.
    fileprivate static func isConservativeRegex(_ pattern: String) -> Bool {
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
