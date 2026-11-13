import Foundation
import CryptoKit
import MultiSwitcherCore

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    CheckCounter.total += 1
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

private enum CheckCounter {
    nonisolated(unsafe) static var total = 0
}

private func testInterfaceChromeCasingPreservesDataAndKeys() {
    expect(InterfaceText.chrome("MultiSwitcher НАСТРОЙКИ Option ⌘W iPhone") == "multiswitcher настройки Option ⌘W iPhone",
           "UI chrome is lowercase while keyboard syntax and correction casing survive")
    expect(String(format: InterfaceText.chrome("Результат: %@"), "iPhone СЛОВО") == "результат: iPhone СЛОВО",
           "dynamic user text is interpolated after chrome casing")
    expect(InterfaceText.chrome("Options Commanded") == "options commanded",
           "key-name protection does not affect parts of ordinary UI words")
    expect(InterfaceText.chrome("AZ AЯ ABC") == "AZ AЯ ABC",
           "technical layout identifiers retain their syntax")
}

private func testAutomaticLayoutTransitionPolicy() {
    expect(AutomaticLayoutTransitionPolicy.decide(
        sourceLayoutID: "ru", currentLayoutID: "ru", targetLayoutID: "en"
    ) == .select("en"), "the captured source selects its exact paired target")
    expect(AutomaticLayoutTransitionPolicy.decide(
        sourceLayoutID: "ru", currentLayoutID: "en", targetLayoutID: "en"
    ) == .alreadyAtTarget, "a user-selected target is not toggled again")
    expect(AutomaticLayoutTransitionPolicy.decide(
        sourceLayoutID: "ru", currentLayoutID: "fr", targetLayoutID: "en"
    ) == .preserveUserChoice, "a manual layout change while replacement waits is preserved")
    expect(AutomaticLayoutTransitionPolicy.decide(
        sourceLayoutID: nil, currentLayoutID: "ru", targetLayoutID: "en"
    ) == .sourceUnavailable, "unknown captured layout never triggers a blind switch")
    expect(AutomaticLayoutTransitionPolicy.decide(
        sourceLayoutID: "ru", currentLayoutID: "ru", targetLayoutID: nil
    ) == .keep, "no inferred target leaves the current layout unchanged")
}

private func testTrailingKeyboardPunctuation() {
    let caret = KeyboardPunctuationPolicy.splitTrailing(from: "utybq^")
    expect(caret.coreLength == 5 && caret.suffix == "^",
           "US Shift+6 punctuation is split from a wrong-layout word before dictionary lookup")

    let question = KeyboardPunctuationPolicy.splitTrailing(from: "gthtdtkjcm?")
    expect(question.coreLength == 10 && question.suffix == "?",
           "question punctuation remains outside the candidate word")

    let apostropheWord = KeyboardPunctuationPolicy.splitTrailing(from: "'nj")
    expect(apostropheWord.coreLength == 3 && apostropheWord.suffix.isEmpty,
           "a leading apostrophe key that can represent a Russian letter stays in the token")
}

private func propertyListData(_ value: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
}

private func testSpotlightTargetClassification() {
    expect(SpotlightTargetClassifier.isSpotlight(
        frontmostBundleIdentifier: "com.apple.Spotlight", windowOwnerNames: []
    ), "the Spotlight bundle ID is recognized without an exact window-owner name")
    expect(SpotlightTargetClassifier.isSpotlight(
        frontmostBundleIdentifier: "com.apple.finder", windowOwnerNames: ["spotlight"]
    ), "Spotlight window owner matching is case-insensitive")
    expect(SpotlightTargetClassifier.isSpotlight(
        frontmostBundleIdentifier: "com.google.Chrome", windowOwnerNames: ["Search"],
        windowOwnerBundleIdentifiers: ["com.apple.Spotlight"]
    ), "a Spotlight-owned window is recognized when another app remains frontmost")
    expect(!SpotlightTargetClassifier.isSpotlight(
        frontmostBundleIdentifier: "com.apple.finder", windowOwnerNames: ["Finder"]
    ), "unrelated frontmost app and window remain inactive")
    expect(SpotlightTargetClassifier.isSpotlight(
        frontmostBundleIdentifier: "com.apple.finder", windowOwnerNames: ["SystemUIServer"],
        focusedElementBundleIdentifier: "com.apple.systemuiserver",
        focusedElementRole: "AXSearchField"
    ), "the SystemUIServer-hosted Spotlight search field is recognized")
    expect(SpotlightTargetClassifier.isSpotlight(
        frontmostBundleIdentifier: "com.apple.finder", windowOwnerNames: [],
        focusedElementBundleIdentifier: "com.apple.Spotlight",
        focusedElementRole: "AXTextField"
    ), "a Spotlight-process focused search field is recognized without window metadata")
    expect(SpotlightTargetClassifier.isSpotlight(
        frontmostBundleIdentifier: "com.openai.codex", windowOwnerNames: [],
        focusedElementBundleIdentifier: "com.apple.campo",
        focusedElementRole: "AXTextField"
    ), "a Campo-hosted Spotlight query field is recognized when another app remains frontmost")
    expect(!SpotlightTargetClassifier.isSpotlight(
        frontmostBundleIdentifier: "com.apple.finder", windowOwnerNames: [],
        focusedElementBundleIdentifier: "com.apple.campo",
        focusedElementRole: "AXButton"
    ), "a Campo button is not mistaken for the Spotlight query field")
    expect(!SpotlightTargetClassifier.isSpotlight(
        frontmostBundleIdentifier: "com.apple.finder", windowOwnerNames: [],
        focusedElementBundleIdentifier: "com.apple.systemuiserver",
        focusedElementRole: "AXButton"
    ), "a SystemUIServer menu button is not mistaken for Spotlight search")
    expect(!SpotlightTargetClassifier.isSpotlight(
        frontmostBundleIdentifier: "com.apple.finder", windowOwnerNames: [],
        focusedElementBundleIdentifier: "com.apple.finder",
        focusedElementRole: "AXSearchField"
    ), "Finder search field is not mistaken for Spotlight")
}

private func testGlobalSpaceShortcutsPreserveOnlyLayoutSwitchWords() {
    expect(SpaceShortcutPolicy.disposition(commandDown: true, controlDown: false) == .resetForShortcut,
           "Command-Space must clear the pending word before Spotlight changes focus")
    expect(SpaceShortcutPolicy.disposition(commandDown: false, controlDown: true) == .preserveWordForLayoutSwitch,
           "Control-Space changes the layout without ending the current word")
    expect(SpaceShortcutPolicy.disposition(commandDown: false, controlDown: false) == .wordBoundary,
           "ordinary Space must remain an auto-conversion boundary")
}

private func testPauseStateExpiry() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    expect(PauseStatePolicy.hasExpiredDeadline(now.addingTimeInterval(-1), now: now),
           "an elapsed timed pause must expire")
    expect(!PauseStatePolicy.hasExpiredDeadline(now.addingTimeInterval(60), now: now),
           "a future timed pause remains active")
    expect(!PauseStatePolicy.hasExpiredDeadline(nil, now: now),
           "an indefinite pause has no automatic expiry")
}

private func testUpdateChannelSelection() {
    let releases = [
        PublishedRelease(tag: "v1.0.0-build2", version: "1.0.0", buildNumber: "2",
                         isDraft: false, isPrerelease: false, publishedAt: "2026-10-12T10:00:00Z"),
        PublishedRelease(tag: "beta-v1.1.0-build3", version: "1.1.0", buildNumber: "3",
                         isDraft: false, isPrerelease: true, publishedAt: "2026-10-18T10:00:00Z"),
        PublishedRelease(tag: "beta-v1.2.0-build4", version: "1.2.0", buildNumber: "4",
                         isDraft: true, isPrerelease: true, publishedAt: "2026-10-19T10:00:00Z"),
        PublishedRelease(tag: "v1.0.0-build9", version: "1.0.0", buildNumber: "9",
                         isDraft: false, isPrerelease: false, publishedAt: "2026-10-19T10:00:00Z"),
    ]
    expect(UpdateChannelPolicy.select(releases, channel: .stable)?.tag == "v1.0.0-build9",
           "stable channel selects the newest published stable release and ignores prereleases")
    expect(UpdateChannelPolicy.select(releases, channel: .beta)?.tag == "beta-v1.1.0-build3",
           "beta channel selects a published beta when it is newer than stable")
    expect(UpdateChannelPolicy.isValidTag("beta-v0.3.0-build12", channel: .beta),
           "beta release tags use an explicit beta prefix")
    expect(!UpdateChannelPolicy.isValidTag("v0.3.0-build12", channel: .beta),
           "stable tags cannot be misclassified as beta")
    expect(!UpdateChannelPolicy.isValidTag("v999999999999999999999.0-build1", channel: .stable),
           "oversized release numbers are rejected before comparison")
}

private func testAppendedInputPolicy() {
    expect(AppendedInputPolicy.singleCharacter(in: "x") == "x",
           "a one-grapheme keyboard event is tracked exactly")
    expect(AppendedInputPolicy.singleCharacter(in: "ab") == nil,
           "a multi-character keyboard event cannot be truncated to its first character")
    expect(AppendedInputPolicy.singleCharacter(in: "🙂") == "🙂",
           "a single emoji event is preserved as one grapheme and then rejected safely by policy")
    expect(AppendedInputPolicy.classifyUnicodeEvent(text: nil) == .keyCodeOnly,
           "an event without Unicode text can use the physical key mapping")
    expect(AppendedInputPolicy.classifyUnicodeEvent(text: "") == .keyCodeOnly,
           "an empty Unicode event can use the physical key mapping")
    expect(AppendedInputPolicy.classifyUnicodeEvent(text: "a") == .character("a"),
           "a single safe Unicode scalar is tracked exactly")
    expect(AppendedInputPolicy.classifyUnicodeEvent(text: "ab") == .invalidate,
           "multi-character text invalidates the tracked word")
    expect(AppendedInputPolicy.classifyUnicodeEvent(text: "e\u{301}") == .invalidate,
           "composed text invalidates the tracked word")
    expect(AppendedInputPolicy.classifyUnicodeEvent(text: "🙂") == .invalidate,
           "unsupported multiscalar symbols invalidate the tracked word")
    expect(AppendedInputPolicy.classifyUnicodeEvent(text: "a", wasTruncated: true) == .invalidate,
           "a truncated event is never interpreted from its physical key")
    expect(AppendedInputPolicy.canPreserveTypedSuffix(
        generationDelta: 3, trackedKeyCount: 3, suffix: "abc"
    ), "boundary correction can retain ordinary letters typed after the space")
    expect(AppendedInputPolicy.canPreserveTypedSuffix(
        generationDelta: 0, trackedKeyCount: 0, suffix: ""
    ), "a conversion can commit when no new text was typed after its boundary")
    expect(!AppendedInputPolicy.canPreserveTypedSuffix(
        generationDelta: 4, trackedKeyCount: 3, suffix: "abc"
    ), "an untracked key invalidates the captured replacement")
    expect(AppendedInputPolicy.canPreserveTypedSuffix(
        generationDelta: 2, trackedKeyCount: 2, suffix: "a "
    ), "a later word boundary is preserved as literal text")
    expect(AppendedInputPolicy.canPreserveTypedSuffix(
        generationDelta: 3, trackedKeyCount: 3, suffix: "!? "
    ), "punctuation and spaces are preserved exactly")
    expect(!AppendedInputPolicy.canPreserveTypedSuffix(
        generationDelta: 1, trackedKeyCount: 1, suffix: "🙂"
    ), "emoji suffixes are rejected safely")
    expect(AppendedInputPolicy.canPreserveRecoveredTypedSuffix(
        generationDelta: 3, recoveredKeyCount: 3, suffix: "abc", capturedPrefixMatches: true
    ), "a complete matching key-buffer suffix can recover an incomplete keyboard event")
    expect(!AppendedInputPolicy.canPreserveRecoveredTypedSuffix(
        generationDelta: 3, recoveredKeyCount: 2, suffix: "ab", capturedPrefixMatches: true
    ), "key-buffer recovery rejects an untracked key event")
    expect(!AppendedInputPolicy.canPreserveRecoveredTypedSuffix(
        generationDelta: 2, recoveredKeyCount: 2, suffix: "ab", capturedPrefixMatches: false
    ), "key-buffer recovery rejects a changed captured prefix")
    expect(!AppendedInputPolicy.canPreserveRecoveredTypedSuffix(
        generationDelta: 2, recoveredKeyCount: 2, suffix: "e\u{301}", capturedPrefixMatches: true
    ), "key-buffer recovery rejects composed text that cannot be safely deleted by key count")
    expect(!AppendedInputPolicy.canPreserveRecoveredTypedSuffix(
        generationDelta: 1, recoveredKeyCount: 1, suffix: "a", capturedPrefixMatches: true,
        allKeyEventsAreRecoverable: false
    ), "key-buffer recovery rejects a composed event that cannot be reconstructed from physical keys")
    expect(!AppendedInputPolicy.canPreserveRecoveredTypedSuffix(
        generationDelta: 65, recoveredKeyCount: 65, suffix: String(repeating: "a", count: 65),
        capturedPrefixMatches: true
    ), "key-buffer recovery remains bounded for fast or stale input")
    if case .reject(.historyExpired) = AppendedInputPolicy.decide(
        generationDelta: 1, trackedKeyCount: 1, suffix: "a", historyAvailable: false
    ) {
        expect(true, "an expired suffix history returns a distinct privacy-safe reason")
    } else {
        expect(false, "an expired suffix history returns a distinct privacy-safe reason")
    }
    if case .reject(.unsupportedCharacter) = AppendedInputPolicy.decide(
        generationDelta: 1, trackedKeyCount: 1, suffix: "e\u{301}"
    ) {
        expect(true, "composed multi-scalar suffixes are rejected instead of truncated")
    } else {
        expect(false, "composed multi-scalar suffixes are rejected instead of truncated")
    }
}

