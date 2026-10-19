import CoreFoundation
import Foundation

public struct PuntoUserRule: Equatable {
    public let sourceIndex: Int
    public let term: String
    public let typeCode: Int
    public let flags: [Bool]

    public init(sourceIndex: Int, term: String, typeCode: Int, flags: [Bool]) {
        self.sourceIndex = sourceIndex
        self.term = term
        self.typeCode = typeCode
        self.flags = flags
    }
}

public struct PuntoImportReport: Equatable {
    public let rules: [PuntoUserRule]
    public let learnedEntries: [PuntoLearnedEntry]
    public let undoCollectionEnabled: Bool?
    public let mustShowUndoWindow: Bool?
    public let sourceSettingsData: Data

    public init(rules: [PuntoUserRule], learnedEntries: [PuntoLearnedEntry],
                undoCollectionEnabled: Bool?, mustShowUndoWindow: Bool?,
                sourceSettingsData: Data) {
        self.rules = rules
        self.learnedEntries = learnedEntries
        self.undoCollectionEnabled = undoCollectionEnabled
        self.mustShowUndoWindow = mustShowUndoWindow
        self.sourceSettingsData = sourceSettingsData
    }

    public var learnedEntryCount: Int { learnedEntries.count }

    /// Conservative exact-match projection used only by the legacy fallback list.
    /// The full records below retain the raw code and flags until UI semantics are verified.
    public var neverConvertWords: [String] {
        var seen = Set<String>()
        return rules
            .filter { PuntoProfileImporter.retainedRuleTypeCodes.contains($0.typeCode) }
            .compactMap { rule in
                let word = rule.term.precomposedStringWithCanonicalMapping
                let key = word.lowercased()
                guard !key.isEmpty, seen.insert(key).inserted else { return nil }
                return word
            }
    }

    public var profileRules: [ProfileRule] {
        rules.map { rule in
            let retainedType = PuntoProfileImporter.retainedRuleTypeCodes.contains(rule.typeCode)
            return ProfileRule(
                id: "punto-\(rule.sourceIndex)-\(rule.typeCode)",
                pattern: rule.term,
                match: .unverifiedPunto,
                action: .neverConvert,
                enabled: retainedType,
                caseSensitive: false,
                origin: .punto,
                semanticStatus: .unverifiedPuntoType,
                sourceIndex: rule.sourceIndex,
                sourceTypeCode: rule.typeCode,
                sourceFlags: rule.flags
            )
        }
    }

    public var unsupportedRules: [PuntoUserRule] {
        rules.filter { !PuntoProfileImporter.retainedRuleTypeCodes.contains($0.typeCode) }
    }
}

public struct PuntoLearnedEntry: Equatable {
    public let word: String
    public let cancellationCount: Int

    public init(word: String, cancellationCount: Int) {
        self.word = word
        self.cancellationCount = cancellationCount
    }
}

public enum PuntoProfileImportError: LocalizedError, Equatable {
    case fileTooLarge
    case invalidPropertyList
    case missingRules
    case invalidRule(index: Int)
    case invalidLearning

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "The selected Punto profile is too large to import."
        case .invalidPropertyList:
            return "The selected file is not a valid Punto preferences property list."
        case .missingRules:
            return "The selected preferences file does not contain Punto user rules."
        case .invalidRule(let index):
            return "Punto user rule at row \(index + 1) has an unsupported structure. No rules were imported."
        case .invalidLearning:
            return "Punto learning history has an unsupported structure. No data was imported."
        }
    }
}

public enum PuntoProfileImporter {
    /// Codes observed in the current profile and carried into the conservative exact-word fallback.
    /// Their full matching semantics remain explicitly unverified.
    public static let retainedRuleTypeCodes: Set<Int> = [12, 13]
    public static let neverConvertTypeCodes: Set<Int> = retainedRuleTypeCodes
    public static let reviewedHistoryDeletions: Set<String> = ["сделатй", "нужн", "шбор", "ытой", ";nj", "shla"]
    public static let reviewedHistoryRenames: [String: String] = ["еюьу": "t.me"]
    public static let maximumProfileSize = 10 * 1024 * 1024

    public static func read(from url: URL) throws -> PuntoImportReport {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize, fileSize > maximumProfileSize {
            throw PuntoProfileImportError.fileTooLarge
        }
        return try parse(data: Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    public static func parse(data: Data) throws -> PuntoImportReport {
        guard data.count <= maximumProfileSize else {
            throw PuntoProfileImportError.fileTooLarge
        }

        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw PuntoProfileImportError.invalidPropertyList
        }

        guard let profile = propertyList as? [String: Any],
              let rawRules = profile["userRulesDictionary"] as? [Any] else {
            throw PuntoProfileImportError.missingRules
        }

        let rules = try rawRules.enumerated().map { index, rawRule -> PuntoUserRule in
            guard let fields = rawRule as? [Any], fields.count >= 2,
                  let term = fields[0] as? String,
                  !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let typeNumber = fields[1] as? NSNumber,
                  CFGetTypeID(typeNumber) != CFBooleanGetTypeID(),
                  typeNumber.doubleValue.rounded(.towardZero) == typeNumber.doubleValue else {
                throw PuntoProfileImportError.invalidRule(index: index)
            }

            var flags: [Bool] = []
            for field in fields.dropFirst(2) {
                guard let number = field as? NSNumber,
                      CFGetTypeID(number) == CFBooleanGetTypeID() else {
                    throw PuntoProfileImportError.invalidRule(index: index)
                }
                flags.append(number.boolValue)
            }

            return PuntoUserRule(
                sourceIndex: index,
                term: term,
                typeCode: typeNumber.intValue,
                flags: flags
            )
        }

        let undoLearning: [String: Any]
        if let rawLearning = profile["undoLearning"] {
            guard let parsed = rawLearning as? [String: Any] else {
                throw PuntoProfileImportError.invalidLearning
            }
            undoLearning = parsed
        } else {
            undoLearning = [:]
        }

        let rawEntries: [String: Any]
        if let value = undoLearning["undoDictionary"] {
            guard let parsed = value as? [String: Any] else {
                throw PuntoProfileImportError.invalidLearning
            }
            rawEntries = parsed
        } else {
            rawEntries = [:]
        }

        let learnedEntries = try rawEntries.map { word, rawCount -> PuntoLearnedEntry in
            guard !word.isEmpty,
                  let count = rawCount as? NSNumber,
                  CFGetTypeID(count) != CFBooleanGetTypeID(),
                  count.doubleValue.isFinite,
                  count.doubleValue.rounded(.towardZero) == count.doubleValue,
                  count.intValue >= 0 else {
                throw PuntoProfileImportError.invalidLearning
            }
            return PuntoLearnedEntry(word: word, cancellationCount: count.intValue)
        }.sorted { $0.word < $1.word }

        func optionalBoolean(_ key: String) throws -> Bool? {
            guard let value = undoLearning[key] else { return nil }
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw PuntoProfileImportError.invalidLearning
            }
            return number.boolValue
        }

        var settings = profile
        settings.removeValue(forKey: "userRulesDictionary")
        settings.removeValue(forKey: "undoLearning")
        let settingsData = try PropertyListSerialization.data(
            fromPropertyList: settings, format: .binary, options: 0)

        return PuntoImportReport(
            rules: rules,
            learnedEntries: learnedEntries,
            undoCollectionEnabled: try optionalBoolean("undoCollectionEnabled"),
            mustShowUndoWindow: try optionalBoolean("mustShowUndoWindow"),
            sourceSettingsData: settingsData
        )
    }
}
