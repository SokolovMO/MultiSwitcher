import Foundation

/// In-memory evidence that a completed automatic layout conversion was explicitly
/// undone in the same application and text context. The event itself is never saved.
public struct LearningEvidence: Equatable, Sendable {
    public var operationID: String
    public var word: String
    public var processIdentifier: Int32?
    public var bundleIdentifier: String?
    public var textContextGeneration: UInt64
    public var completedAt: Date

    public init(operationID: String = UUID().uuidString, word: String,
                processIdentifier: Int32?, bundleIdentifier: String?,
                textContextGeneration: UInt64, completedAt: Date = Date()) {
        self.operationID = operationID
        self.word = word
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.textContextGeneration = textContextGeneration
        self.completedAt = completedAt
    }

    public func matchesUndo(operationID undoOperationID: String?,
                            processIdentifier undoPID: Int32?, bundleIdentifier undoBundleID: String?,
                            textContextGeneration undoGeneration: UInt64, at date: Date) -> Bool {
        guard !operationID.isEmpty, operationID == undoOperationID,
              processIdentifier != nil, bundleIdentifier != nil,
              undoPID != nil, undoBundleID != nil,
              date >= completedAt else { return false }
        return processIdentifier == undoPID && bundleIdentifier == undoBundleID
            && textContextGeneration == undoGeneration
    }
}

/// In-memory correlation for a manual Option conversion and its exact return toggle.
/// This never stores the surrounding text or writes keyboard history to disk.
public struct ManualOptionLearningEvidence: Equatable, Sendable {
    public let operationID: String
    public let word: String
    public let processIdentifier: Int32
    public let bundleIdentifier: String
    public let inputGeneration: UInt64
    public private(set) var textContextGeneration: UInt64

    public init(operationID: String, word: String, processIdentifier: Int32,
                bundleIdentifier: String, inputGeneration: UInt64 = 0,
                textContextGeneration: UInt64) {
        self.operationID = operationID
        self.word = word
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.inputGeneration = inputGeneration
        self.textContextGeneration = textContextGeneration
    }

    /// A queued Option press may have captured the context immediately before the
    /// preceding toggle completed. Rebase only when that exact operation advanced
    /// the context and no physical input, process, field owner, or operation changed.
    public func matchesQueuedToggle(snapshotInputGeneration: UInt64,
                                    snapshotTextContextGeneration: UInt64,
                                    currentInputGeneration: UInt64,
                                    currentTextContextGeneration: UInt64,
                                    processIdentifier currentPID: Int32?,
                                    bundleIdentifier currentBundleID: String?,
                                    operationID currentOperationID: String?) -> Bool {
        guard !operationID.isEmpty,
              snapshotInputGeneration == inputGeneration,
              currentInputGeneration == inputGeneration,
              snapshotTextContextGeneration < textContextGeneration,
              currentTextContextGeneration == textContextGeneration,
              currentPID == processIdentifier,
              currentBundleID == bundleIdentifier,
              currentOperationID == operationID else { return false }
        return true
    }

    /// Returns true only for restoring the same operation in the same field/context;
    /// false means a valid toggle back to the converted form; nil invalidates the chain.
    public mutating func completeToggle(operationID currentOperationID: String?,
                                        undoneOperationID: String?,
                                        processIdentifier currentPID: Int32?,
                                        bundleIdentifier currentBundleID: String?,
                                        inputGeneration currentInputGeneration: UInt64 = 0,
                                        textContextGeneration currentGeneration: UInt64,
                                        resultingContextGeneration: UInt64) -> Bool? {
        guard !operationID.isEmpty, operationID == currentOperationID,
              currentPID == processIdentifier, currentBundleID == bundleIdentifier,
              currentInputGeneration == inputGeneration,
              currentGeneration == textContextGeneration,
              undoneOperationID == nil || undoneOperationID == operationID else { return nil }
        textContextGeneration = resultingContextGeneration
        return undoneOperationID == operationID
    }
}