private func testSettingsCardLayoutPolicy() {
    expect(SettingsCardLayoutPolicy.topAlignedOriginY(containerHeight: 760, contentHeight: 520) == 240,
           "a settings page stays attached to the same top edge when its container grows")
    expect(SettingsCardLayoutPolicy.topAlignedOriginY(containerHeight: 520, contentHeight: 760) == 0,
           "a taller settings page starts at the container's top without a negative offset")
    let insetFill = SettingsCardLayoutPolicy.insetFillFrame(containerHeight: 700, inset: 12)
    expect(insetFill.originY == 12 && insetFill.height == 676,
           "full-height settings pages keep an equal 12-point top and bottom inset")
    let compactInsetFill = SettingsCardLayoutPolicy.insetFillFrame(containerHeight: 18, inset: 12)
    expect(compactInsetFill.originY == 9 && compactInsetFill.height == 0,
           "inset settings pages clamp their margins when the available area is short")
    expect(SettingsCardLayoutPolicy.downwardShiftToFitTop(containerHeight: 520, contentMaxY: 526) == 6,
           "a card whose controls overflow the top edge is moved back inside its page")
    expect(SettingsCardLayoutPolicy.downwardShiftToFitTop(containerHeight: 520, contentMaxY: 514) == 0,
           "a card that fits the page keeps its current position")
    expect(SettingsCardLayoutPolicy.documentHeight(
        viewportHeight: 700, baselineHeight: 620, pageHeights: [560, 680]
    ) == 700, "the settings document always covers its visible viewport")
    expect(SettingsCardLayoutPolicy.documentHeight(
        viewportHeight: 700, baselineHeight: 620, pageHeights: [760, 680]
    ) == 760, "a dynamically expanded localized page grows the scroll document")

    let newCard = SettingsCardFrame(x: 6, y: 197, width: 448, height: 82)
    let previousCard = SettingsCardFrame(x: 6, y: 271, width: 448, height: 215)
    let shift = SettingsCardLayoutPolicy.downwardShift(
        for: newCard, existingFrames: [previousCard], gutter: 10
    )
    expect(shift == 18, "an 8 pt overlap is moved down to leave the shared 10 pt gutter")
    let correctedMaxY = newCard.maxY - shift
    expect(previousCard.y - correctedMaxY == 10,
           "the corrected cards do not overlap and have the exact shared gutter")
    expect(SettingsCardLayoutPolicy.downwardShift(
        for: SettingsCardFrame(x: 500, y: 197, width: 100, height: 82),
        existingFrames: [previousCard], gutter: 10
    ) == 0, "cards in separate columns do not move each other")

    let lowerNeighbor = SettingsCardFrame(x: 10, y: 150, width: 220, height: 80)
    let upperNeighbor = SettingsCardFrame(x: 10, y: 320, width: 220, height: 80)
    let tallCard = SettingsCardFrame(x: 10, y: 100, width: 220, height: 100)
    let multiCardShift = SettingsCardLayoutPolicy.downwardShift(
        for: tallCard, existingFrames: [upperNeighbor, lowerNeighbor], gutter: 12
    )
    expect(tallCard.maxY - multiCardShift == lowerNeighbor.y - 12,
           "a resized settings card clears the lowest overlapping card and keeps the shared gutter")
}

private func testAutomaticShortWordPolicy() {
    expect(ShortWordPolicy.decide(
        typed: "lf", converted: "да", currentLanguage: "en", otherLanguage: "ru"
    ) == .convert, "the first token in the reported phrase is a confirmed Russian short word")
    expect(ShortWordPolicy.decide(
        typed: "to", converted: "ещ", currentLanguage: "en", otherLanguage: "ru"
    ) == .keep, "a common English short word is preserved")
    expect(ShortWordPolicy.decide(
        typed: "yt", converted: "не", currentLanguage: "en", otherLanguage: "ru"
    ) == .convert, "the reported two-letter word maps to a curated common Russian word")
    expect(ShortWordPolicy.decide(
        typed: "xx", converted: "чч", currentLanguage: "en", otherLanguage: "ru"
    ) == .undecided, "unknown short combinations remain unchanged")
    expect(ShortWordPolicy.decide(
        typed: "lf", converted: "да", currentLanguage: "fr", otherLanguage: "ru"
    ) == .undecided, "unsupported language pairs do not guess")
}

private func testAutomaticDictionaryDecision() {
    let available: Set<String> = ["ru", "en"]
    let valid: Set<String> = ["hello", "want", "привет", "вот"]
    let decision = LayoutCorrectionEngine.dictionaryDecision(
        typed: "руддщ", converted: "hello", currentLanguage: "ru", targetLanguage: "en",
        isLanguageAvailable: { available.contains($0) },
        isValidWord: { word, _ in valid.contains(word.lowercased()) }
    )
    expect(decision == .convert,
           "a target-dictionary-confirmed `hello` corrects the wrong-layout token `руддщ`")

    let languageDecision = LayoutCorrectionEngine.dictionaryDecision(
        typed: "дфтпгфпу", converted: "language", currentLanguage: "ru", targetLanguage: "en",
        isLanguageAvailable: { available.contains($0) },
        isValidWord: { word, _ in valid.contains(word.lowercased()) || word.lowercased() == "language" }
    )
    expect(languageDecision == .convert,
           "the target-dictionary-confirmed `language` corrects `дфтпгфпу` inside a Russian sentence")

    let keepValidEnglish = LayoutCorrectionEngine.dictionaryDecision(
        typed: "want", converted: "цфте", currentLanguage: "en", targetLanguage: "ru",
        isLanguageAvailable: { available.contains($0) },
        isValidWord: { word, _ in valid.contains(word.lowercased()) }
    )
    expect(keepValidEnglish == .keepBecauseTargetIsNotAWord,
           "a correct English token such as `want` is not flipped into a nonword")

    let bothValid = LayoutCorrectionEngine.dictionaryDecision(
        typed: "gift", converted: "gift", currentLanguage: "en", targetLanguage: "ru",
        isLanguageAvailable: { available.contains($0) },
        isValidWord: { _ , _ in true }
    )
    expect(bothValid == .keepBecauseSourceIsAWord,
           "a valid source-language word remains unchanged when both sides are valid")

    let missingTargetDictionary = LayoutCorrectionEngine.dictionaryDecision(
        typed: "руддщ", converted: "hello", currentLanguage: "ru", targetLanguage: "en",
        isLanguageAvailable: { $0 == "ru" },
        isValidWord: { _, _ in true }
    )
    expect(missingTargetDictionary == .undecidedBecauseTargetDictionaryIsUnavailable,
           "an unavailable target dictionary is reported as undecided, not as an invalid word")
}

private func testModifiedBackspaceInvalidatesTrackedText() {
    expect(KeyboardBufferEditPolicy.backspaceDisposition(command: false, option: false, control: false)
           == .removePreviousCharacter, "plain Backspace removes one tracked character")
    expect(KeyboardBufferEditPolicy.backspaceDisposition(command: true, option: false, control: false)
           == .invalidateTrackedText, "Command-Backspace invalidates the buffer after deleting a line prefix")
    expect(KeyboardBufferEditPolicy.backspaceDisposition(command: false, option: true, control: false)
           == .invalidateTrackedText, "Option-Backspace invalidates the buffer after deleting a word")
    expect(KeyboardBufferEditPolicy.backspaceDisposition(command: false, option: false, control: true)
           == .invalidateTrackedText, "Control-Backspace invalidates the buffer after a modified delete")
}

private func testSerialReplacementQueueIsBoundedAndFIFO() {
    var queue = SerialReplacementQueue<String>(capacity: 2)
    let acceptedFirst = queue.enqueue("first")
    let acceptedSecond = queue.enqueue("second")
    let rejectedOverflow = queue.enqueue("overflow")
    expect(acceptedFirst && acceptedSecond && !rejectedOverflow,
           "replacement queue accepts up to its configured waiting capacity")

    let first = queue.beginNext()
    expect(first == "first" && queue.isActive && queue.pendingCount == 1,
           "starting a replacement removes the FIFO head and marks one operation active")
    let concurrentStart = queue.beginNext()
    expect(concurrentStart == nil,
           "a second replacement cannot start before the active one finishes")

    let acceptedWhileActive = queue.enqueue("third")
    let rejectedWhileFull = queue.enqueue("fourth")
    expect(acceptedWhileActive && !rejectedWhileFull,
           "queue capacity bounds waiting work while allowing one active operation")

    queue.finishCurrent()
    let second = queue.beginNext()
    expect(second == "second", "the second replacement starts after the first completes")
    queue.finishCurrent()
    let third = queue.beginNext()
    expect(third == "third", "newer replacement remains ordered behind earlier work")
    queue.finishCurrent()
    let empty = queue.beginNext()
    expect(empty == nil && !queue.isActive,
           "an empty queue has no active operation")
}

private func testDefaultReplacementQueueHandlesRapidToggleBursts() {
    var queue = SerialReplacementQueue<Int>()
    let accepted = (0..<32).allSatisfy { queue.enqueue($0) }
    expect(accepted && queue.pendingCount == 32,
           "the default replacement queue retains a rapid ten-toggle burst with room to spare")
    expect(!queue.enqueue(32) && queue.pendingCount == 32,
           "the default replacement queue remains strictly bounded at 32 waiting operations")
}

