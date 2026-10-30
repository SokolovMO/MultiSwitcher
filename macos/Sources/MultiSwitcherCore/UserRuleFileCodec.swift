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
    case unsupportedFormat
    case textIntentRequired
    case tooManyRules
    case invalidRule(index: Int)
    case invalidTextRow(index: Int)
    case invalidDelimitedRow(index: Int)
}

public enum UserRuleTextIntent: Equatable, Sendable {
    case neverConvert
    case alwaysConvert
}

public struct UserRuleImportPreview: Equatable, Sendable {
    public enum Format: Equatable, Sendable { case json, wordList, pairs }
    public var format: Format
    public var sourceRowCount: Int
    public var duplicateRowCount: Int
    public var rules: [ProfileRule]

    public init(format: Format, sourceRowCount: Int, duplicateRowCount: Int, rules: [ProfileRule]) {
        self.format = format
        self.sourceRowCount = sourceRowCount
        self.duplicateRowCount = duplicateRowCount
        self.rules = rules
    }
}

public enum UserRuleFileCodec {
    public static let maximumRuleCount = 10_000
    public static let maximumFileSize = 5_000_000

    /// Decode the formats the app explicitly supports. A plain word list has no
    /// inherent meaning, so the caller must ask whether its words are exceptions
    /// or explicit conversion targets before importing it.
    public static func previewImport(_ data: Data, fileExtension: String,
                                     textIntent: UserRuleTextIntent? = nil) throws -> UserRuleImportPreview {
        guard data.count <= maximumFileSize else { throw UserRuleFileError.invalidDocument }
        switch fileExtension.lowercased() {
        case "json":
            let decoded = try decode(data)
            return deduplicated(decoded, sourceRowCount: decoded.count, format: .json)
        case "txt":
            guard let textIntent else { throw UserRuleFileError.textIntentRequired }
            guard let text = String(data: data, encoding: .utf8) else { throw UserRuleFileError.invalidDocument }
            let lines = text.components(separatedBy: .newlines).enumerated().compactMap { index, line -> (Int, String)? in
                let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : (index + 1, value)
            }
            guard lines.count <= maximumRuleCount else { throw UserRuleFileError.tooManyRules }
            let action: ProfileRuleAction = textIntent == .neverConvert ? .neverConvert : .alwaysConvert
            var rules: [ProfileRule] = []
            for (lineNumber, pattern) in lines {
                let rule = ProfileRule(pattern: pattern, match: .exact, action: action, origin: .user)
                guard valid(rule) else { throw UserRuleFileError.invalidTextRow(index: lineNumber) }
                rules.append(rule)
            }
            return deduplicated(rules, sourceRowCount: lines.count, format: .wordList)
        case "csv", "tsv":
            guard let text = String(data: data, encoding: .utf8) else { throw UserRuleFileError.invalidDocument }
            let delimiter: Character = fileExtension.lowercased() == "tsv" ? "\t" : ","
            var rows = try parseDelimited(text, delimiter: delimiter)
            if let first = rows.first, isPairHeader(first) { rows.removeFirst() }
            guard rows.count <= maximumRuleCount else { throw UserRuleFileError.tooManyRules }
            var rules: [ProfileRule] = []
            for (offset, row) in rows.enumerated() {
                guard row.count == 2 else { throw UserRuleFileError.invalidDelimitedRow(index: offset + 1) }
                let pattern = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let replacement = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let rule = ProfileRule(pattern: pattern, replacement: replacement, match: .exact,
                                       action: .replace, origin: .user)
                guard valid(rule) else { throw UserRuleFileError.invalidDelimitedRow(index: offset + 1) }
                rules.append(rule)
            }
            return deduplicated(rules, sourceRowCount: rows.count, format: .pairs)
        default:
            throw UserRuleFileError.unsupportedFormat
        }
    }

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
        guard data.count <= maximumFileSize else { throw UserRuleFileError.invalidDocument }
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

    private static func deduplicated(_ rules: [ProfileRule], sourceRowCount: Int,
                                     format: UserRuleImportPreview.Format) -> UserRuleImportPreview {
        var seen = Set<String>()
        var unique: [ProfileRule] = []
        for rule in rules {
            let pattern = rule.caseSensitive ? rule.pattern.precomposedStringWithCanonicalMapping
                : rule.pattern.precomposedStringWithCanonicalMapping.lowercased()
            let replacement = rule.replacement?.precomposedStringWithCanonicalMapping ?? ""
            let key = "\(pattern)\u{0}\(rule.match.rawValue)\u{0}\(rule.action.rawValue)\u{0}\(replacement)\u{0}\(rule.caseSensitive)"
            if seen.insert(key).inserted { unique.append(rule) }
        }
        return UserRuleImportPreview(format: format, sourceRowCount: sourceRowCount,
                                     duplicateRowCount: sourceRowCount - unique.count, rules: unique)
    }

    private static func isPairHeader(_ row: [String]) -> Bool {
        guard row.count == 2 else { return false }
        let first = row[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let second = row[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let patternNames: Set<String> = ["pattern", "word", "source", "input", "исходное слово", "шаблон"]
        let replacementNames: Set<String> = ["replacement", "replace", "target", "output", "замена", "результат"]
        return patternNames.contains(first) && replacementNames.contains(second)
    }

    /// Small CSV/TSV reader with quoted fields and doubled-quote escaping. Malformed
    /// quoting is rejected instead of silently importing shifted columns.
    private static func parseDelimited(_ text: String, delimiter: Character) throws -> [[String]] {
        let characters = Array(text.dropFirst(text.first == "\u{feff}" ? 1 : 0))
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var fieldStarted = false
        var index = 0

        func finishField() { row.append(field); field = ""; fieldStarted = false }
        func finishRow() {
            finishField()
            if row.count > 1 || row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                rows.append(row)
            }
            row = []
        }

        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\""); index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case delimiter:
                    finishField()
                case "\n":
                    finishRow()
                case "\r":
                    finishRow()
                    if index + 1 < characters.count, characters[index + 1] == "\n" { index += 1 }
                case "\"":
                    guard !fieldStarted && field.isEmpty else {
                        throw UserRuleFileError.invalidDelimitedRow(index: rows.count + 1)
                    }
                    quoted = true
                    fieldStarted = true
                default:
                    field.append(character)
                    fieldStarted = true
                }
            }
            index += 1
        }
        guard !quoted else { throw UserRuleFileError.invalidDelimitedRow(index: rows.count + 1) }
        if !row.isEmpty || !field.isEmpty || fieldStarted { finishRow() }
        return rows
    }
}
