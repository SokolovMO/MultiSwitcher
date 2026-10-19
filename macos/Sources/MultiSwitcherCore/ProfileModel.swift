import Foundation

public enum ProfileSetting: Codable, Equatable, Sendable {
    case bool(Bool)
    case string(String)
    case strings([String])
    case integer(Int)

    private enum CodingKeys: String, CodingKey { case kind, bool, string, strings, integer }
    private enum Kind: String, Codable { case bool, string, strings, integer }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .bool: self = .bool(try container.decode(Bool.self, forKey: .bool))
        case .string: self = .string(try container.decode(String.self, forKey: .string))
        case .strings: self = .strings(try container.decode([String].self, forKey: .strings))
        case .integer: self = .integer(try container.decode(Int.self, forKey: .integer))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let value):
            try container.encode(Kind.bool, forKey: .kind)
            try container.encode(value, forKey: .bool)
        case .string(let value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .string)
        case .strings(let value):
            try container.encode(Kind.strings, forKey: .kind)
            try container.encode(value, forKey: .strings)
        case .integer(let value):
            try container.encode(Kind.integer, forKey: .kind)
            try container.encode(value, forKey: .integer)
        }
    }
}

public enum ProfileRuleOrigin: String, Codable, Sendable {
    case user
    case punto
    case learned
}

public enum ProfileRuleMatch: String, Codable, Sendable {
    case exact
    case prefix
    case contains
    case regularExpression
    case unverifiedPunto
}

public enum ProfileRuleAction: String, Codable, Sendable {
    case neverConvert
    case alwaysConvert
    case replace
}

public enum RuleSemanticStatus: String, Codable, Sendable {
    case verified
    case unverifiedPuntoType
}

/// Unknown Punto type/flag semantics stay explicit. The provisional runtime fallback
/// for imported types 12/13 is exact, case-insensitive suppression only.
public struct ProfileRule: Codable, Equatable, Sendable {
    public var id: String
    public var pattern: String
    public var replacement: String?
    public var match: ProfileRuleMatch
    public var action: ProfileRuleAction
    public var enabled: Bool
    public var caseSensitive: Bool
    public var origin: ProfileRuleOrigin
    public var semanticStatus: RuleSemanticStatus
    public var sourceIndex: Int?
    public var sourceTypeCode: Int?
    public var sourceFlags: [Bool]?

    public init(
        id: String = UUID().uuidString, pattern: String, replacement: String? = nil,
        match: ProfileRuleMatch = .exact, action: ProfileRuleAction = .neverConvert,
        enabled: Bool = true, caseSensitive: Bool = false, origin: ProfileRuleOrigin = .user,
        semanticStatus: RuleSemanticStatus = .verified, sourceIndex: Int? = nil,
        sourceTypeCode: Int? = nil, sourceFlags: [Bool]? = nil
    ) {
        self.id = id
        self.pattern = pattern
        self.replacement = replacement
        self.match = match
        self.action = action
        self.enabled = enabled
        self.caseSensitive = caseSensitive
        self.origin = origin
        self.semanticStatus = semanticStatus
        self.sourceIndex = sourceIndex
        self.sourceTypeCode = sourceTypeCode
        self.sourceFlags = sourceFlags
    }
}

public enum LearningOrigin: String, Codable, Sendable {
    case punto
    case local
}

/// An imported Punto history count is pending evidence, never an active exclusion.
public struct LearningEntry: Codable, Equatable, Sendable {
    public var word: String
    public var cancellationCount: Int
    public var isExcluded: Bool
    public var origin: LearningOrigin
    public var updatedAt: Date?

    public init(word: String, cancellationCount: Int, isExcluded: Bool = false,
                origin: LearningOrigin, updatedAt: Date? = nil) {
        self.word = word
        self.cancellationCount = cancellationCount
        self.isExcluded = isExcluded
        self.origin = origin
        self.updatedAt = updatedAt
    }
}

public struct PuntoImportMetadata: Codable, Equatable, Sendable {
    public var importedAt: Date
    public var sourceSHA256: String
    public var sourceSnapshotName: String
    public var sourceRuleCount: Int
    public var sourceLearningCount: Int
    public var unverifiedRuleCount: Int

    public init(importedAt: Date, sourceSHA256: String, sourceSnapshotName: String,
                sourceRuleCount: Int, sourceLearningCount: Int, unverifiedRuleCount: Int) {
        self.importedAt = importedAt
        self.sourceSHA256 = sourceSHA256
        self.sourceSnapshotName = sourceSnapshotName
        self.sourceRuleCount = sourceRuleCount
        self.sourceLearningCount = sourceLearningCount
        self.unverifiedRuleCount = unverifiedRuleCount
    }
}

public struct MultiSwitcherProfile: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var legacyDefaultsMigrated: Bool
    public var settings: [String: ProfileSetting]
    public var rules: [ProfileRule]
    public var learning: [LearningEntry]
    /// Original settings excluding rules/history; retained until each key has a verified mapping.
    public var importedPuntoSettings: Data?
    /// Last imported source rows retained separately so locally removed rows can be restored.
    public var importedPuntoRules: [ProfileRule]?
    public var lastPuntoImport: PuntoImportMetadata?

    public init(schemaVersion: Int = currentSchemaVersion, legacyDefaultsMigrated: Bool = false,
                settings: [String: ProfileSetting] = [:],
                rules: [ProfileRule] = [], learning: [LearningEntry] = [],
                importedPuntoSettings: Data? = nil,
                importedPuntoRules: [ProfileRule]? = nil,
                lastPuntoImport: PuntoImportMetadata? = nil) {
        self.schemaVersion = schemaVersion
        self.legacyDefaultsMigrated = legacyDefaultsMigrated
        self.settings = settings
        self.rules = rules
        self.learning = learning
        self.importedPuntoSettings = importedPuntoSettings
        self.importedPuntoRules = importedPuntoRules
        self.lastPuntoImport = lastPuntoImport
    }
}

public enum LearningOutcome: Equatable, Sendable {
    case disabled
    case ineligible
    case pending(cancellations: Int)
    case excluded(word: String)
    case alreadyExcluded
}

public struct PuntoAppliedImportReport: Equatable, Sendable {
    public var rulesImported: Int
    public var unverifiedRules: Int
    public var learningImported: Int
    public var learningDiscardedByReview: Int
    public var snapshotName: String
    public var sourceSHA256: String

    public init(rulesImported: Int, unverifiedRules: Int, learningImported: Int,
                learningDiscardedByReview: Int, snapshotName: String, sourceSHA256: String) {
        self.rulesImported = rulesImported
        self.unverifiedRules = unverifiedRules
        self.learningImported = learningImported
        self.learningDiscardedByReview = learningDiscardedByReview
        self.snapshotName = snapshotName
        self.sourceSHA256 = sourceSHA256
    }
}