private func testReplacementQueueReportsSafeDiagnosticState() {
    var queue = SerialReplacementQueue<String>(capacity: 1)
    expect(queue.enqueueReportingStatus("active") == .accepted(
        waitingCount: 1, hasActiveOperation: false, capacity: 1
    ), "queue diagnostics report an accepted request and its bounded depth")
    expect(queue.beginNext() == "active", "the diagnostic test starts the accepted request")
    expect(queue.enqueueReportingStatus("waiting") == .accepted(
        waitingCount: 1, hasActiveOperation: true, capacity: 1
    ), "queue diagnostics distinguish pending work from the active request")
    expect(queue.enqueueReportingStatus("overflow") == .full(
        waitingCount: 1, hasActiveOperation: true, capacity: 1
    ), "queue saturation reports a precise, text-free refusal state")
}

private func testBufferReplacementLifecycleTracksExactUndoDirection() {
    var lifecycle = BufferReplacementLifecycle()
    expect(lifecycle.toggle() == nil,
           "an uncommitted buffer replacement cannot produce undo evidence")
    lifecycle.commit(operationID: "buffer-op-1")
    expect(lifecycle.isConverted && lifecycle.operationID == "buffer-op-1",
           "a confirmed replacement starts in converted state with its operation ID")
    expect(lifecycle.toggle() == "buffer-op-1" && !lifecycle.isConverted,
           "the reverse toggle restores source text and identifies the undone operation")
    expect(lifecycle.toggle() == nil && lifecycle.isConverted,
           "toggling forward cannot be mistaken for another undo")
    expect(lifecycle.toggle() == "buffer-op-1" && !lifecycle.isConverted,
           "a later exact return to source keeps the same operation identity")
    lifecycle.clear()
    expect(lifecycle.operationID == nil && !lifecycle.isConverted,
           "clearing replacement state removes stale undo evidence")
}

private func testBundledWordLexicon() {
    let lexicon = WordLexicon(wordList: "# sample\nПривет\nпривет\nAPP\n\nслово\nnot a token\n")
    expect(lexicon.count == 3, "word lists ignore comments, blanks, and non-token lines")
    expect(lexicon.contains("привет") && lexicon.contains("APP"),
           "word-list lookup is case-insensitive and keeps Unicode words")
    expect(lexicon.contains("слово") && !lexicon.contains("zzzz"),
           "sorted word-list lookup finds entries across the array and rejects missing words")
    expect(!lexicon.contains("приве"), "word-list lookup does not invent a near match")
}

private func testImportsRulesAndSeparatesLearnedHistory() throws {
    let profile: [String: Any] = [
        "userRulesDictionary": [
            ["Brand", 12, false, true, false],
            ["brand", 13, false, true, false],
            ["future-rule", 99, false, true, false],
        ],
        "undoLearning": [
            "undoDictionary": ["learned-one": 1, "learned-two": 1],
        ],
    ]

    let report = try PuntoProfileImporter.parse(data: propertyListData(profile))
    expect(report.rules.count == 3, "all source records remain represented")
    expect(report.neverConvertWords == ["Brand"], "supported rules are deduplicated case-insensitively")
    expect(report.unsupportedRules.map(\.typeCode) == [99], "unknown rule kinds are reported separately")
    expect(report.learnedEntryCount == 2, "learned history is counted but not applied as rules")
    expect(report.rules[0].flags == [false, true, false], "all source flags are preserved")
    expect(report.rules[0].sourceIndex == 0, "original row position is preserved")
}

private func testUnicodeEquivalentWordsAreDeduplicated() throws {
    let profile: [String: Any] = [
        "userRulesDictionary": [
            ["café", 12, false, true, false],
            ["cafe\u{301}", 12, false, true, false],
            ["Cafe", 13, false, true, false],
        ],
    ]

    let report = try PuntoProfileImporter.parse(data: propertyListData(profile))
    expect(report.neverConvertWords == ["café", "Cafe"], "canonical Unicode and case variants merge without folding accents")
}

private func testMalformedRuleRejectsWholeImport() throws {
    let profile: [String: Any] = [
        "userRulesDictionary": [
            ["valid", 12, false, true, false],
            ["malformed", 13, "not-a-flag"],
        ],
    ]

    do {
        _ = try PuntoProfileImporter.parse(data: propertyListData(profile))
        expect(false, "malformed source row must reject the import")
    } catch let error as PuntoProfileImportError {
        expect(error == .invalidRule(index: 1), "error identifies the row without exposing its contents")
    }
}

private func testMissingRulesAreRejected() throws {
    do {
        _ = try PuntoProfileImporter.parse(data: propertyListData(["configVersion": 8]))
        expect(false, "profile without user rules must reject the import")
    } catch let error as PuntoProfileImportError {
        expect(error == .missingRules, "missing user rules are reported")
    }
}


private func testPuntoHistoryIsPreservedAndRuleProvenance() throws {
    let history: [String: Int] = [
        "custom-history-a": 1, "custom-history-b": 1, "custom-link": 2,
    ]
    let profile: [String: Any] = [
        "userRulesDictionary": [
            ["first", 12, false, true, false],
            ["second", 13, true, false, true],
        ],
        "undoLearning": [
            "undoDictionary": history,
            "undoCollectionEnabled": true,
            "mustShowUndoWindow": false,
        ],
        "isAutocorrectionActive": true,
    ]
    let report = try PuntoProfileImporter.parse(data: propertyListData(profile))
    var destination = MultiSwitcherProfile()
    destination.rules.append(ProfileRule(pattern: "my-own", origin: .user))
    destination.learning.append(LearningEntry(word: "local", cancellationCount: 1, origin: .local))

    let applied = PuntoProfileMigration.apply(
        report,
        sourceSnapshotName: "Punto/profile.plist",
        sourceSHA256: "abc123",
        to: &destination
    )
    expect(applied.rulesImported == 2, "all Punto rows are retained")
    expect(applied.unverifiedRules == 2, "unverified source semantics are explicit")
    expect(applied.learningDiscardedByReview == 0, "a public import never applies another user's cleanup choices")
    expect(destination.rules.filter { $0.origin == .punto }.count == 2, "Punto provenance is assigned")
    expect(destination.rules.first(where: { $0.pattern == "second" })?.sourceFlags == [true, false, true],
           "raw rule flags are preserved")
    expect(destination.rules.contains(where: { $0.pattern == "my-own" && $0.origin == .user }),
           "user rules survive import")
    expect(destination.learning.contains(where: { $0.word == "local" && $0.origin == .local }),
           "local learning survives import")
    expect(destination.learning.first(where: { $0.word == "custom-link" })?.cancellationCount == 0
           && destination.learning.first(where: { $0.word == "custom-link" })?.importedCancellationCount == 2,
           "Punto history stays visible but does not count as fresh local learning evidence")
    expect(destination.learning.count == 4, "all source history and local history remain present")
    let preserved = Set(destination.learning.map(\.word))
    expect(preserved.contains("custom-history-a") && preserved.contains("custom-history-b")
            && preserved.contains("custom-link"),
           "all source history entries are preserved for each importer")
    expect(destination.settings["com.multiswitcher.autoConvert"] == .bool(true),
           "verified automatic-correction setting is mapped")
}

private func testLearningNeedsTwoAutomaticUndos() throws {
    var profile = MultiSwitcherProfile()
    let first = LearningEngine.recordAutomaticCancellation(word: "customword", in: &profile)
    expect(first == .pending(cancellations: 1), "first cancellation remains pending")
    expect(!profile.rules.contains(where: { $0.origin == .learned }), "one undo does not create an exception")
    let second = LearningEngine.recordAutomaticCancellation(word: "customword", in: &profile)
    expect(second == .excluded(word: "customword"), "second cancellation creates the learned exception")
    expect(profile.rules.contains(where: { $0.origin == .learned && $0.pattern == "customword" }),
           "learned rule is stored separately")
    expect(LearningEngine.undoLearnedExclusion(word: "customword", in: &profile),
           "last learned exclusion can be undone")
    expect(!profile.rules.contains(where: { $0.origin == .learned }), "undo removes only learned rule")
    expect(profile.learning.first(where: { $0.word == "customword" })?.cancellationCount == 0,
           "undoing a learned exclusion clears its old evidence")
    expect(LearningEngine.recordAutomaticCancellation(word: "customword", in: &profile)
           == .pending(cancellations: 1), "two fresh cancellations are required to learn the word again")

    profile.settings["com.multiswitcher.learningEnabled"] = .bool(false)
    expect(LearningEngine.recordAutomaticCancellation(word: "another", in: &profile) == .disabled,
           "disabled learning does not record a cancellation")
    profile.settings["com.multiswitcher.learningEnabled"] = .bool(true)
    expect(LearningEngine.recordAutomaticCancellation(word: "no", in: &profile) == .ineligible,
           "short combinations are ignored")
}

private func testManualOptionLearningNeedsReview() {
    var profile = MultiSwitcherProfile()
    let first = LearningEngine.recordManualOptionRoundTrip(word: "cmd", in: &profile)
    expect(first == .manualCandidate(roundTrips: 1), "first manual round trip is recorded as a candidate")
    expect(profile.learning.first?.cancellationCount == 0 && profile.rules.isEmpty,
           "manual Option does not count as an automatic undo or activate an exception")
    let second = LearningEngine.recordManualOptionRoundTrip(word: "cmd", in: &profile)
    expect(second == .manualCandidate(roundTrips: 2), "second complete Option round trip reaches review")
    expect(profile.rules.isEmpty, "manual candidate still needs explicit confirmation")
    expect(LearningEngine.confirmManualCandidate(word: "cmd", in: &profile),
           "review action confirms the manual candidate")
    expect(profile.rules.contains(where: {
        $0.pattern == "cmd" && $0.origin == .learned && $0.action == .neverConvert
    }), "confirmed manual candidate becomes a learned exact exclusion")
    expect(LearningEngine.recordManualOptionRoundTrip(word: "cmd", in: &profile) == .alreadyExcluded,
           "active exclusion cannot accumulate another manual candidate")
    expect(LearningEngine.recordManualOptionRoundTrip(word: "multi word", in: &profile) == .ineligible,
           "multiword selection cannot become a single-word learning candidate")
}

private func testLearningCandidatesAppearBeforeImportedHistory() {
    let entries = [
        LearningEntry(word: "z-punto", cancellationCount: 0, origin: .punto),
        LearningEntry(word: "a-pending", cancellationCount: 1, origin: .local),
        LearningEntry(word: "b-candidate", cancellationCount: 0, origin: .local,
                      manualRoundTripCount: LearningEngine.requiredManualRoundTrips),
        LearningEntry(word: "c-excluded", cancellationCount: 0, isExcluded: true, origin: .local),
    ]

    let ordered = LearningEngine.sortedForReview(entries).map(\.word)
    expect(ordered == ["b-candidate", "c-excluded", "a-pending", "z-punto"],
           "actionable manual candidates appear before local evidence and imported Punto history")
}

