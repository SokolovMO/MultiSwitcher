import Foundation
import MultiSwitcherCore

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
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


private func testReviewedHistoryMigrationAndRuleProvenance() throws {
    let history: [String: Int] = [
        "сделатй": 1, "нужн": 1, "шбор": 1, "ытой": 1, ";nj": 1, "shla": 1,
        "еюьу": 2, "t.me": 1, "retained": 1,
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
    expect(applied.learningDiscardedByReview == 6, "the six approved history records are removed")
    expect(destination.rules.filter { $0.origin == .punto }.count == 2, "Punto provenance is assigned")
    expect(destination.rules.first(where: { $0.pattern == "second" })?.sourceFlags == [true, false, true],
           "raw rule flags are preserved")
    expect(destination.rules.contains(where: { $0.pattern == "my-own" && $0.origin == .user }),
           "user rules survive import")
    expect(destination.learning.contains(where: { $0.word == "local" && $0.origin == .local }),
           "local learning survives import")
    expect(destination.learning.count == 3, "renamed collision merges without discarding unrelated history")
    let renamed = destination.learning.first(where: { $0.word == "t.me" })
    expect(renamed?.cancellationCount == 2 && renamed?.isExcluded == false,
           "еюьу is renamed to t.me and stays pending, not an active exception")
    expect(destination.settings["com.multiswitcher.autoConvert"] == .bool(true),
           "verified automatic-correction setting is mapped")
}

private func testLearningNeedsTwoAutomaticUndos() throws {
    var profile = MultiSwitcherProfile()
    let first = LearningEngine.recordAutomaticCancellation(word: "shiishka", in: &profile)
    expect(first == .pending(cancellations: 1), "first cancellation remains pending")
    expect(!profile.rules.contains(where: { $0.origin == .learned }), "one undo does not create an exception")
    let second = LearningEngine.recordAutomaticCancellation(word: "shiishka", in: &profile)
    expect(second == .excluded(word: "shiishka"), "second cancellation creates the learned exception")
    expect(profile.rules.contains(where: { $0.origin == .learned && $0.pattern == "shiishka" }),
           "learned rule is stored separately")
    expect(LearningEngine.undoLearnedExclusion(word: "shiishka", in: &profile),
           "last learned exclusion can be undone")
    expect(!profile.rules.contains(where: { $0.origin == .learned }), "undo removes only learned rule")

    profile.settings["com.multiswitcher.learningEnabled"] = .bool(false)
    expect(LearningEngine.recordAutomaticCancellation(word: "another", in: &profile) == .disabled,
           "disabled learning does not record a cancellation")
    profile.settings["com.multiswitcher.learningEnabled"] = .bool(true)
    expect(LearningEngine.recordAutomaticCancellation(word: "no", in: &profile) == .ineligible,
           "short combinations are ignored")
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
    expect(ProfileRuleEngine.evaluate(typed: "teh", converted: "the",
                                      rules: [ProfileRule(pattern: "teh", replacement: "the", action: .replace, origin: .punto)]) == .none,
           "unverified imported Punto replacement actions stay inactive")
    expect(ProfileRuleEngine.evaluate(typed: "wrong", converted: "brand", rules: [
        ProfileRule(pattern: "brand", action: .neverConvert, origin: .punto,
                    semanticStatus: .unverifiedPuntoType),
        ProfileRule(pattern: "brand", action: .alwaysConvert, origin: .user),
    ]) == .alwaysConvert, "explicit user rules take precedence over imported Punto rows")
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
    print("Punto profile imported: \(report.rulesImported) rules; \(report.learningImported) reviewed history entries; \(report.learningDiscardedByReview) history entries removed by prior review; snapshot \(report.snapshotName); SHA-256 \(report.sourceSHA256)")
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

testSpotlightTargetClassification()
testGlobalSpaceShortcutsPreserveOnlyLayoutSwitchWords()
try testImportsRulesAndSeparatesLearnedHistory()
try testUnicodeEquivalentWordsAreDeduplicated()
try testMalformedRuleRejectsWholeImport()
try testMissingRulesAreRejected()
try testReviewedHistoryMigrationAndRuleProvenance()
try testLearningNeedsTwoAutomaticUndos()
testSpotlightRangePlannerPreservesQueryAndCaret()
testSharedLayoutCorrectionPolicy()
testReviewedRuleCleanupKeepsPuntoDeletionTombstones()
testExactTextUndoTogglesOnlyUnchangedField()
testTextFieldSnapshotRejectsStaleCaretOrTarget()
testClipboardRestoreRequiresOwnership()
testForgettingLearningPreservesImportedAndUserRules()
try testProfileStoreImportIsRepeatableAndSnapshotsSource()
try testImportedRuleRemovalSurvivesReimportAndCanBeRestored()
try testPerAppLayoutMemorySurvivesProfileSerialization()
testApplicationExclusionPolicy()
testTypedRuleMatchingAndProvenance()
try testUserRuleFileRoundTripSanitizesProvenance()
print("MultiSwitcherCoreChecks: 21 checks passed")
