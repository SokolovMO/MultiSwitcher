import Foundation

/// Targeted cleanup for reviewed personal exceptions. Imported Punto rows receive the
/// same stable tombstones as a manual deletion, so a later import cannot revive them.
public enum ProfileRuleMaintenance {
    public static let deniedWordsSettingKey = "com.multiswitcher.deniedWords"

    @discardableResult
    public static func removeExactExclusions(_ words: Set<String>, from profile: inout MultiSwitcherProfile) -> Int {
        let keys = Set(words.map(normalizedKey))
        guard !keys.isEmpty else { return 0 }
        let matching = profile.rules.filter {
            $0.enabled && $0.action == .neverConvert
                && ($0.match == .exact || $0.match == .unverifiedPunto)
                && keys.contains(normalizedKey($0.pattern))
        }
        var removed = 0
        for rule in matching {
            if rule.origin == .punto {
                if PuntoProfileMigration.removeImportedRule(rule.id, from: &profile) { removed += 1 }
            } else {
                profile.rules.removeAll { $0.id == rule.id }
                if rule.origin == .learned { LearningEngine.forget(word: rule.pattern, in: &profile) }
                removed += 1
            }
        }

        if case .strings(let legacy) = profile.settings[deniedWordsSettingKey] {
            let retained = legacy.filter { !keys.contains(normalizedKey($0)) }
            removed += legacy.count - retained.count
            profile.settings[deniedWordsSettingKey] = .strings(retained)
        }
        return removed
    }

    private static func normalizedKey(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
    }
}