private func testManualOptionLearningRequiresExactToggleChain() {
    var evidence = ManualOptionLearningEvidence(
        operationID: "manual-1", word: "cmd", processIdentifier: 42,
        bundleIdentifier: "com.example.Editor", textContextGeneration: 10
    )
    let toggledForward = evidence.completeToggle(
        operationID: "manual-1", undoneOperationID: nil, processIdentifier: 42,
        bundleIdentifier: "com.example.Editor", textContextGeneration: 10,
        resultingContextGeneration: 11
    )
    expect(toggledForward == false, "the conversion toggle advances evidence without learning")
    let restored = evidence.completeToggle(
        operationID: "manual-1", undoneOperationID: "manual-1", processIdentifier: 42,
        bundleIdentifier: "com.example.Editor", textContextGeneration: 11,
        resultingContextGeneration: 12
    )
    expect(restored == true && evidence.textContextGeneration == 12,
           "only the exact return toggle in the same field completes a round trip")
    expect(evidence.completeToggle(
        operationID: "manual-1", undoneOperationID: "manual-1", processIdentifier: 42,
        bundleIdentifier: "com.example.Editor", textContextGeneration: 99,
        resultingContextGeneration: 100
    ) == nil, "moving the text context invalidates manual learning evidence")

    var otherField = ManualOptionLearningEvidence(
        operationID: "manual-2", word: "cmd", processIdentifier: 42,
        bundleIdentifier: "com.example.Editor", textContextGeneration: 20
    )
    expect(otherField.completeToggle(
        operationID: "manual-2", undoneOperationID: "manual-2", processIdentifier: 43,
        bundleIdentifier: "com.example.Editor", textContextGeneration: 20,
        resultingContextGeneration: 21
    ) == nil, "switching applications cannot count toward learning")

    var profile = MultiSwitcherProfile()
    var cycles = ManualOptionLearningEvidence(
        operationID: "cmd-toggle", word: "cmd", processIdentifier: 42,
        bundleIdentifier: "com.example.Editor", textContextGeneration: 30
    )
    for cycle in 0..<2 {
        let generation = UInt64(30 + cycle * 2)
        let forward = cycles.completeToggle(
            operationID: "cmd-toggle", undoneOperationID: nil, processIdentifier: 42,
            bundleIdentifier: "com.example.Editor", textContextGeneration: generation,
            resultingContextGeneration: generation + 1
        )
        if forward == true {
            _ = LearningEngine.recordManualOptionRoundTrip(word: cycles.word, in: &profile)
        }
        let back = cycles.completeToggle(
            operationID: "cmd-toggle", undoneOperationID: "cmd-toggle", processIdentifier: 42,
            bundleIdentifier: "com.example.Editor", textContextGeneration: generation + 1,
            resultingContextGeneration: generation + 2
        )
        if back == true {
            _ = LearningEngine.recordManualOptionRoundTrip(word: cycles.word, in: &profile)
        }
    }
    expect(profile.learning.first(where: { $0.word == "cmd" })?.manualRoundTripCount == 2,
           "two exact manual Option round trips create a visible review candidate")
}

private func testQueuedManualOptionToggleCanFollowItsOwnReplacement() {
    let evidence = ManualOptionLearningEvidence(
        operationID: "manual-queued", word: "cmd", processIdentifier: 42,
        bundleIdentifier: "com.example.Editor", inputGeneration: 20,
        textContextGeneration: 11
    )
    expect(evidence.matchesQueuedToggle(
        snapshotInputGeneration: 20,
        snapshotTextContextGeneration: 10,
        currentInputGeneration: 20,
        currentTextContextGeneration: 11,
        processIdentifier: 42,
        bundleIdentifier: "com.example.Editor",
        operationID: "manual-queued"
    ), "a queued Option toggle may follow the successful replacement that advanced its own context")
    expect(!evidence.matchesQueuedToggle(
        snapshotInputGeneration: 20,
        snapshotTextContextGeneration: 10,
        currentInputGeneration: 21,
        currentTextContextGeneration: 11,
        processIdentifier: 42,
        bundleIdentifier: "com.example.Editor",
        operationID: "manual-queued"
    ), "typing after the captured Option tap invalidates the queued continuation")
    expect(!evidence.matchesQueuedToggle(
        snapshotInputGeneration: 20,
        snapshotTextContextGeneration: 10,
        currentInputGeneration: 20,
        currentTextContextGeneration: 11,
        processIdentifier: 42,
        bundleIdentifier: "com.example.Editor",
        operationID: "different-operation"
    ), "an unrelated replacement cannot rebase a queued Option toggle")

    var continued = evidence
    let restored = continued.completeToggle(
        operationID: "manual-queued",
        undoneOperationID: "manual-queued",
        processIdentifier: 42,
        bundleIdentifier: "com.example.Editor",
        inputGeneration: 20,
        textContextGeneration: 11,
        resultingContextGeneration: 12
    )
    expect(restored == true && continued.textContextGeneration == 12,
           "a rebased queued return toggle can complete the same learning cycle")
}

private func testTenManualOptionTapsCreateVisibleReviewCandidate() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MultiSwitcher-Manual-Learning-\\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProfileStore(rootURL: root)
    var evidence = ManualOptionLearningEvidence(
        operationID: "cmd-ten-taps", word: "cmd", processIdentifier: 42,
        bundleIdentifier: "com.example.Editor", textContextGeneration: 50
    )
    var generation: UInt64 = 50
    var isConverted = true

    for _ in 1...10 {
        isConverted.toggle()
        generation += 1
        let restored = evidence.completeToggle(
            operationID: "cmd-ten-taps",
            undoneOperationID: isConverted ? nil : "cmd-ten-taps",
            processIdentifier: 42,
            bundleIdentifier: "com.example.Editor",
            textContextGeneration: generation - 1,
            resultingContextGeneration: generation
        )
        if restored == true {
            try store.update { profile in
                _ = LearningEngine.recordManualOptionRoundTrip(word: evidence.word, in: &profile)
            }
        }
    }

    let reloadedStore = ProfileStore(rootURL: root)
    let reloaded = reloadedStore.current
    let candidate = LearningEngine.sortedForReview(reloaded.learning).first
    expect(reloaded.learning.first?.manualRoundTripCount == LearningEngine.requiredManualRoundTrips,
           "ten consecutive Option toggles persist the required complete round trips")
    expect(candidate?.word == "cmd", "the completed Option candidate is the first learning row")
    expect(!reloaded.rules.contains(where: { $0.origin == .learned && $0.pattern == "cmd" }),
           "manual Option evidence stays a review candidate until the user confirms it")
}

private func testAutomaticLearningUsesFreshUniqueOperations() {
    var profile = MultiSwitcherProfile(learning: [
        LearningEntry(word: "importedword", cancellationCount: 99, origin: .punto)
    ])
    let first = LearningEvidence(operationID: "auto-1", word: "importedword",
                                 processIdentifier: 42, bundleIdentifier: "com.example.Editor",
                                 textContextGeneration: 7)
    let duplicate = LearningEngine.recordAutomaticCancellation(evidence: first, in: &profile)
    expect(duplicate == .pending(cancellations: 1), "one operation id contributes at most one cancellation")
    expect(profile.learning.first?.importedCancellationCount == 99
           && profile.learning.first?.cancellationCount == 1,
           "imported history remains separate from fresh cancellation evidence")
    _ = LearningEngine.recordAutomaticCancellation(evidence: first, in: &profile)
    expect(profile.learning.first?.cancellationCount == 1,
           "duplicate completion for the same operation is idempotent")
    let second = LearningEvidence(operationID: "auto-2", word: "importedword",
                                  processIdentifier: 42, bundleIdentifier: "com.example.Editor",
                                  textContextGeneration: 8)
    let result = LearningEngine.recordAutomaticCancellation(evidence: second, in: &profile)
    expect(result == .excluded(word: "importedword"),
           "two distinct local undo operations can activate learning despite old imported counts")
}

private func testLearningEvidenceMustMatchSameOperationContext() {
    let completed = Date(timeIntervalSince1970: 100)
    let evidence = LearningEvidence(operationID: "auto-1", word: "ghbdtn",
                                    processIdentifier: 42, bundleIdentifier: "com.example.Editor",
                                    textContextGeneration: 7, completedAt: completed)
    expect(evidence.matchesUndo(operationID: "auto-1", processIdentifier: 42, bundleIdentifier: "com.example.Editor",
                               textContextGeneration: 7,
                               at: completed.addingTimeInterval(2)),
           "a timely undo in the same app process and text field can create learning evidence")
    expect(!evidence.matchesUndo(operationID: "other-operation", processIdentifier: 42, bundleIdentifier: "com.example.Editor",
                                textContextGeneration: 7,
                                at: completed.addingTimeInterval(2)),
           "an undo for a different replacement cannot teach from this correction")
    expect(!evidence.matchesUndo(operationID: "auto-1", processIdentifier: 43, bundleIdentifier: "com.example.Editor",
                                textContextGeneration: 7,
                                at: completed.addingTimeInterval(2)),
           "undo in another app process cannot teach from the conversion")
    expect(!evidence.matchesUndo(operationID: "auto-1", processIdentifier: 42, bundleIdentifier: "com.example.Editor",
                                textContextGeneration: 8,
                                at: completed.addingTimeInterval(2)),
           "undo after the focused text context changed cannot teach from the conversion")
    expect(evidence.matchesUndo(operationID: "auto-1", processIdentifier: 42, bundleIdentifier: "com.example.Editor",
                               textContextGeneration: 7,
                               at: completed.addingTimeInterval(90)),
           "the exact operation remains eligible after a delay while its field context is unchanged")
}

private func testPerAppLayoutMemorySurvivesProfileSerialization() throws {
    var profile = MultiSwitcherProfile()
    PerAppLayoutMemory.remember("com.apple.keylayout.Russian", for: "org.example.Editor", in: &profile)
    PerAppLayoutMemory.remember("com.apple.keylayout.ABC", for: "com.apple.finder", in: &profile)
    PerAppLayoutMemory.remember("", for: "org.example.Empty", in: &profile)

    let encoded = try JSONEncoder().encode(profile)
    let restored = try JSONDecoder().decode(MultiSwitcherProfile.self, from: encoded)
    let layouts = PerAppLayoutMemory.layouts(in: restored)
    expect(layouts["org.example.Editor"] == "com.apple.keylayout.Russian",
           "per-app input source survives profile serialization")
    expect(layouts["com.apple.finder"] == "com.apple.keylayout.ABC",
           "each bundle identifier retains its own input source")
    expect(layouts["org.example.Empty"] == nil, "empty input sources are not stored")
}

private func testUserRuleFileRoundTripSanitizesProvenance() throws {
    let rules = [
        ProfileRule(id: "user-1", pattern: "pre", match: .prefix, action: .neverConvert,
                    caseSensitive: true, origin: .user),
        ProfileRule(id: "user-2", pattern: "teh", replacement: "the", action: .replace, origin: .user),
    ]
    let data = try UserRuleFileCodec.encode(rules)
    let imported = try UserRuleFileCodec.decode(data)
    expect(imported == rules, "user rule export/import preserves editable rule fields")

    let forged = UserRuleDocument(rules: [
        ProfileRule(pattern: "punto-row", action: .neverConvert, origin: .punto,
                    semanticStatus: .unverifiedPuntoType, sourceTypeCode: 12)
    ])
    let forgedData = try JSONEncoder().encode(forged)
    let sanitized = try UserRuleFileCodec.decode(forgedData)
    expect(sanitized.count == 1 && sanitized[0].origin == .user
           && sanitized[0].semanticStatus == .verified && sanitized[0].sourceTypeCode == nil,
           "imported JSON cannot inject Punto provenance or unverified source metadata")
    do {
        _ = try UserRuleFileCodec.decode(Data("{broken".utf8))
        expect(false, "malformed rule document must be rejected")
    } catch let error as UserRuleFileError {
        expect(error == .invalidDocument, "malformed rule document has a typed error")
    }
}