public enum LearningEngine {
    public static let minimumLetters = 3
    public static let requiredCancellations = 2
    public static let requiredManualRoundTrips = 2

    /// Call only when an automatic correction was completed and the user explicitly undid it.
    public static func recordAutomaticCancellation(word: String, in profile: inout MultiSwitcherProfile) -> LearningOutcome {
        recordAutomaticCancellation(word: word, operationID: nil, in: &profile)
    }

    /// The operation id makes an undo idempotent if an adapter reports completion twice.
    public static func recordAutomaticCancellation(evidence: LearningEvidence,
                                                   in profile: inout MultiSwitcherProfile) -> LearningOutcome {
        guard !evidence.operationID.isEmpty else { return .ineligible }
        return recordAutomaticCancellation(word: evidence.word,
                                           operationID: evidence.operationID,
                                           in: &profile)
    }

    /// Manual Option round trips are user intent, not cancellation of automatic
    /// correction. Keep them as a review candidate until the user confirms it.
    public static func recordManualOptionRoundTrip(word: String,
                                                   in profile: inout MultiSwitcherProfile) -> LearningOutcome {
        guard settingBool("com.multiswitcher.learningEnabled", in: profile, default: true) else {
            return .disabled
        }
        guard let clean = eligibleWord(word) else { return .ineligible }
        let key = normalizedKey(clean)
        if hasNeverConvertRule(key: key, in: profile) { return .alreadyExcluded }
        let existingIndex = profile.learning.firstIndex { normalizedKey($0.word) == key }
        let nextCount = min(requiredManualRoundTrips,
                            max(0, existingIndex.flatMap { profile.learning[$0].manualRoundTripCount } ?? 0) + 1)
        if let existingIndex = existingIndex {
            profile.learning[existingIndex].word = clean
            if profile.learning[existingIndex].origin == .punto {
                profile.learning[existingIndex].importedCancellationCount = max(
                    profile.learning[existingIndex].importedCancellationCount ?? 0,
                    profile.learning[existingIndex].cancellationCount
                )
                profile.learning[existingIndex].cancellationCount = 0
            }
            profile.learning[existingIndex].manualRoundTripCount = nextCount
            profile.learning[existingIndex].origin = .local
            profile.learning[existingIndex].updatedAt = Date()
        } else {
            profile.learning.append(LearningEntry(
                word: clean, cancellationCount: 0, isExcluded: false, origin: .local,
                updatedAt: Date(), manualRoundTripCount: nextCount
            ))
        }
        return .manualCandidate(roundTrips: nextCount)
    }

    /// Activates only a candidate the user reviewed in Learning settings.
    @discardableResult
    public static func confirmManualCandidate(word: String,
                                              in profile: inout MultiSwitcherProfile) -> Bool {
        let key = normalizedKey(word)
        guard settingBool("com.multiswitcher.learningEnabled", in: profile, default: true),
              let index = profile.learning.firstIndex(where: { normalizedKey($0.word) == key }),
              !profile.learning[index].isExcluded,
              (profile.learning[index].manualRoundTripCount ?? 0) >= requiredManualRoundTrips,
              !hasNeverConvertRule(key: key, in: profile) else { return false }

        profile.rules.append(ProfileRule(pattern: profile.learning[index].word,
                                         match: .exact, action: .neverConvert,
                                         enabled: true, caseSensitive: false,
                                         origin: .learned, semanticStatus: .verified))
        profile.learning[index].isExcluded = true
        profile.learning[index].updatedAt = Date()
        return true
    }

