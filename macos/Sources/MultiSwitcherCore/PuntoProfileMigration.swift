import CoreFoundation
import CryptoKit
import Foundation

public enum PuntoProfileMigration {
    /// Local removals are stored as tombstones so a later Punto import does not resurrect them.
    public static let removedRuleIDsSettingKey = "com.multiswitcher.removedPuntoRuleIDs"

    private static let deletedHistoryKeys = Set(
        PuntoProfileImporter.reviewedHistoryDeletions.map(normalizedKey)
    )
    private static let renames = Dictionary(
        uniqueKeysWithValues: PuntoProfileImporter.reviewedHistoryRenames.map {
            (normalizedKey($0.key), $0.value)
        }
    )

    @discardableResult
    public static func apply(
        _ report: PuntoImportReport,
        sourceSnapshotName: String,
        sourceSHA256: String,
        importedAt: Date = Date(),
        to profile: inout MultiSwitcherProfile
    ) -> PuntoAppliedImportReport {
        let sourceRules = report.profileRules
        let removedIDs: Set<String>
        if case .strings(let ids) = profile.settings[removedRuleIDsSettingKey] {
            removedIDs = Set(ids)
        } else {
            removedIDs = []
        }
        let sourceKeys = stableRuleKeys(sourceRules)
        let importedRules = zip(sourceRules, sourceKeys)
            .filter { !removedIDs.contains($0.1) }
            .map(\.0)
        profile.rules.removeAll { $0.origin == .punto }
        profile.rules.append(contentsOf: importedRules)

        let reviewedHistory = cleanedHistory(report.learnedEntries)
        profile.learning.removeAll { $0.origin == .punto }
        profile.learning.append(contentsOf: reviewedHistory.entries)
        profile.importedPuntoSettings = report.sourceSettingsData
        profile.importedPuntoRules = sourceRules

        if let enabled = report.undoCollectionEnabled {
            profile.settings["com.multiswitcher.learningEnabled"] = .bool(enabled)
        }
        applyKnownSettings(from: report.sourceSettingsData, to: &profile)

        profile.lastPuntoImport = PuntoImportMetadata(
            importedAt: importedAt,
            sourceSHA256: sourceSHA256,
            sourceSnapshotName: sourceSnapshotName,
            sourceRuleCount: sourceRules.count,
            sourceLearningCount: report.learnedEntries.count,
            unverifiedRuleCount: importedRules.count
        )

        return PuntoAppliedImportReport(
            rulesImported: importedRules.count,
            unverifiedRules: importedRules.count,
            learningImported: reviewedHistory.entries.count,
            learningDiscardedByReview: reviewedHistory.discarded,
            snapshotName: sourceSnapshotName,
            sourceSHA256: sourceSHA256
        )
    }

    /// Removes one imported row from the local profile while retaining a stable tombstone.
    @discardableResult
    public static func removeImportedRule(_ id: String, from profile: inout MultiSwitcherProfile) -> Bool {
        guard let index = profile.rules.firstIndex(where: { $0.id == id && $0.origin == .punto }) else {
            return false
        }
        let rule = profile.rules[index]
        let sourceRules = (profile.importedPuntoRules ?? profile.rules.filter { $0.origin == .punto })
            .sorted { ($0.sourceIndex ?? .max) < ($1.sourceIndex ?? .max) }
        let sourceIndex = sourceRules.firstIndex(where: { $0.id == rule.id })
        let key = sourceIndex.map { stableRuleKeys(sourceRules)[$0] } ?? stableRuleKey(rule)
        var removedIDs: Set<String>
        if case .strings(let ids) = profile.settings[removedRuleIDsSettingKey] {
            removedIDs = Set(ids)
        } else {
            removedIDs = []
        }
        removedIDs.insert(key)
        profile.settings[removedRuleIDsSettingKey] = .strings(removedIDs.sorted())
        profile.rules.remove(at: index)
        return true
    }