private func testGenericTextRuleImportsAreExplicitAndPreviewable() throws {
    do {
        _ = try UserRuleFileCodec.previewImport(Data("customword\n".utf8), fileExtension: "txt")
        expect(false, "a plain list cannot be assigned a behavior silently")
    } catch let error as UserRuleFileError {
        expect(error == .textIntentRequired, "plain text import requires an explicit rule intent")
    }

    let words = try UserRuleFileCodec.previewImport(
        Data("customword\napp\ncustomword\n\n".utf8), fileExtension: "txt", textIntent: .neverConvert
    )
    expect(words.format == .wordList && words.sourceRowCount == 3 && words.duplicateRowCount == 1,
           "word-list preview reports source rows and duplicates")
    expect(words.rules.count == 2 && words.rules.allSatisfy { $0.action == .neverConvert },
           "selected word-list behavior is applied to every distinct word")

    let pairs = try UserRuleFileCodec.previewImport(
        Data("pattern,replacement\n\"teh, typo\",\"the, correct\"\n".utf8), fileExtension: "csv"
    )
    expect(pairs.format == .pairs && pairs.rules.count == 1,
           "CSV pair import recognizes a supported header")
    expect(pairs.rules[0].pattern == "teh, typo" && pairs.rules[0].replacement == "the, correct"
           && pairs.rules[0].action == .replace,
           "quoted commas remain inside their CSV fields")

    do {
        _ = try UserRuleFileCodec.previewImport(Data("one,two,three\n".utf8), fileExtension: "csv")
        expect(false, "unsupported CSV row shapes must not be imported partially")
    } catch let error as UserRuleFileError {
        expect(error == .invalidDelimitedRow(index: 1), "invalid CSV reports the row number")
    }
}

private func testTypedRuleMatchingAndProvenance() {
    let rules = [
        ProfileRule(pattern: "Brand", match: .exact, action: .neverConvert, origin: .punto,
                    semanticStatus: .unverifiedPuntoType),
        ProfileRule(pattern: "pre", match: .prefix, action: .neverConvert, origin: .user),
        ProfileRule(pattern: "safe", match: .contains, action: .neverConvert, origin: .user),
        ProfileRule(pattern: #"^wr[0-9]+s$"#, match: .regularExpression, action: .neverConvert, origin: .user),
    ]
    expect(ProfileRuleEngine.evaluate(typed: "brand", converted: "brand", rules: rules) == .neverConvert,
           "unverified Punto rules keep the exact case-insensitive fallback")
    expect(ProfileRuleEngine.matches("pre", in: "prefix", mode: .prefix, caseSensitive: false),
           "prefix rules match only at the beginning")
    expect(ProfileRuleEngine.matches("safe", in: "stay-safe", mode: .contains, caseSensitive: false),
           "contains rules find an internal match")
    expect(ProfileRuleEngine.evaluate(typed: "WR300S", converted: "x", rules: rules) == .neverConvert,
           "user regular expressions match case-insensitively by default")
    let compiledRules = ProfileRuleEngine.compile(rules)
    expect(ProfileRuleEngine.evaluate(typed: "WR300S", converted: "x", rules: compiledRules) == .neverConvert,
           "a cached compiled rule snapshot preserves regex behavior")
    expect(ProfileRuleEngine.evaluate(typed: "stay-safe", converted: "x", rules: compiledRules) == .neverConvert,
           "a cached compiled rule snapshot preserves exact rule precedence and contains matching")
    expect(!ProfileRuleEngine.matches(#"(a+)+$"#, in: String(repeating: "a", count: 64) + "!",
                                      mode: .regularExpression, caseSensitive: true),
           "nested quantified regex is refused instead of blocking the keyboard path")

    let actions = [
        ProfileRule(pattern: "forced", action: .alwaysConvert, origin: .user),
        ProfileRule(pattern: "teh", replacement: "the", action: .replace, origin: .user),
    ]
    expect(ProfileRuleEngine.evaluate(typed: "wrong", converted: "forced", rules: actions) == .alwaysConvert,
           "always-convert rules match the target form")
    expect(ProfileRuleEngine.evaluate(typed: "teh", converted: "the", rules: actions) == .replace("the"),
           "replace rules return their configured target")
    expect(ProfileRuleEngine.evaluate(typed: "сркщтщ24", converted: "chrono24", rules: [
        ProfileRule(pattern: "chrono24", action: .neverConvert, origin: .user),
        ProfileRule(pattern: "сркщтщ24", replacement: "chrono24", action: .replace, origin: .user),
    ]) == .replace("chrono24"),
           "a matching replacement overrides a no-convert rule on the replacement target")
    expect(ProfileRuleEngine.evaluate(typed: "сркщтщ24", converted: "chrono24", rules: [
        ProfileRule(pattern: "сркщтщ24", action: .neverConvert, origin: .user),
        ProfileRule(pattern: "сркщтщ24", replacement: "chrono24", action: .replace, origin: .user),
    ]) == .neverConvert,
           "an explicit no-convert rule for the typed source still blocks its replacement")
    expect(ProfileRuleEngine.evaluate(typed: "ordinary", converted: "chrono24", rules: [
        ProfileRule(pattern: "chrono24", action: .neverConvert, origin: .user),
    ]) == .neverConvert,
           "a no-convert rule still protects the converted output without a source replacement")
    expect(ProfileRuleEngine.evaluate(typed: "teh", converted: "the",
                                      rules: [ProfileRule(pattern: "teh", replacement: "the", action: .replace, origin: .punto)]) == .none,
           "unverified imported Punto replacement actions stay inactive")
    expect(ProfileRuleEngine.evaluate(typed: "wrong", converted: "brand", rules: [
        ProfileRule(pattern: "brand", action: .neverConvert, origin: .punto,
                    semanticStatus: .unverifiedPuntoType),
        ProfileRule(pattern: "brand", action: .alwaysConvert, origin: .user),
    ]) == .alwaysConvert, "explicit user rules take precedence over imported Punto rows")
}

private func testProfileStoreGenerationTracksSnapshots() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MultiSwitcher-Generation-Test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ProfileStore(rootURL: root)
    let initial = store.versionedSnapshot()
    try store.update { profile in
        profile.rules.append(ProfileRule(pattern: "fresh", origin: .user))
    }
    let updated = store.versionedSnapshot()
    expect(updated.generation == initial.generation + 1,
           "profile generation increments after an atomic profile update")
    expect(updated.profile.rules.contains(where: { $0.pattern == "fresh" }),
           "a versioned snapshot returns the profile from the same generation")
}

private func testApplicationExclusionPolicy() {
    let entries = ["com.example.Editor", "com.vendor.*"]
    let protected: Set<String> = ["com.password.manager"]
    expect(ApplicationExclusionPolicy.isExcluded(bundleID: "com.example.Editor", entries: entries),
           "exact bundle identifiers are excluded")
    expect(ApplicationExclusionPolicy.isExcluded(bundleID: "com.vendor.IDE", entries: entries),
           "trailing wildcard matches the vendor bundle prefix")
    expect(!ApplicationExclusionPolicy.isExcluded(bundleID: "com.vendorish.IDE", entries: entries),
           "vendor wildcard does not match a neighboring prefix")
    expect(ApplicationExclusionPolicy.isExcluded(bundleID: "com.password.manager", entries: [], protected: protected),
           "protected applications stay excluded even when absent from user settings")
    expect(!ApplicationExclusionPolicy.isExcluded(bundleID: nil, entries: entries),
           "unknown foreground application does not inherit an exclusion")
}

private func testForgettingLearningPreservesImportedAndUserRules() {
    var profile = MultiSwitcherProfile()
    profile.rules = [
        ProfileRule(pattern: "learn-me", action: .neverConvert, origin: .learned),
        ProfileRule(pattern: "punto-word", action: .neverConvert, origin: .punto),
        ProfileRule(pattern: "my-word", action: .neverConvert, origin: .user),
    ]
    profile.learning = [
        LearningEntry(word: "learn-me", cancellationCount: 2, isExcluded: true, origin: .local),
        LearningEntry(word: "pending", cancellationCount: 1, origin: .local),
    ]
    LearningEngine.forget(word: "learn-me", in: &profile)
    expect(!profile.learning.contains { $0.word == "learn-me" }, "forget removes the selected learning record")
    expect(!profile.rules.contains { $0.origin == .learned && $0.pattern == "learn-me" },
           "forget removes the matching learned exclusion")
    expect(profile.rules.contains { $0.origin == .punto && $0.pattern == "punto-word" },
           "forget never changes imported Punto rules")
    expect(profile.rules.contains { $0.origin == .user && $0.pattern == "my-word" },
           "forget never changes user rules")
    expect(profile.learning.contains { $0.word == "pending" },
           "forget leaves unrelated pending history intact")
}

