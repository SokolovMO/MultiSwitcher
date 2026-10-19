import Foundation

public enum LearningEngine {
    public static let minimumLetters = 3
    public static let requiredCancellations = 2

    /// Call only when an automatic correction was completed and the user explicitly undid it.
    public static func recordAutomaticCancellation(word: String, in profile: inout MultiSwitcherProfile) -> LearningOutcome {
        guard settingBool("com.multiswitcher.learningEnabled", in: profile, default: true) else {
            return .disabled
        }
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalizedKey(clean)
        let letterCount = clean.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard !key.isEmpty, letterCount >= minimumLetters else { return .ineligible }

        if profile.rules.contains(where: {
            $0.enabled && $0.action == .neverConvert && normalizedKey($0.pattern) == key
                && ($0.origin == .user || $0.origin == .punto || $0.origin == .learned)
        }) {
            return .alreadyExcluded
        }

        let existingIndex = profile.learning.firstIndex { normalizedKey($0.word) == key }
        let nextCount: Int
        if let existingIndex = existingIndex {
            nextCount = max(0, profile.learning[existingIndex].cancellationCount) + 1
            profile.learning[existingIndex].word = clean
            profile.learning[existingIndex].cancellationCount = nextCount
            profile.learning[existingIndex].origin = .local
            profile.learning[existingIndex].updatedAt = Date()
        } else {
            nextCount = 1
            profile.learning.append(LearningEntry(word: clean, cancellationCount: nextCount,
                                                  isExcluded: false, origin: .local, updatedAt: Date()))
        }

        guard nextCount >= requiredCancellations else {
            return .pending(cancellations: nextCount)
        }

        if profile.rules.contains(where: { $0.origin == .learned && normalizedKey($0.pattern) == key }) {
            return .alreadyExcluded
        }
        profile.rules.append(ProfileRule(pattern: clean, action: .neverConvert,
                                         enabled: true, caseSensitive: false,
                                         origin: .learned, semanticStatus: .verified))
        if let index = profile.learning.firstIndex(where: { normalizedKey($0.word) == key }) {
            profile.learning[index].isExcluded = true
        }
        return .excluded(word: clean)
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool, in store: ProfileStore) throws -> Bool {
        try store.update { profile in
            profile.settings["com.multiswitcher.learningEnabled"] = .bool(enabled)
        }
        return enabled
    }

    public static func isEnabled(in profile: MultiSwitcherProfile) -> Bool {
        settingBool("com.multiswitcher.learningEnabled", in: profile, default: true)
    }

    public static func undoLearnedExclusion(word: String, in profile: inout MultiSwitcherProfile) -> Bool {
        let key = normalizedKey(word)
        let oldCount = profile.rules.count
        profile.rules.removeAll { $0.origin == .learned && normalizedKey($0.pattern) == key }
        if let index = profile.learning.firstIndex(where: { normalizedKey($0.word) == key }) {
            profile.learning[index].isExcluded = false
            profile.learning[index].updatedAt = Date()
        }
        return profile.rules.count != oldCount
    }

    public static func forget(word: String, in profile: inout MultiSwitcherProfile) {
        let key = normalizedKey(word)
        profile.learning.removeAll { normalizedKey($0.word) == key }
        profile.rules.removeAll { $0.origin == .learned && normalizedKey($0.pattern) == key }
    }

    public static func learnedWords(in profile: MultiSwitcherProfile) -> [LearningEntry] {
        profile.learning
            .filter { $0.isExcluded || $0.origin == .local }
            .sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }

    private static func normalizedKey(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func settingBool(_ key: String, in profile: MultiSwitcherProfile, default fallback: Bool) -> Bool {
        guard case .bool(let value) = profile.settings[key] else { return fallback }
        return value
    }
}