    /// Restores locally removed Punto rows from the last immutable imported profile snapshot.
    @discardableResult
    public static func restoreRemovedRules(in profile: inout MultiSwitcherProfile) -> Int {
        guard case .strings(let removedIDs) = profile.settings[removedRuleIDsSettingKey],
              !removedIDs.isEmpty,
              let sourceRules = profile.importedPuntoRules else { return 0 }

        let removed = Set(removedIDs)
        let sourceKeys = stableRuleKeys(sourceRules)
        let restored = zip(sourceRules, sourceKeys)
            .filter { removed.contains($0.1) }
            .map(\.0)
        guard !restored.isEmpty else { return 0 }
        let restoredKeys = Set(zip(sourceRules, sourceKeys)
            .filter { removed.contains($0.1) }
            .map(\.1))
        profile.settings[removedRuleIDsSettingKey] = .strings(removed.subtracting(restoredKeys).sorted())
        for rule in restored.sorted(by: { ($0.sourceIndex ?? .max) < ($1.sourceIndex ?? .max) }) {
            guard !profile.rules.contains(where: { $0.id == rule.id }) else { continue }
            let insertion = profile.rules.firstIndex {
                $0.origin == .punto && ($0.sourceIndex ?? .max) > (rule.sourceIndex ?? .max)
            } ?? profile.rules.endIndex
            profile.rules.insert(rule, at: insertion)
        }
        return restored.count
    }

    /// Stable key for a single non-duplicate source row.
    public static func stableRuleKey(_ rule: ProfileRule) -> String {
        stableRuleKey(rule, occurrence: 0)
    }

    private static func stableRuleKeys(_ rules: [ProfileRule]) -> [String] {
        var occurrences: [String: Int] = [:]
        return rules.map { rule in
            let base = ruleIdentity(rule)
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return stableRuleKey(rule, occurrence: occurrence)
        }
    }

    private static func stableRuleKey(_ rule: ProfileRule, occurrence: Int) -> String {
        guard rule.origin == .punto, let typeCode = rule.sourceTypeCode else { return rule.id }
        let flags = (rule.sourceFlags ?? []).map { $0 ? "1" : "0" }.joined()
        let identity = "\(typeCode)|\(flags)|\(rule.pattern.precomposedStringWithCanonicalMapping)|\(occurrence)"
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "punto-key-\(digest)"
    }

    private static func ruleIdentity(_ rule: ProfileRule) -> String {
        "\(rule.sourceTypeCode ?? -1)|\((rule.sourceFlags ?? []).map { $0 ? "1" : "0" }.joined())|\(rule.pattern.precomposedStringWithCanonicalMapping)"
    }

    private static func cleanedHistory(
        _ entries: [PuntoLearnedEntry]
    ) -> (entries: [LearningEntry], discarded: Int) {
        var merged: [String: LearningEntry] = [:]
        var discarded = 0
        for item in entries {
            let sourceKey = normalizedKey(item.word)
            guard !deletedHistoryKeys.contains(sourceKey) else {
                discarded += 1
                continue
            }
            let destination = renames[sourceKey] ?? item.word
            let key = normalizedKey(destination)
            guard !key.isEmpty else {
                discarded += 1
                continue
            }
            if var existing = merged[key] {
                existing.cancellationCount = max(existing.cancellationCount, item.cancellationCount)
                existing.word = destination
                merged[key] = existing
            } else {
                merged[key] = LearningEntry(
                    word: destination,
                    cancellationCount: item.cancellationCount,
                    isExcluded: false,
                    origin: .punto,
                    updatedAt: nil
                )
            }
        }
        return (merged.values.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending },
                discarded)
    }

    /// The raw source plist is always retained. Only mappings confirmed by a stable
    /// app setting are materialized here; unknown shortcut and flag schemas stay raw.
    private static func applyKnownSettings(from data: Data, to profile: inout MultiSwitcherProfile) {
        guard let dictionary = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any] else { return }

        copyBool(dictionary, source: "isAutocorrectionActive",
                 destination: "com.multiswitcher.autoConvert", to: &profile)
        copyBool(dictionary, source: "shouldRememberInputSourceForEachApp",
                 destination: "com.multiswitcher.perAppLayout", to: &profile)
        copyBool(dictionary, source: "launchesOnStartup",
                 destination: "com.multiswitcher.launchAtLogin", to: &profile)
        copyString(dictionary, source: "russianLayoutID",
                   destination: "com.multiswitcher.layout1ID", to: &profile)
        copyString(dictionary, source: "englishLayoutID",
                   destination: "com.multiswitcher.layout2ID", to: &profile)
    }

    private static func copyBool(
        _ dictionary: [String: Any], source: String, destination: String,
        to profile: inout MultiSwitcherProfile
    ) {
        guard let number = dictionary[source] as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return }
        profile.settings[destination] = .bool(number.boolValue)
    }

    private static func copyString(
        _ dictionary: [String: Any], source: String, destination: String,
        to profile: inout MultiSwitcherProfile
    ) {
        guard let value = dictionary[source] as? String, !value.isEmpty else { return }
        profile.settings[destination] = .string(value)
    }

    private static func normalizedKey(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
    }
}