private func testSpotlightRangePlannerPreservesQueryAndCaret() {
    let text = "search привет,   "
    let caret = (text as NSString).length
    guard let plan = TextReplacementPlanner.plan(text: text, selection: NSRange(location: caret, length: 0)) else {
        expect(false, "last word range is found after spaces and punctuation")
        return
    }
    expect((text as NSString).substring(with: plan.range) == "привет", "only the last word is selected")
    let changed = TextReplacementPlanner.replacing(text: text, plan: plan, with: "ghbdtn")
    expect(changed == "search ghbdtn,   ", "prefix, punctuation and all spaces remain unchanged")
    let selection = TextReplacementPlanner.selectionAfterReplacement(plan: plan, replacement: "ghbdtn")
    expect(selection.location == (changed! as NSString).length && selection.length == 0,
           "caret stays after the preserved trailing text")

    let safariText = "ghbdtn "
    let safariPlan = TextReplacementPlanner.plan(
        text: safariText,
        selection: NSRange(location: (safariText as NSString).length, length: 0)
    )
    expect(safariPlan.map { (safariText as NSString).substring(with: $0.range) } == "ghbdtn",
           "an editable browser address field targets the typed word before its space")
    expect(safariPlan.flatMap {
        TextReplacementPlanner.replacing(text: safariText, plan: $0, with: "привет")
    } == "привет ", "browser replacement preserves the submitted trailing space")

    // Reproduce an async word-boundary callback arriving after the next word has
    // already started. Safari must target the captured word, not reject the edit
    // because the caret now points after the newer token.
    let delayedSafariText = "ghbdtn rfr "
    let delayedSafariPlan = TextReplacementPlanner.planCapturedToken(
        text: delayedSafariText,
        selection: NSRange(location: (delayedSafariText as NSString).length, length: 0),
        token: "ghbdtn"
    )
    expect(delayedSafariPlan.map { (delayedSafariText as NSString).substring(with: $0.range) } == "ghbdtn",
           "a delayed Safari correction still targets the word captured at its boundary")
    expect(delayedSafariPlan.flatMap {
        TextReplacementPlanner.replacing(text: delayedSafariText, plan: $0, with: "привет")
    } == "привет rfr ", "a later word remains untouched when the captured word is corrected")
    expect(delayedSafariPlan.map {
        TextReplacementPlanner.selectionAfterReplacement(plan: $0, replacement: "привет").location
    } == ("привет rfr " as NSString).length,
           "the caret remains after newer text when a previous word is replaced")

    // Contextual short-word correction can be delayed until a later confirmed word.
    // The captured line suffix must remain replaceable after the user has continued typing.
    let delayedContextText = "z yt ghbdtn rfr "
    let delayedContextPlan = TextReplacementPlanner.planCapturedSuffix(
        text: delayedContextText,
        selection: NSRange(location: (delayedContextText as NSString).length, length: 0),
        suffix: "z yt ghbdtn "
    )
    expect(delayedContextPlan.map { (delayedContextText as NSString).substring(with: $0.range) } == "z yt ghbdtn ",
           "a delayed contextual correction still targets the captured line suffix")
    expect(delayedContextPlan.flatMap {
        TextReplacementPlanner.replacing(text: delayedContextText, plan: $0, with: "я не могу ")
    } == "я не могу rfr ", "context correction preserves a newer word")
    expect(delayedContextPlan.map {
        TextReplacementPlanner.selectionAfterReplacement(plan: $0, replacement: "я не могу ").location
    } == ("я не могу rfr " as NSString).length,
           "the caret remains after newer text when contextual correction is delayed")
    expect(TextReplacementPlanner.planCapturedSuffix(
        text: "xz yt ghbdtn rfr ",
        selection: NSRange(location: ("xz yt ghbdtn rfr " as NSString).length, length: 0),
        suffix: "z yt ghbdtn "
    ) == nil, "captured context is not matched inside a longer word")
    expect(TextReplacementPlanner.planCapturedSuffix(
        text: "z yt ghbdtn rfr ",
        selection: NSRange(location: 0, length: 2),
        suffix: "z yt ghbdtn "
    ) == nil, "context correction is not applied after the user creates a selection")

    let punctuatedSafariText = "ghbdtn, rfr "
    let punctuatedSafariPlan = TextReplacementPlanner.planCapturedToken(
        text: punctuatedSafariText,
        selection: NSRange(location: (punctuatedSafariText as NSString).length, length: 0),
        token: "ghbdtn"
    )
    expect(punctuatedSafariPlan.map { (punctuatedSafariText as NSString).substring(with: $0.range) } == "ghbdtn",
           "a captured word remains identifiable before punctuation and later input")

    expect(TextReplacementPlanner.planCapturedToken(
        text: "xghbdtn rfr ",
        selection: NSRange(location: ("xghbdtn rfr " as NSString).length, length: 0),
        token: "ghbdtn"
    ) == nil, "a captured token inside another word is not replaced")
    expect(TextReplacementPlanner.planCapturedToken(
        text: "ghbdtnrfr",
        selection: NSRange(location: ("ghbdtnrfr" as NSString).length, length: 0),
        token: "ghbdtn"
    ) == nil, "a captured token without its word boundary is not replaced")

    let selectedText = "🙂 one two"
    let selected = NSRange(location: 3, length: 3)
    let selectedPlan = TextReplacementPlanner.plan(text: selectedText, selection: selected)
    expect(selectedPlan?.range == selected, "a user selection takes precedence over last-word targeting")

    let mixed = "ghbkj;ение,   "
    let mixedPlan = TextReplacementPlanner.plan(
        text: mixed,
        selection: NSRange(location: (mixed as NSString).length, length: 0),
        includeKeyboardPunctuation: true
    )
    expect(mixedPlan.map { (mixed as NSString).substring(with: $0.range) } == "ghbkj;ение",
           "a keyboard punctuation joiner stays inside a mixed-script candidate")
    expect(mixedPlan.map { (mixed as NSString).substring(from: NSMaxRange($0.range)) } == ",   ",
           "trailing punctuation and spaces remain outside the candidate")
    expect(mixedPlan.flatMap {
        TextReplacementPlanner.replacing(text: mixed, plan: $0, with: "приложение")
    } == "приложение,   ", "browser replacement converts the whole mixed token without shifting punctuation")

    let suffixText = "query z yt "
    let suffix = "z yt "
    let suffixPlan = TextReplacementPlanner.planExactSuffix(
        text: suffixText,
        selection: NSRange(location: (suffixText as NSString).length, length: 0),
        suffix: suffix
    )
    expect(suffixPlan.map { (suffixText as NSString).substring(with: $0.range) } == suffix,
           "contextual correction can target the exact typed suffix")
    expect(TextReplacementPlanner.planExactSuffix(
        text: suffixText,
        selection: NSRange(location: (suffixText as NSString).length - 1, length: 0),
        suffix: suffix
    ) == nil, "a moved caret prevents contextual suffix replacement")

    let prefixedContext = "prefix z yt ghbdtn rfr "
    let prefixedSuffix = "z yt ghbdtn "
    let prefixedPlan = TextReplacementPlanner.planCapturedSuffix(
        text: prefixedContext,
        selection: NSRange(location: (prefixedContext as NSString).length, length: 0),
        suffix: prefixedSuffix
    )
    expect(prefixedPlan.map { (prefixedContext as NSString).substring(with: $0.range) } == prefixedSuffix,
           "a captured context suffix is found after an unrelated field prefix")

    let urlQuery = "https://example.com/site/#contacts\n\n"
    expect(TextReplacementPlanner.plan(
        text: urlQuery,
        selection: NSRange(location: (urlQuery as NSString).length, length: 0)
    ) == nil, "a blank line after a URL never targets the URL's last path fragment")

    let urlCaret = "https://example.com/site/#contacts"
    expect(TextReplacementPlanner.plan(
        text: urlCaret,
        selection: NSRange(location: (urlCaret as NSString).length, length: 0)
    ) == nil, "a URL fragment is not treated as an editable word candidate")
}

private func testSharedLayoutCorrectionPolicy() {
    expect(LayoutCorrectionEngine.isMixedScript("ghbkj;ение"), "mixed Latin and Cyrillic text is detected")
    let candidate = LayoutCorrectionEngine.uniqueMixedCandidate(
        typed: "ghbkj;ение",
        currentLanguage: "ru",
        oppositeLanguage: "en",
        currentCandidate: "приложение",
        oppositeCandidate: "ghbkj;tybt",
        isValidWord: { text, language in text == "приложение" && language == "ru" }
    )
    expect(candidate == .init(text: "приложение", language: "ru", changesLayout: false),
           "a unique dictionary-backed candidate keeps the correct existing script")
    expect(LayoutCorrectionEngine.uniqueMixedCandidate(
        typed: "ghbkj;ение",
        currentLanguage: "ru",
        oppositeLanguage: "en",
        currentCandidate: "приложение",
        oppositeCandidate: "application",
        isValidWord: { _, _ in true }
    ) == nil, "two dictionary-valid directions remain ambiguous")
    expect(LayoutCorrectionEngine.shouldApplyContextualRewrite(
        original: "z yt ", corrected: "я не ", currentWordWasConfirmed: true
    ), "a confirmed word can supply context for a pending one-letter token")
    expect(!LayoutCorrectionEngine.shouldApplyContextualRewrite(
        original: "z ", corrected: "я ", currentWordWasConfirmed: false
    ), "a one-letter token cannot create its own correction signal")
    expect(LayoutCorrectionEngine.trustedTermDecision(typed: "iPhone", converted: "шЗрщту") == .preserve,
           "a correctly typed trusted product name stays unchanged")
    expect(LayoutCorrectionEngine.trustedTermDecision(typed: "шЗрщту", converted: "iphone") == .convert("iPhone"),
           "a misspelled-layout product name returns canonical spelling")
    expect(LayoutCorrectionEngine.trustedTermDecision(typed: "IPHONE", converted: "шЗрщту") == .preserve,
           "trusted-term lookup does not reinterpret an all-caps token as a brand")
    expect(LayoutCorrectionEngine.canonicalTrustedTerm(for: "iphone") == "iPhone",
           "trusted terms expose their canonical spelling for smart conversion")
    expect(LayoutCorrectionEngine.shouldApplyContextualRewrite(
        original: "rfr kb jy ", corrected: "как ли он ", currentWordWasConfirmed: true,
        hasAmbiguousShortWordCorrection: true
    ), "a confirmed phrase can rewrite an ambiguous two-letter word")
    expect(!LayoutCorrectionEngine.shouldApplyContextualRewrite(
        original: "kb ", corrected: "ли ", currentWordWasConfirmed: true
    ), "an ambiguous two-letter word cannot trigger its own contextual rewrite")
    expect(LayoutCorrectionEngine.shouldPreserveInputLanguageForTrustedName(
        corrected: "iphone", prefix: "привет, я купил ", currentLanguage: "ru"
    ), "a recognized product name does not switch the input language in a clear Russian phrase")
    expect(!LayoutCorrectionEngine.shouldPreserveInputLanguageForTrustedName(
        corrected: "iphone", prefix: "hello there ", currentLanguage: "ru"
    ), "an English prefix does not get an unrelated Russian-layout override")
    expect(!LayoutCorrectionEngine.shouldPreserveInputLanguageForTrustedName(
        corrected: "iphone", prefix: "привет, я купил ", currentLanguage: "en"
    ), "an explicit English input source remains authoritative")
    expect(LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
        corrected: "hello", prefix: "привет ", currentLanguage: "ru", targetLanguage: "en",
        targetIsConfirmedWord: true
    ), "correcting one foreign word inside a Russian sentence keeps the Russian input source")
    expect(LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
        corrected: "hello", prefix: "привет ", currentLanguage: "ru", targetLanguage: "en",
        targetIsConfirmedWord: true,
        isKnownTargetWord: { word, language in language == "en" && word == "hello" }
    ), "one corrected English word inside a Russian sentence does not switch the input source")
    expect(!LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
        corrected: "hello", prefix: "привет ", currentLanguage: "ru", targetLanguage: "en",
        targetIsConfirmedWord: true, requiredConsecutiveTargetWords: 1,
        isKnownTargetWord: { word, language in language == "en" && word == "hello" }
    ), "the optional one-word threshold switches after one confirmed target word")
    expect(!LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
        corrected: "language", prefix: "я всего лишь want ", currentLanguage: "ru", targetLanguage: "en",
        targetIsConfirmedWord: true,
        isKnownTargetWord: { word, language in
            language == "en" && ["want", "language"].contains(word.lowercased())
        }
    ), "the second confirmed English word in 'я всего лишь want language' switches the input source")
    expect(LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
        corrected: "language", prefix: "я всего лишь want и ", currentLanguage: "ru", targetLanguage: "en",
        targetIsConfirmedWord: true,
        isKnownTargetWord: { word, language in
            language == "en" && ["want", "language"].contains(word.lowercased())
        }
    ), "a Russian word between English terms breaks the consecutive-word transition signal")
    expect(LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
        corrected: "hello", prefix: "привет hello привет ", currentLanguage: "ru", targetLanguage: "en",
        targetIsConfirmedWord: true,
        isKnownTargetWord: { word, language in language == "en" && word.lowercased() == "hello" }
    ), "a corrected English word followed by Russian text keeps Russian as the active input layout")
    expect(LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
        corrected: "language", prefix: "привет hello мир there привет ",
        currentLanguage: "ru", targetLanguage: "en", targetIsConfirmedWord: true,
        isKnownTargetWord: { _, language in language == "en" }
    ), "nonconsecutive English words elsewhere in Russian context do not switch the active layout")
    expect(!LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
        corrected: "hello", prefix: "привет hello there ", currentLanguage: "ru", targetLanguage: "en",
        targetIsConfirmedWord: true,
        isKnownTargetWord: { _, language in language == "en" }
    ), "two consecutive valid English words confirm a language transition")
    expect(!LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
        corrected: "hello", prefix: "hello there ", currentLanguage: "ru", targetLanguage: "en",
        targetIsConfirmedWord: true,
        isKnownTargetWord: { _, _ in true }
    ), "an all-English prefix is not mistaken for Russian sentence context")
    expect(!LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
        corrected: "hello", prefix: "привет hello there ", currentLanguage: "ru", targetLanguage: "en",
        targetIsConfirmedWord: true,
        isKnownTargetWord: { _, _ in true }
    ), "multiple foreign words can signal a deliberate language transition")
    expect(LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
        corrected: "hello", prefix: "привет ", currentLanguage: "ru", targetLanguage: "en",
        targetIsConfirmedWord: false
    ) == false, "an unconfirmed foreign candidate does not alter input-source behavior")
    expect(LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
        corrected: "привет", prefix: "hello ", currentLanguage: "en", targetLanguage: "ru",
        targetIsConfirmedWord: true
    ), "the same context policy works from English into a Russian word")
}

