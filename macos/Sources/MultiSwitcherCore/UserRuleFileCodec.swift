import Foundation

public struct UserRuleDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var rules: [ProfileRule]

    public init(schemaVersion: Int = 1, rules: [ProfileRule]) {
        self.schemaVersion = schemaVersion
        self.rules = rules
    }
}

public enum UserRuleFileError: Error, Equatable {
    case invalidDocument
    case unsupportedVersion(Int)
    case tooManyRules
    case invalidRule(index: Int)
}

public enum UserRuleFileCodec {
    public static let maximumRuleCount = 10_000

    public static func encode(_ rules: [ProfileRule]) throws -> Data {
        guard rules.count <= maximumRuleCount else { throw UserRuleFileError.tooManyRules }
        let exported = try rules.enumerated().map { index, rule -> ProfileRule in
            guard rule.origin == .user, valid(rule) else { throw UserRuleFileError.invalidRule(index: index) }
            return ProfileRule(
                id: rule.id,
                pattern: rule.pattern,
                replacement: rule.replacement,
                match: rule.match,
                action: rule.action,
                enabled: rule.enabled,
                caseSensitive: rule.caseSensitive,
                origin: .user,
                semanticStatus: .verified
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(UserRuleDocument(rules: exported))
    }

    public static func decode(_ data: Data) throws -> [ProfileRule] {
        guard data.count <= 5_000_000 else { throw UserRuleFileError.invalidDocument }
        let document: UserRuleDocument
        do { document = try JSONDecoder().decode(UserRuleDocument.self, from: data) }
        catch { throw UserRuleFileError.invalidDocument }
        guard document.schemaVersion == 1 else {
            throw UserRuleFileError.unsupportedVersion(document.schemaVersion)
        }
        guard document.rules.count <= maximumRuleCount else { throw UserRuleFileError.tooManyRules }
        return try document.rules.enumerated().map { index, rule -> ProfileRule in
            guard valid(rule) else { throw UserRuleFileError.invalidRule(index: index) }
            return ProfileRule(
                id: rule.id,
                pattern: rule.pattern,
                replacement: rule.replacement,
                match: rule.match,
                action: rule.action,
                enabled: rule.enabled,
                caseSensitive: rule.caseSensitive,
                origin: .user,
                semanticStatus: .verified
            )
        }
    }

    private static func valid(_ rule: ProfileRule) -> Bool {
        guard ProfileRuleEngine.isValidPattern(rule.pattern, mode: rule.match) else { return false }
        if rule.action == .replace {
            guard let replacement = rule.replacement, !replacement.isEmpty, replacement.count <= 4096 else {
                return false
            }
        }
        return true
    }
}
