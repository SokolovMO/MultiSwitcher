import XCTest
import MultiSwitcherCore

final class CorrectionReliabilityTests: XCTestCase {
    private let availableLanguages: Set<String> = ["ru", "en"]
    private let confirmedWords: Set<String> = ["hello", "language", "want", "привет"]

    func testRussianLayoutHelloConvertsToEnglish() {
        let decision = LayoutCorrectionEngine.dictionaryDecision(
            typed: "руддщ", converted: "hello", currentLanguage: "ru", targetLanguage: "en",
            isLanguageAvailable: { self.availableLanguages.contains($0) },
            isValidWord: { word, _ in self.confirmedWords.contains(word.lowercased()) }
        )
        XCTAssertEqual(decision, .convert)
    }

    func testRussianLayoutLanguageConvertsToEnglish() {
        let decision = LayoutCorrectionEngine.dictionaryDecision(
            typed: "дфтпгфпу", converted: "language", currentLanguage: "ru", targetLanguage: "en",
            isLanguageAvailable: { self.availableLanguages.contains($0) },
            isValidWord: { word, _ in self.confirmedWords.contains(word.lowercased()) }
        )
        XCTAssertEqual(decision, .convert)
    }

    func testCorrectEnglishWantIsPreserved() {
        let decision = LayoutCorrectionEngine.dictionaryDecision(
            typed: "want", converted: "цфте", currentLanguage: "en", targetLanguage: "ru",
            isLanguageAvailable: { self.availableLanguages.contains($0) },
            isValidWord: { word, _ in self.confirmedWords.contains(word.lowercased()) }
        )
        XCTAssertEqual(decision, .keepBecauseTargetIsNotAWord)
    }

    func testOneForeignWordKeepsRussianInputSource() {
        XCTAssertTrue(LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
            corrected: "hello", prefix: "привет ", currentLanguage: "ru", targetLanguage: "en",
            targetIsConfirmedWord: true,
            isKnownTargetWord: { word, language in language == "en" && self.confirmedWords.contains(word) }
        ))
    }

    func testTwoConsecutiveEnglishWordsAllowInputSourceChange() {
        XCTAssertFalse(LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
            corrected: "language", prefix: "привет want ", currentLanguage: "ru", targetLanguage: "en",
            targetIsConfirmedWord: true,
            isKnownTargetWord: { word, language in language == "en" && self.confirmedWords.contains(word) }
        ))
    }

    func testSingleRussianWordAfterEnglishWantKeepsEnglishInputSource() {
        XCTAssertTrue(LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
            corrected: "вот", prefix: "want ", currentLanguage: "en", targetLanguage: "ru",
            targetIsConfirmedWord: true,
            isKnownTargetWord: { word, language in language == "ru" && word == "вот" }
        ))
    }

    func testTwoConsecutiveRussianWordsAfterEnglishWantAllowInputSourceChange() {
        XCTAssertFalse(LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
            corrected: "сейчас", prefix: "want вот ", currentLanguage: "en", targetLanguage: "ru",
            targetIsConfirmedWord: true,
            isKnownTargetWord: { word, language in language == "ru" && ["вот", "сейчас"].contains(word) }
        ))
    }

    func testSafeTypedSuffixCanBePreservedAfterBoundary() {
        XCTAssertEqual(
            AppendedInputPolicy.decide(generationDelta: 2, trackedKeyCount: 2, suffix: "hi"),
            .preserve("hi")
        )
    }

    func testSuffixWithUntrackedInputIsRejected() {
        XCTAssertEqual(
            AppendedInputPolicy.decide(generationDelta: 2, trackedKeyCount: 1, suffix: "a"),
            .reject(.generationMismatch)
        )
    }

    func testQueuedReplacementOrderIsStable() {
        var queue = SerialReplacementQueue<String>(capacity: 2)
        XCTAssertTrue(queue.enqueue("first"))
        XCTAssertTrue(queue.enqueue("second"))
        XCTAssertFalse(queue.enqueue("overflow"))

        XCTAssertEqual(queue.beginNext(), "first")
        queue.finishCurrent()
        XCTAssertEqual(queue.beginNext(), "second")
    }

    func testQueueRefusalReportsDepthAndActiveOperationWithoutText() {
        var queue = SerialReplacementQueue<String>(capacity: 1)
        XCTAssertEqual(
            queue.enqueueReportingStatus("first"),
            .accepted(waitingCount: 1, hasActiveOperation: false, capacity: 1)
        )
        XCTAssertEqual(queue.beginNext(), "first")
        XCTAssertEqual(
            queue.enqueueReportingStatus("second"),
            .accepted(waitingCount: 1, hasActiveOperation: true, capacity: 1)
        )
        XCTAssertEqual(
            queue.enqueueReportingStatus("third"),
            .full(waitingCount: 1, hasActiveOperation: true, capacity: 1)
        )
    }

    func testManualLayoutChangeIsNotOverriddenByQueuedCorrection() {
        XCTAssertEqual(
            AutomaticLayoutTransitionPolicy.decide(
                sourceLayoutID: "ru", currentLayoutID: "fr", targetLayoutID: "en"
            ),
            .preserveUserChoice
        )
    }

    func testRuleRevisionChangesOnlyWhenRuleInputsChange() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiSwitcher-Rule-Revision-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ProfileStore(rootURL: root)
        let initial = store.versionedRuleSnapshot()

        try store.update { profile in
            profile.settings["com.multiswitcher.debugLog"] = .bool(true)
        }
        XCTAssertEqual(store.versionedRuleSnapshot().generation, initial.generation,
                       "unrelated preferences must not rebuild compiled automatic rules")

        try store.update { profile in
            profile.settings[ProfileRuleMaintenance.deniedWordsSettingKey] = .strings(["preserve-me"])
        }
        let afterDeniedWords = store.versionedRuleSnapshot()
        XCTAssertEqual(afterDeniedWords.generation, initial.generation + 1,
                       "legacy exclusions affect automatic rule decisions")

        try store.update { profile in
            profile.settings[ProfileRuleMaintenance.alwaysConvertWordsSettingKey] = .strings(["convert-me"])
        }
        let afterAlwaysConvert = store.versionedRuleSnapshot()
        XCTAssertEqual(afterAlwaysConvert.generation, afterDeniedWords.generation + 1,
                       "legacy forced-conversion words affect automatic rule decisions")

        try store.update { profile in
            profile.rules.append(ProfileRule(pattern: "rule-row", origin: .user))
        }
        let afterRuleRow = store.versionedRuleSnapshot()
        XCTAssertEqual(afterRuleRow.generation, afterAlwaysConvert.generation + 1,
                       "adding a visible rule row invalidates the compiled rule snapshot")

        _ = try store.reload()
        XCTAssertEqual(store.versionedRuleSnapshot().generation, afterRuleRow.generation,
                       "reloading unchanged rules does not rebuild the snapshot")
    }
}