private func testHyphenatedLayoutCorrectionPolicy() {
    let targetWords: Set<String> = ["как", "то", "по", "английски"]
    expect(HyphenatedTokenPolicy.shouldTrackHyphen(after: "r"),
           "a hyphen after a letter remains attached to the current token")
    expect(HyphenatedTokenPolicy.shouldTrackHyphen(after: "-"),
           "a repeated hyphen remains in the same rejected token")
    expect(!HyphenatedTokenPolicy.shouldTrackHyphen(after: nil),
           "a leading hyphen does not start an auto-conversion token")
    expect(!HyphenatedTokenPolicy.shouldTrackHyphen(after: ","),
           "a hyphen after punctuation cannot attach to a stale word range")
    expect(HyphenatedTokenPolicy.decide(
        typed: "rfr-nj", converted: "как-то", currentLanguage: "en", targetLanguage: "ru",
        isValidWord: { word, language in language == "ru" && targetWords.contains(word.lowercased()) }
    ) == .convert, "a hyphenated RU phrase converts when every target segment is trusted")
    expect(HyphenatedTokenPolicy.decide(
        typed: "set-up", converted: "ыуе-гз", currentLanguage: "en", targetLanguage: "ru",
        isValidWord: { word, language in language == "en" && word == "set" }
    ) == .keep, "a valid source compound is preserved when its mapped form is not trusted")
    expect(HyphenatedTokenPolicy.decide(
        typed: "rfr--nj", converted: "как--то", currentLanguage: "en", targetLanguage: "ru",
        isValidWord: { _, _ in true }
    ) == .undecided, "malformed hyphen runs are never auto-converted")
    expect(HyphenatedTokenPolicy.decide(
        typed: "rfr-1j", converted: "как-1о", currentLanguage: "en", targetLanguage: "ru",
        isValidWord: { _, _ in true }
    ) == .undecided, "digit-containing compounds remain outside automatic conversion")
}

private func testReviewedRuleCleanupKeepsPuntoDeletionTombstones() {
    let imported = ProfileRule(
        id: "punto-app-row", pattern: "app", match: .unverifiedPunto,
        action: .neverConvert, origin: .punto, sourceIndex: 0,
        sourceTypeCode: 12, sourceFlags: [false, true, false]
    )
    var profile = MultiSwitcherProfile(
        settings: [ProfileRuleMaintenance.deniedWordsSettingKey: .strings(["ФЗЗ", "app", "keep"])],
        rules: [
            imported,
            ProfileRule(pattern: "фзз", match: .exact, action: .neverConvert, origin: .user),
            ProfileRule(pattern: "keep", match: .exact, action: .neverConvert, origin: .user),
        ],
        importedPuntoRules: [imported]
    )
    let removed = ProfileRuleMaintenance.removeExactExclusions(["фзз", "app"], from: &profile)
    expect(removed == 4, "cleanup removes selected rules and legacy entries")
    expect(!profile.rules.contains { ["фзз", "app"].contains($0.pattern.lowercased()) },
           "reviewed words no longer block correction")
    expect(profile.rules.contains { $0.pattern == "keep" }, "unrelated exclusions remain intact")
    expect(profile.settings[ProfileRuleMaintenance.deniedWordsSettingKey] == .strings(["keep"]),
           "the legacy exclusion array keeps unrelated words")
    if case .strings(let tombstones) = profile.settings[PuntoProfileMigration.removedRuleIDsSettingKey] {
        expect(tombstones.count == 1, "the imported row receives a stable deletion tombstone")
    } else {
        expect(false, "the imported row deletion tombstone is retained")
    }
}


private func testExactTextUndoTogglesOnlyUnchangedField() {
    let original = "search привет,   "
    let converted = "search ghbdtn,   "
    let originalSelection = NSRange(location: (original as NSString).length, length: 0)
    let convertedSelection = NSRange(location: (converted as NSString).length, length: 0)
    var state = ExactTextUndoState(
        originalText: original,
        convertedText: converted,
        originalSelection: originalSelection,
        convertedSelection: convertedSelection
    )

    expect(state.toggle(currentText: converted,
                        currentSelection: NSRange(location: convertedSelection.location - 1, length: 0)) == nil,
           "a moved caret invalidates the exact second-trigger undo")
    let undone = state.toggle(currentText: converted, currentSelection: convertedSelection)
    expect(undone?.text == original && undone?.selection == originalSelection && undone?.isConverted == false,
           "second trigger restores the complete original query and caret")
    expect(state.toggle(currentText: "edited by user") == nil,
           "a changed field invalidates the saved undo pair")
    expect(state.toggle(currentText: original,
                        currentSelection: NSRange(location: originalSelection.location - 1, length: 0)) == nil,
           "a moved caret also invalidates a later redo")
    let redone = state.toggle(currentText: original, currentSelection: originalSelection)
    expect(redone?.text == converted && redone?.selection == convertedSelection && redone?.isConverted == true,
           "a later trigger can restore the exact converted query when contents still match")
}

private func testTextFieldSnapshotRejectsStaleCaretOrTarget() {
    let expected = TextFieldEditSnapshot(
        processID: 42,
        identity: 7,
        value: "search привет",
        selection: NSRange(location: 13, length: 0)
    )
    expect(expected == TextFieldEditSnapshot(processID: 42, identity: 7,
                                             value: "search привет",
                                             selection: NSRange(location: 13, length: 0)),
           "unchanged field and caret permit a pending replacement")
    expect(expected != TextFieldEditSnapshot(processID: 42, identity: 7,
                                             value: "search привет",
                                             selection: NSRange(location: 12, length: 0)),
           "a moved caret invalidates a pending replacement")
    expect(expected != TextFieldEditSnapshot(processID: 42, identity: 7,
                                             value: "search привет!",
                                             selection: NSRange(location: 13, length: 0)),
           "a changed query invalidates a pending replacement")
    expect(expected != TextFieldEditSnapshot(processID: 42, identity: 8,
                                             value: "search привет",
                                             selection: NSRange(location: 13, length: 0)),
           "a changed focused field invalidates a pending replacement")
}

private func testClipboardRestoreRequiresOwnership() {
    expect(ClipboardRestorePolicy.mayRestore(savedChangeCount: 4, ownedChangeCount: 6,
                                             currentChangeCount: 6),
           "saved clipboard restores while MultiSwitcher still owns the generation")
    expect(!ClipboardRestorePolicy.mayRestore(savedChangeCount: 4, ownedChangeCount: 6,
                                              currentChangeCount: 7),
           "a newer user copy is never overwritten")
    expect(!ClipboardRestorePolicy.mayRestore(savedChangeCount: 4, ownedChangeCount: nil,
                                              currentChangeCount: 4),
           "an unchanged clipboard needs no restore")
}

private func testDiagnosticLogRedaction() {
    let fakeCredential = "ghp_" + String(repeating: "A", count: 36)
    let raw = "path=/Users/example-user/Library/Logs/app.log\nother=/Users/other-person/Documents/private.txt\nbundle=com.example.editor\nquery=private words\nurl=https://example.com/private?token=abc\nopened https://example.org/secret/path\ncontact person@example.com\nremote 192.0.2.4\nremote6 2001:db8::1\ncredential \(fakeCredential)"
    let report = DiagnosticLogRedactor.redact(raw, homeDirectory: "/Users/example-user")
    expect(report.contains("~/Library/Logs/app.log") && report.contains("[local-path]"),
           "diagnostic reports redact the home directory and other absolute local paths")
    expect(report.contains("[app-id]"), "diagnostic reports redact third-party bundle identifiers")
    expect(!report.contains("com.example.editor") && !report.contains("private words")
           && !report.contains("example.com/private") && !report.contains("example.org/secret") && !report.contains("person@example.com")
           && !report.contains("192.0.2.4") && !report.contains("2001:db8::1") && !report.contains(fakeCredential),
           "diagnostic reports redact message values, URLs, emails, IP addresses, and credentials before preview")
}

private func testProfileStoreImportIsRepeatableAndSnapshotsSource() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MultiSwitcher-Core-Test-\\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceURL = root.appendingPathComponent("punto.plist")
    let profileRoot = root.appendingPathComponent("profile", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let sourceData = try propertyListData([
        "userRulesDictionary": [["fresh-rule", 12, false, true, false]],
        "undoLearning": ["undoDictionary": ["kept-history": 2]],
    ])
    try sourceData.write(to: sourceURL)

    let store = ProfileStore(rootURL: profileRoot)
    try store.update { profile in
        profile.rules.append(ProfileRule(pattern: "my-own", origin: .user))
    }
    let first = try store.importPuntoProfile(from: sourceURL)
    expect(first.rulesImported == 1 && first.learningImported == 1,
           "the first import copies rules and pending learning")
    try store.update { profile in
        profile.rules.append(ProfileRule(pattern: "removed-in-source", origin: .punto))
    }

    let second = try store.importPuntoProfile(from: sourceURL)
    let profile = store.current
    expect(second.rulesImported == 1, "repeat import reports the current source rows")
    expect(profile.rules.filter { $0.origin == .punto }.count == 1,
           "repeat import replaces Punto rows and removes obsolete ones")
    expect(profile.rules.contains { $0.origin == .user && $0.pattern == "my-own" },
           "repeat import preserves local rules")
    expect(profile.learning.filter { $0.origin == .punto }.count == 1,
           "repeat import replaces only Punto learning")
    expect(FileManager.default.contents(atPath: sourceURL.path) == sourceData,
           "import never changes the source Punto file")
    let snapshots = (try FileManager.default.contentsOfDirectory(
        at: store.backupsURL, includingPropertiesForKeys: nil
    )).filter { $0.lastPathComponent.hasPrefix("Punto-") }
    expect(snapshots.count == 2, "each import has its own recoverable source snapshot")
}

private func testProfileSchemaMigrationSeparatesImportedHistory() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MultiSwitcher-Schema-Test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let legacy = MultiSwitcherProfile(
        schemaVersion: 1,
        learning: [LearningEntry(word: "legacy-history", cancellationCount: 97, origin: .punto)]
    )
    try JSONEncoder().encode(legacy).write(to: root.appendingPathComponent("profile.json"))

    let store = ProfileStore(rootURL: root)
    let migrated = store.current
    expect(migrated.schemaVersion == MultiSwitcherProfile.currentSchemaVersion,
           "schema 1 profile migrates in memory to the current schema")
    expect(migrated.learning.first?.cancellationCount == 0
           && migrated.learning.first?.importedCancellationCount == 97,
           "migration separates Punto history from fresh automatic undo counts")
    try store.update { $0.settings["migration-check"] = .bool(true) }
    let saved = try JSONDecoder().decode(MultiSwitcherProfile.self,
                                         from: Data(contentsOf: store.profileURL))
    expect(saved.schemaVersion == MultiSwitcherProfile.currentSchemaVersion,
           "the next profile write persists the migrated schema")
}