    private static func recordAutomaticCancellation(word: String, operationID: String?,
                                                    in profile: inout MultiSwitcherProfile) -> LearningOutcome {
        guard settingBool("com.multiswitcher.learningEnabled", in: profile, default: true) else {
            return .disabled
        }
        guard let clean = eligibleWord(word) else { return .ineligible }
        let key = normalizedKey(clean)
        if hasNeverConvertRule(key: key, in: profile) { return .alreadyExcluded }

        let existingIndex = profile.learning.firstIndex { normalizedKey($0.word) == key }
        if let operationID, let existingIndex,
           profile.learning[existingIndex].recentAutomaticOperationIDs?.contains(operationID) == true {
            return .pending(cancellations: max(0, profile.learning[existingIndex].cancellationCount))
        }

        let localCount = existingIndex.map {
            profile.learning[$0].origin == .punto ? 0 : profile.learning[$0].cancellationCount
        } ?? 0
        let nextCount = min(requiredCancellations, max(0, localCount) + 1)
        if let existingIndex {
            var entry = profile.learning[existingIndex]
            if entry.origin == .punto {
                entry.importedCancellationCount = max(entry.importedCancellationCount ?? 0,
                                                       entry.cancellationCount)
                entry.cancellationCount = 0
            }
            entry.word = clean
            entry.cancellationCount = nextCount
            entry.origin = .local
            entry.updatedAt = Date()
            if let operationID {
                var ids = entry.recentAutomaticOperationIDs ?? []
                ids.append(operationID)
                entry.recentAutomaticOperationIDs = Array(ids.suffix(8))
            }
            profile.learning[existingIndex] = entry
        } else {
            profile.learning.append(LearningEntry(
                word: clean, cancellationCount: nextCount, isExcluded: false,
                origin: .local, updatedAt: Date(),
                recentAutomaticOperationIDs: operationID.map { [$0] }
            ))
        }

        guard nextCount >= requiredCancellations else { return .pending(cancellations: nextCount) }
        guard let index = profile.learning.firstIndex(where: { normalizedKey($0.word) == key }) else {
            return .pending(cancellations: nextCount)
        }
        profile.rules.append(ProfileRule(pattern: clean, match: .exact, action: .neverConvert,
                                         enabled: true, caseSensitive: false,
                                         origin: .learned, semanticStatus: .verified))
        profile.learning[index].isExcluded = true
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
            profile.learning[index].cancellationCount = 0
            profile.learning[index].manualRoundTripCount = 0
            profile.learning[index].recentAutomaticOperationIDs = []
            profile.learning[index].origin = .local
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

    /// Keep actionable local learning evidence visible ahead of imported history.
    /// A confirmed candidate is easiest to miss when an imported Punto list is long.
    public static func sortedForReview(_ entries: [LearningEntry]) -> [LearningEntry] {
        func priority(_ entry: LearningEntry) -> Int {
            if entry.origin == .punto { return 3 }
            if !entry.isExcluded,
               (entry.manualRoundTripCount ?? 0) >= requiredManualRoundTrips { return 0 }
            return entry.isExcluded ? 1 : 2
        }

        return entries.sorted { lhs, rhs in
            let leftPriority = priority(lhs)
            let rightPriority = priority(rhs)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            if leftPriority < 3, lhs.updatedAt != rhs.updatedAt {
                return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
            }
            return lhs.word.localizedCaseInsensitiveCompare(rhs.word) == .orderedAscending
        }
    }

    private static func normalizedKey(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func eligibleWord(_ word: String) -> String? {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let letters = clean.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard !clean.isEmpty, letters >= minimumLetters,
              clean.unicodeScalars.allSatisfy({ CharacterSet.letters.union(.decimalDigits).contains($0) }) else {
            return nil
        }
        return clean
    }

    private static func hasNeverConvertRule(key: String, in profile: MultiSwitcherProfile) -> Bool {
        if profile.rules.contains(where: {
            $0.enabled && $0.action == .neverConvert
                && ($0.match == .exact || $0.match == .unverifiedPunto)
                && normalizedKey($0.pattern) == key
                && ($0.origin == .user || $0.origin == .punto || $0.origin == .learned)
        }) { return true }
        if case .strings(let words) = profile.settings["com.multiswitcher.deniedWords"] {
            return words.contains { normalizedKey($0) == key }
        }
        return false
    }

    private static func settingBool(_ key: String, in profile: MultiSwitcherProfile, default fallback: Bool) -> Bool {
        guard case .bool(let value) = profile.settings[key] else { return fallback }
        return value
    }
}