private func testProfileBackupSnapshotIsPrivateAndVerifiable() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MultiSwitcher-Backup-Test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProfileStore(rootURL: root.appendingPathComponent("profile", isDirectory: true))
    _ = try store.update { profile in
        profile.rules.append(ProfileRule(pattern: "private-rule", origin: .user))
    }
    let beforeUpdate = try Data(contentsOf: store.profileURL)
    let snapshot = try store.createBackupSnapshot(label: "before-update")
    let copiedProfile = try Data(contentsOf: snapshot.appendingPathComponent("profile.json"))
    let manifestData = try Data(contentsOf: snapshot.appendingPathComponent("manifest.json"))
    let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
    let digest = SHA256.hash(data: copiedProfile).map { String(format: "%02x", $0) }.joined()
    expect(copiedProfile == beforeUpdate, "pre-update snapshots preserve the exact serialized profile bytes")
    expect(manifest?["profileSHA256"] as? String == digest,
           "profile snapshot manifest contains a verifiable SHA-256")
    let permissions = try FileManager.default.attributesOfItem(atPath: snapshot.path)[.posixPermissions] as? NSNumber
    expect(permissions?.intValue == 0o700, "profile snapshot directories are private to the user")
}

private func testProfileStoreRecoveryPreservesDamagedPrimary() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("MultiSwitcher-Recovery-Test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ProfileStore(rootURL: root)
    try store.update { $0.settings["recovery-marker"] = .string("previous-valid") }
    try store.update { $0.settings["recovery-marker"] = .string("current-valid") }
    let damaged = Data("not a profile".utf8)
    try damaged.write(to: store.profileURL, options: .atomic)

    let recoveryStore = ProfileStore(rootURL: root)
    expect(recoveryStore.isInRecoveryMode, "an unreadable profile is surfaced as recovery mode")
    expect(recoveryStore.canRestorePreviousProfile, "a valid previous generation is offered for recovery")
    do {
        try recoveryStore.update { $0.settings["recovery-marker"] = .string("must-not-write") }
        expect(false, "profile writes stay blocked until recovery")
    } catch {
        expect(true, "an unreadable profile is never silently overwritten")
    }

    let restored = try recoveryStore.restorePreviousProfile()
    expect(!recoveryStore.isInRecoveryMode, "successful restore clears recovery mode")
    expect(restored.settings["recovery-marker"] == .string("previous-valid"),
           "restore uses the previous valid generation")
    expect(FileManager.default.contents(atPath: store.profileURL.path) != damaged,
           "the active profile is repaired from the validated snapshot")
    let recoveryFiles = try FileManager.default.contentsOfDirectory(
        at: store.backupsURL, includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("profile-unreadable-") }
    expect(recoveryFiles.count == 1 && FileManager.default.contents(atPath: recoveryFiles[0].path) == damaged,
           "the unreadable original is retained as a recovery backup")
}

private func testImportedRuleRemovalSurvivesReimportAndCanBeRestored() throws {
    let data = try propertyListData([
        "userRulesDictionary": [
            ["keep-me", 12, false, true, false],
            ["remove-me", 13, false, true, false],
        ],
    ])
    let report = try PuntoProfileImporter.parse(data: data)
    var profile = MultiSwitcherProfile()
    _ = PuntoProfileMigration.apply(report, sourceSnapshotName: "snapshot/profile.plist",
                                    sourceSHA256: "test", to: &profile)
    let removed = report.profileRules[1]
    expect(PuntoProfileMigration.removeImportedRule(removed.id, from: &profile),
           "an imported Punto row can be removed from the local profile")
    expect(!profile.rules.contains(where: { $0.id == removed.id }),
           "removed Punto row disappears immediately")

    _ = PuntoProfileMigration.apply(report, sourceSnapshotName: "snapshot/profile.plist",
                                    sourceSHA256: "test", to: &profile)
    expect(!profile.rules.contains(where: { $0.id == removed.id }),
           "a repeat import does not resurrect a locally removed Punto row")
    expect(profile.rules.contains(where: { $0.pattern == "keep-me" }),
           "other imported Punto rows remain intact")

    expect(PuntoProfileMigration.restoreRemovedRules(in: &profile) == 1,
           "removed rows can be restored from the retained imported source snapshot")
    expect(profile.rules.contains(where: { $0.id == removed.id }),
           "restoring re-adds the exact source row")
    _ = PuntoProfileMigration.apply(report, sourceSnapshotName: "snapshot/profile.plist",
                                    sourceSHA256: "test", to: &profile)
    expect(profile.rules.contains(where: { $0.id == removed.id }),
           "a restored Punto row remains present after a later import")

    let reordered = try PuntoProfileImporter.parse(data: propertyListData([
        "userRulesDictionary": [
            ["new-row", 12, false, true, false],
            ["keep-me", 12, false, true, false],
            ["remove-me", 13, false, true, false],
        ],
    ]))
    expect(PuntoProfileMigration.stableRuleKey(reordered.profileRules[2])
            == PuntoProfileMigration.stableRuleKey(removed),
           "Punto rule identity stays stable when unrelated rows are inserted")

    let duplicates = try PuntoProfileImporter.parse(data: propertyListData([
        "userRulesDictionary": [
            ["same-row", 12, false, true, false],
            ["same-row", 12, false, true, false],
        ],
    ]))
    var duplicateProfile = MultiSwitcherProfile()
    _ = PuntoProfileMigration.apply(duplicates, sourceSnapshotName: "snapshot/duplicates.plist",
                                    sourceSHA256: "test", to: &duplicateProfile)
    expect(PuntoProfileMigration.removeImportedRule(duplicates.profileRules[1].id,
                                                     from: &duplicateProfile),
           "one of two identical imported rows can be removed individually")
    _ = PuntoProfileMigration.apply(duplicates, sourceSnapshotName: "snapshot/duplicates.plist",
                                    sourceSHA256: "test", to: &duplicateProfile)
    expect(duplicateProfile.rules.filter { $0.origin == .punto }.count == 1,
           "removing a duplicate does not suppress the other identical source row")
}

if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--import-punto-profile" {
    let source = URL(fileURLWithPath: CommandLine.arguments[2])
    let root = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    let report = try ProfileStore(rootURL: root).importPuntoProfile(from: source)
    print("Punto profile imported: \(report.rulesImported) rules; \(report.learningImported) source history entries; \(report.learningDiscardedByReview) source entries omitted; snapshot \(report.snapshotName); SHA-256 \(report.sourceSHA256)")
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--add-local-exception" {
    let word = CommandLine.arguments[2].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !word.isEmpty else { throw PuntoProfileImportError.missingRules }
    let store = ProfileStore(rootURL: URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true))
    _ = try store.reload()
    var added = false
    try store.update { profile in
        let key = word.precomposedStringWithCanonicalMapping.lowercased()
        let exists = profile.rules.contains {
            $0.origin == .user && $0.action == .neverConvert && $0.match == .exact
                && $0.pattern.precomposedStringWithCanonicalMapping.lowercased() == key
        }
        guard !exists else { return }
        profile.rules.append(ProfileRule(
            pattern: word,
            match: .exact,
            action: .neverConvert,
            enabled: true,
            caseSensitive: false,
            origin: .user,
            semanticStatus: .verified,
            sourceTypeCode: 13,
            sourceFlags: [false, true, false]
        ))
        added = true
    }
    print(added ? "Added one local exact exception." : "Local exact exception already present.")
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--audit-punto-profile" {
    let report = try PuntoProfileImporter.read(from: URL(fileURLWithPath: CommandLine.arguments[2]))
    print("Punto profile parsed: \(report.rules.count) rules, \(report.neverConvertWords.count) supported unique words, \(report.learnedEntryCount) history entries, \(report.unsupportedRules.count) unsupported rules")
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--cleanup-reviewed-exceptions" {
    let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let backupDirectory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    let store = ProfileStore(rootURL: root)
    _ = try store.reload()
    guard FileManager.default.fileExists(atPath: store.profileURL.path) else {
        fputs("No MultiSwitcher profile exists; nothing was changed.\n", stderr)
        exit(EXIT_FAILURE)
    }
    try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let backup = backupDirectory.appendingPathComponent("profile-before-reviewed-rule-cleanup-\(stamp).json")
    try FileManager.default.copyItem(at: store.profileURL, to: backup)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)

    var removed = 0
    try store.update { profile in
        removed = ProfileRuleMaintenance.removeExactExclusions(["фзз", "app"], from: &profile)
    }
    UserDefaults.standard.removeObject(forKey: ProfileRuleMaintenance.deniedWordsSettingKey)
    print("Reviewed exclusions cleaned: \(removed) stored entries removed; backup saved as \(backup.lastPathComponent).")
    exit(EXIT_SUCCESS)
}

testInterfaceChromeCasingPreservesDataAndKeys()
testSpotlightTargetClassification()
testAutomaticLayoutTransitionPolicy()
testGlobalSpaceShortcutsPreserveOnlyLayoutSwitchWords()
testPauseStateExpiry()
testUpdateChannelSelection()
testAppendedInputPolicy()
testSettingsCardLayoutPolicy()
testAutomaticShortWordPolicy()
testAutomaticDictionaryDecision()
testHyphenatedLayoutCorrectionPolicy()
testModifiedBackspaceInvalidatesTrackedText()
testSerialReplacementQueueIsBoundedAndFIFO()
testDefaultReplacementQueueHandlesRapidToggleBursts()
testReplacementQueueReportsSafeDiagnosticState()
testBufferReplacementLifecycleTracksExactUndoDirection()
testBundledWordLexicon()
try testImportsRulesAndSeparatesLearnedHistory()
try testUnicodeEquivalentWordsAreDeduplicated()
try testMalformedRuleRejectsWholeImport()
try testMissingRulesAreRejected()
try testPuntoHistoryIsPreservedAndRuleProvenance()
try testLearningNeedsTwoAutomaticUndos()
testManualOptionLearningNeedsReview()
testLearningCandidatesAppearBeforeImportedHistory()
testManualOptionLearningRequiresExactToggleChain()
testQueuedManualOptionToggleCanFollowItsOwnReplacement()
try testTenManualOptionTapsCreateVisibleReviewCandidate()
testAutomaticLearningUsesFreshUniqueOperations()
testLearningEvidenceMustMatchSameOperationContext()
testSpotlightRangePlannerPreservesQueryAndCaret()
testSharedLayoutCorrectionPolicy()
testReviewedRuleCleanupKeepsPuntoDeletionTombstones()
testExactTextUndoTogglesOnlyUnchangedField()
testTextFieldSnapshotRejectsStaleCaretOrTarget()
testClipboardRestoreRequiresOwnership()
testDiagnosticLogRedaction()
try testProfileBackupSnapshotIsPrivateAndVerifiable()
testForgettingLearningPreservesImportedAndUserRules()
try testProfileStoreImportIsRepeatableAndSnapshotsSource()
try testProfileSchemaMigrationSeparatesImportedHistory()
try testProfileStoreRecoveryPreservesDamagedPrimary()
try testImportedRuleRemovalSurvivesReimportAndCanBeRestored()
try testPerAppLayoutMemorySurvivesProfileSerialization()
testApplicationExclusionPolicy()
testTypedRuleMatchingAndProvenance()
try testProfileStoreGenerationTracksSnapshots()
try testUserRuleFileRoundTripSanitizesProvenance()
try testGenericTextRuleImportsAreExplicitAndPreviewable()
testTrailingKeyboardPunctuation()
print("MultiSwitcherCoreChecks: \(CheckCounter.total) checks passed")
