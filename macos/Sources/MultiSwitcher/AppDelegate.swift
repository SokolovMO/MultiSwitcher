import AppKit
@preconcurrency import ApplicationServices
import MultiSwitcherCore

@MainActor private final class NativeMenuAuditState {
    var failures: [String] = []
    var captures: [[String: Any]] = []
    let transitions: [[String: Any]]
    init(transitions: [[String: Any]]) { self.transitions = transitions }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum AutomaticInputLayoutResult {
        case kept
        case alreadyTarget
        case switched
        case preservedUserChoice
        case unavailable

        var changedLayout: Bool { if case .switched = self { return true }; return false }
        var logValue: String {
            switch self {
            case .kept: return "kept"
            case .alreadyTarget: return "already-target"
            case .switched: return "switched"
            case .preservedUserChoice: return "manual-choice-preserved"
            case .unavailable: return "switch-failed"
            }
        }
    }

    private var statusItem: NSStatusItem!
    private var statusMenuTracking = false
    private var statusMenuNeedsRebuild = false
    private var statusMenu: NSMenu?
    private let layoutPresentation = LayoutPresentationState {
        let id = LayoutSwitcher.currentLayoutID()
        let sources = LayoutSwitcher.installedLayouts().map {
            LayoutPresentationSnapshot.Source(id: LayoutSwitcher.sourceID($0),
                name: LayoutSwitcher.sourceName($0), language: LayoutSwitcher.languageCode($0))
        }
        return LayoutPresentationSnapshot(selectedID: id, sources: sources,
            language: sources.first(where: { $0.id == id })?.language ?? LayoutSwitcher.currentLanguageCode())
    }
    private var statusPopover: StatusPopoverController?
    private let keyboardMonitor = KeyboardMonitor()
    private let textConverter = TextConverter()
    private let settingsController = SettingsWindowController()
    private let perAppLayoutManager = PerAppLayoutManager()
    private var helpController: HelpWindowController?
    private var permissionsGuide: PermissionsGuideWindowController?
    private var settingsWindowVisible = false
    private var iconRefreshTimer: Timer?
    #if !canImport(Sparkle)
    private var updateCheckTimer: Timer?
    #endif
    private var pauseExpiryWorkItem: DispatchWorkItem?
    private var monitoringActive = false
    private var monitoringStartPending = false
    private var caretIndicator: CaretIndicator?   // issue #10: метка раскладки у каретки (бета, по умолчанию OFF)
    private let secureNotice = SecureInputNotice()  // issue #27: подсказка о защ. вводе без кражи фокуса
    private let learningNotice = LearningNotice()
    private var lastLearnedWord: String?
    private var lastSourceShown: String?
    func applicationDidFinishLaunching(_ notification: Notification) {
        DesignTheme.shared.apply()
        if let directory = ProcessInfo.processInfo.environment["MULTI_AUDIT_DATA_ROOT"],
           ProcessInfo.processInfo.environment["MULTI_AUDIT_SCENARIO"] == "native" {
            setupStatusItem()
            setupSettingsCallbacks()
            settingsController.auditPageTransitions { [weak self] transitions in
                self?.auditNativeMenu(directory: directory, transitions: transitions)
            }
            return
        }
        if let directory = ProcessInfo.processInfo.environment["MULTISWITCHER_PERMISSION_REVIEW"] {
            reviewPermissionsGuide(to: directory)
            return
        }
        if let directory = ProcessInfo.processInfo.environment["MULTISWITCHER_UI_REVIEW"] ?? ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] {
            let originalTheme = DesignTheme.shared.preference
            setupStatusItem()
            setupSettingsCallbacks()
            if ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_INTERACTIVE"] == "1" {
                settingsController.showWindow()
                return
            }
            if ProcessInfo.processInfo.environment["MULTISWITCHER_LAYOUT_LIVE_REVIEW"] == "1" {
                reviewSystemLayout(to: directory)
                return
            }
            settingsController.captureReview(to: directory) { [weak self] in
                guard let self else { NSApp.terminate(nil); return }
                @MainActor func capturePopover(_ index: Int) {
                    guard index < 2 else {
                        DesignTheme.shared.preference = originalTheme
                        NSApp.terminate(nil)
                        return
                    }
                    DesignTheme.shared.preference = index == 0 ? .light : .dark
                    self.toggleLegacyPopoverForReview()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if let window = self.statusPopover?.reviewWindow {
                            let theme = index == 0 ? "light" : "dark"
                            SettingsWindowController.captureWindow(window, to: directory + "/\(theme)-popover.png")
                            if let geometry = self.statusPopover?.reviewGeometry {
                                try? JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: directory + "/\(theme)-geometry.json"))
                            }
                        }
                        let theme = index == 0 ? "light" : "dark"
                        if let button = self.statusItem.button, let window = button.window {
                            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
                            SettingsWindowController.captureScreenRegion(rect, to: directory + "/\(theme)-menubar-screen-region.png")
                            SettingsWindowController.captureView(button, to: directory + "/\(theme)-menubar-native-view.png")
                        }
                        self.statusPopover?.openFirstSubmenuForReview()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if let window = self.statusPopover?.reviewWindow {
                                SettingsWindowController.captureWindow(window, to: directory + "/\(theme)-layout-menu.png")
                            }
                            self.statusPopover?.close()
                            self.learningNotice.show(title: L10n.learningPendingTitle,
                                body: L10n.learningPendingBody(1), near: self.statusItem.button)
                            self.secureNotice.show(title: L10n.securePausedTitle,
                                body: String(format: L10n.securePausedBody, "multiswitcher ui review"))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                SettingsWindowController.captureWindow(self.learningNotice.reviewWindow, to: directory + "/\(theme)-learning-notice.png")
                                SettingsWindowController.captureWindow(self.secureNotice.reviewWindow, to: directory + "/\(theme)-secure-notice.png")
                                self.learningNotice.reviewWindow.orderOut(nil)
                                self.secureNotice.reviewWindow.orderOut(nil)
                                self.showHelp()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    self.showPermissionsGuide(accessibilityGranted: false, inputMonitoringGranted: false)
                                    capturePopover(index + 1)
                                }
                            }
                        }
                    }
                }
                // Record the real native popover, including dismissal/reopening.
                self.toggleLegacyPopoverForReview()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if let window = self.statusPopover?.reviewWindow {
                        let recorder = Process()
                        recorder.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                        recorder.arguments = ["-x", "-v", "-V", "3", "-l", String(window.windowNumber), directory + "/popover-open-close.mov"]
                        try? recorder.run()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            self.statusPopover?.close()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.toggleLegacyPopoverForReview() }
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                        self.statusPopover?.close()
                        capturePopover(0)
                    }
                }
            }
            return
        }
        Dict.preloadBundledLexiconsIfNeeded()
        SettingsManager.shared.clearExpiredPause()
        if MultiAuditEnvironment.root == nil {
            CrashReporter.startIfConsented()
            UpdateChecker.checkOnLaunch()
        }
        #if !canImport(Sparkle)
        if MultiAuditEnvironment.root == nil { scheduleUpdateChecks() }
        #endif
        setupStatusItem()
        setupSettingsCallbacks()
        syncLoginItem()
        runPermissionWizard()
        if ProcessInfo.processInfo.arguments.contains("--permissions-guide") {
            showPermissionsGuide(accessibilityGranted: AXIsProcessTrusted(), inputMonitoringGranted: CGPreflightListenEventAccess())
        }
        schedulePauseExpiry()
        // Прогрев NSSpellChecker: первый чек поднимает XPC AppleSpell (сотни мс на main) —
        // прогреваем в тихую паузу после старта, а не на первом пробеле пользователя.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            Task { @MainActor in Dict.warmUp() }
        }

        // Скрытая иконка: reopen-событие приходит только УЖЕ работающему приложению.
        // Свежий РУЧНОЙ запуск со скрытой иконкой без этого блока «тих» (ни иконки, ни
        // окна — выглядит как «не запустилось»). Показываем настройки; автологин-старт
        // (флаг login-item в oapp Apple event) остаётся тихим, как и положено.
        if SettingsManager.shared.hideMenuBarIcon && !Self.launchedAsLoginItem() {
            settingsController.showWindow()
        }
        if MultiAuditEnvironment.isFunctional, let root = MultiAuditEnvironment.root {
            if ProcessInfo.processInfo.environment["MULTI_AUDIT_SHOW_SETTINGS"] == "1" { settingsController.showWindow() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                let report: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
                    "accessibility": AXIsProcessTrusted(), "inputMonitoring": CGPreflightListenEventAccess(),
                    "monitoringActive": self.monitoringActive, "autoSwitch": SettingsManager.shared.autoSwitchEnabled,
                    "autoConvert": SettingsManager.shared.autoConvert,
                    "profileRoot": ProfileStore.shared.rootURL.path,
                    "nativeStatusMenu": self.statusItem.menu === self.statusMenu,
                    "windowVisible": self.settingsController.auditWindowIsVisible]
                try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: root.appendingPathComponent("permission-runtime.json"))
            }
        }
    }

    #if !canImport(Sparkle)
    private func scheduleUpdateChecks() {
        updateCheckTimer?.invalidate()
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in UpdateChecker.checkPeriodic() }
        }
    }
    #endif

    /// Запущены ли мы как login item (автостарт): loginwindow помечает oapp-событие
    /// флагом keyAELaunchedAsLogInItem в propData.
    private static func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }

    private func setupSettingsCallbacks() {
        settingsController.onQuitRequested = { [weak self] in self?.quit() }
        settingsController.onPermissionsReviewRequested = { [weak self] in
            self?.runPermissionWizard(interactive: true)
        }
        settingsController.onAutoSwitchChanged = { [weak self] _ in
            // Не адресуем пункт по индексу: с 2.5.0 item(at: 0) — строка версии, а со списком
            // раскладок индексы вообще динамические. Пересборка — как у соседних колбэков.
            self?.rebuildMenu()
            self?.updateStatusIcon()
        }
        settingsController.onPerAppLayoutChanged = { [weak self] enabled in
            guard let self else { return }
            if enabled {
                self.startPerAppLayout()
            } else {
                self.perAppLayoutManager.stop()
            }
        }
        settingsController.onLanguageChanged = { [weak self] in
            self?.rebuildMenu()
        }
        settingsController.onTriggerChanged = { [weak self] in
            self?.reconfigureTap()
        }
        settingsController.onAutoConvertChanged = { [weak self] _ in
            self?.rebuildMenu()  // синхронизировать галочку в меню
            self?.updateStatusIcon()
        }
        settingsController.onRemoteDesktopChanged = { [weak self] _ in
            self?.reconfigureTap()  // уровень tap зависит от режима
            self?.configureIconRefreshFallback()
            self?.rebuildMenu()
        }
        settingsController.onCaretFlagChanged = { [weak self] _ in
            self?.rebuildMenu()          // синхронизировать галочку в меню
            self?.syncCaretIndicator()   // создать/снести индикатор + обновить гейт onUserInput
        }
        settingsController.onHideIconChanged = { [weak self] hide in
            self?.statusItem.isVisible = !hide
        }
        settingsController.onWindowVisibilityChanged = { [weak self] isVisible in
            guard let self else { return }
            self.settingsWindowVisible = isVisible
            // LSUIElement keeps the menu-bar utility out of the app switcher by
            // default. Keep the app switchable while either app-owned window is open.
            NSApp.setActivationPolicy(isVisible || self.permissionsGuide?.window?.isVisible == true ? .regular : .accessory)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Recheck after returning from System Settings; a visible switch may still
        // belong to an older signature. Only the system APIs decide readiness.
        guard statusItem != nil, MultiAuditEnvironment.root == nil else { return }
        runPermissionWizard()
        updateStatusIcon()
        rebuildMenu()
    }

    /// Повторный запуск приложения (двойной клик в «Программах», Spotlight, Launchpad) —
    /// стандартный для menu-bar-утилит путь добраться до настроек при СКРЫТОЙ иконке.
    /// Открываем настройки и при видимой иконке: reopen без реакции выглядит как «не работает».
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsController.showWindow()
        return false
    }

    // MARK: - Learn-from-undo (предложить добавить слово в never-convert)

    /// Последняя авто-конвертация: слово (как было набрано) + время. Если пользователь
    /// сразу откатывает ручным триггером — предлагаем занести слово в исключения.
    private var lastAutoConverted: LearningEvidence?
    private var manualOptionEvidence: ManualOptionLearningEvidence?

    /// Анти-наг для уведомления о защищённом вводе (не чаще раза в N секунд).
    private var lastSecureNoticeAt: Date?

    /// Ручной триггер нажат, но активен защищённый ввод (фокус в поле пароля — часто во
    /// вкладке браузера в фоне) → конверсия by design не трогает клавиши. Без подсказки это
    /// выглядит как «приложение сломалось» (реальный кейс: пользователь мял триггер и лез в
    /// ioreg). Показываем разовое (троттлённое) объяснение с лечением.
    private func notifySecureInputPaused() {
        guard SettingsManager.shared.secureInputNoticeEnabled else { return }
        if let last = lastSecureNoticeAt, Date().timeIntervalSince(last) < 180 { return }
        lastSecureNoticeAt = Date()
        let holder = AutoSwitchPolicy.secureInputHolderName() ?? L10n.securePausedUnknownApp
        // issue #27: неактивирующая плашка вместо NSAlert.runModal() — модалка активировала
        // приложение и уводила фокус из поля пароля (пользователь терял место в терминале).
        secureNotice.show(title: L10n.securePausedTitle,
                          body: String(format: L10n.securePausedBody, holder))
    }

    private func offerExceptionAfterUndo(_ undo: ManualConversionSnapshot, operationID: String?) {
        guard let last = lastAutoConverted,
              last.matchesUndo(
                operationID: operationID,
                processIdentifier: undo.processIdentifier,
                bundleIdentifier: undo.bundleIdentifier,
                textContextGeneration: undo.textContextGeneration,
                at: Date()
              ) else {
            lastAutoConverted = nil
            return
        }
        lastAutoConverted = nil
        let key = last.word.precomposedStringWithCanonicalMapping.lowercased()
        guard !SettingsManager.shared.deniedWordsSet.contains(key) else { return }

        var outcome: LearningOutcome = .disabled
        do {
            try ProfileStore.shared.update { profile in
                outcome = LearningEngine.recordAutomaticCancellation(evidence: last, in: &profile)
            }
        } catch {
            rslog("learn: profile update failed: \(error.localizedDescription)")
            return
        }
        NotificationCenter.default.post(name: .multiSwitcherLearningDidChange, object: nil)

        switch outcome {
        case .pending(let cancellations):
            learningNotice.show(title: L10n.learningPendingTitle,
                                body: L10n.learningPendingBody(cancellations),
                                near: statusItem?.button)
        case .excluded(let word):
            lastLearnedWord = word
            rebuildMenu()
            learningNotice.show(title: L10n.learningAddedTitle,
                                body: L10n.learningAddedBody,
                                near: statusItem?.button)
        case .disabled, .ineligible, .alreadyExcluded:
            break
        case .manualCandidate:
            break
        }
    }

    /// Remember the single typed word before an explicit Option flip. Manual flips are
    /// not automatic-correction cancellations; only a complete return to the original
    /// text can create a review candidate.
    private func rememberManualOptionConversion(from snapshot: ManualConversionSnapshot,
                                                resultingContextGeneration: UInt64) {
        guard let operationID = textConverter.lastConversionOperationID,
              let processIdentifier = snapshot.processIdentifier,
              let bundleIdentifier = snapshot.bundleIdentifier,
              let word = textConverter.lastConversionSourceToken,
              !word.isEmpty else {
            manualOptionEvidence = nil
            rslog("learn: manual Option evidence unavailable after conversion")
            return
        }
        manualOptionEvidence = ManualOptionLearningEvidence(
            operationID: operationID,
            word: word,
            processIdentifier: Int32(processIdentifier),
            bundleIdentifier: bundleIdentifier,
            inputGeneration: snapshot.inputGeneration,
            textContextGeneration: resultingContextGeneration
        )
        rslog("learn: manual Option evidence captured")
    }

    /// Count a manual Option cycle only after TextConverter confirms the original
    /// operation was restored in the same process and unchanged text context.
    private func completeManualOptionToggle(from snapshot: ManualConversionSnapshot,
                                            undoneOperationID: String?,
                                            resultingContextGeneration: UInt64) {
        guard var evidence = manualOptionEvidence,
              snapshot.inputGeneration == evidence.inputGeneration,
              keyboardMonitor.isInputGenerationCurrent(evidence.inputGeneration),
              let restoredOriginal = evidence.completeToggle(
                operationID: textConverter.lastConversionOperationID,
                undoneOperationID: undoneOperationID,
                processIdentifier: snapshot.processIdentifier,
                bundleIdentifier: snapshot.bundleIdentifier,
                inputGeneration: snapshot.inputGeneration,
                textContextGeneration: evidence.textContextGeneration,
                resultingContextGeneration: resultingContextGeneration
              ) else {
            manualOptionEvidence = nil
            rslog("learn: manual Option toggle ignored (operation or context mismatch)")
            return
        }

        if restoredOriginal {
            var outcome: LearningOutcome = .disabled
            var previousRoundTrips = 0
            var didPersist = false
            do {
                try ProfileStore.shared.update { profile in
                    let wordKey = evidence.word.precomposedStringWithCanonicalMapping.lowercased()
                    previousRoundTrips = profile.learning.first(where: {
                        $0.word.precomposedStringWithCanonicalMapping.lowercased() == wordKey
                    })?.manualRoundTripCount ?? 0
                    outcome = LearningEngine.recordManualOptionRoundTrip(word: evidence.word, in: &profile)
                }
                didPersist = true
                NotificationCenter.default.post(name: .multiSwitcherLearningDidChange, object: nil)
            } catch {
                rslog("manual learning candidate save failed: \(error.localizedDescription)")
            }

            if didPersist {
                switch outcome {
                case .manualCandidate(let roundTrips) where roundTrips >= LearningEngine.requiredManualRoundTrips
                    && previousRoundTrips < LearningEngine.requiredManualRoundTrips:
                    rslog("learn: manual Option candidate ready after \(roundTrips) round trips")
                    learningNotice.show(title: L10n.learningManualCandidateTitle,
                                        body: L10n.learningManualCandidateBody(evidence.word),
                                        near: statusItem?.button)
                case .manualCandidate(let roundTrips) where roundTrips == 1:
                    rslog("learn: manual Option round trip recorded (1/\(LearningEngine.requiredManualRoundTrips))")
                    learningNotice.show(title: L10n.learningManualProgressTitle,
                                        body: L10n.learningManualProgressBody(evidence.word),
                                        near: statusItem?.button)
                case .ineligible:
                    rslog("learn: manual Option candidate was not eligible for the review list")
                    learningNotice.show(title: L10n.learningManualNotTrackedTitle,
                                        body: L10n.learningManualNotTrackedBody,
                                        near: statusItem?.button)
                case .alreadyExcluded:
                    rslog("learn: manual Option candidate is already excluded")
                    learningNotice.show(title: L10n.learningManualAlreadyExcludedTitle,
                                        body: L10n.learningManualAlreadyExcludedBody,
                                        near: statusItem?.button)
                case .disabled:
                    rslog("learn: manual Option tracking is disabled")
                    learningNotice.show(title: L10n.learningDisabledTitle,
                                        body: L10n.learningDisabledBody,
                                        near: statusItem?.button)
                default:
                    break
                }
            }
        } else {
            rslog("learn: manual Option forward toggle confirmed; awaiting return")
        }
        manualOptionEvidence = evidence
    }

    /// Keep only the identity of the latest completed automatic correction in memory.
    /// Self-learning can use it only when the user undoes it in the same app and field.
    @discardableResult
    private func completeAutomaticConversion(word: String, snapshot: WordBoundarySnapshot,
                                             changesLayout: Bool,
                                             preservingTypedSuffixKeyCount: Int = 0) -> UInt64 {
        textConverter.reconcileLastConversionLayoutChange(changesLayout)
        let generation = keyboardMonitor.markConverted(
            boundaryInputGeneration: snapshot.inputGeneration,
            preservingTypedSuffixKeyCount: preservingTypedSuffixKeyCount
        )
        guard let operationID = textConverter.lastConversionOperationID,
              let processIdentifier = snapshot.processIdentifier,
              let bundleIdentifier = snapshot.bundleIdentifier else {
            lastAutoConverted = nil
            return generation
        }
        lastAutoConverted = LearningEvidence(
            operationID: operationID,
            word: word,
            processIdentifier: Int32(processIdentifier),
            bundleIdentifier: bundleIdentifier,
            textContextGeneration: generation
        )
        return generation
    }

    /// Correlates one private, text-free diagnostic timeline from the detector decision
    /// through the replacement outcome. The log deliberately contains no typed content.
    private func logAutomaticReplacementOutcome(
        operationID: String,
        startedAt: UInt64,
        result: String,
        layout: String,
        reason: String? = nil
    ) {
        let elapsedMilliseconds = (DispatchTime.now().uptimeNanoseconds &- startedAt) / 1_000_000
        let reasonField = reason.map { " reason=\($0)" } ?? ""
        rslog("auto: outcome op=\(operationID) result=\(result) layout=\(layout)" +
              " elapsed-ms=\(elapsedMilliseconds)\(reasonField)")
    }

    /// A correction is decided for the input source that produced the captured keys.
    /// Select that exact paired source after commit instead of flipping whatever layout
    /// happens to be current when an asynchronous replacement finishes.
    private func applyAutomaticInputLayout(
        sourceLayoutID: String?,
        targetLayoutID: String?,
        operationID: String
    ) -> AutomaticInputLayoutResult {
        let currentLayoutID = LayoutSwitcher.currentLayoutID()
        switch AutomaticLayoutTransitionPolicy.decide(
            sourceLayoutID: sourceLayoutID,
            currentLayoutID: currentLayoutID,
            targetLayoutID: targetLayoutID
        ) {
        case .keep:
            return .kept
        case .alreadyAtTarget:
            return .alreadyTarget
        case .sourceUnavailable:
            rslog("auto: input-layout op=\(operationID) result=source-unavailable")
            return .unavailable
        case .preserveUserChoice:
            rslog("auto: input-layout op=\(operationID) result=manual-choice-preserved")
            return .preservedUserChoice
        case .select(let targetID):
            let selected = LayoutSwitcher.switchTo(layoutID: targetID)
            let result: AutomaticInputLayoutResult = selected ? .switched : .unavailable
            rslog("auto: input-layout op=\(operationID) result=\(result.logValue)")
            return result
        }
    }

    /// Reconciles the private line context only after the target field confirmed its
    /// replacement. This lets subsequent decisions reason about visible words without
    /// retaining text in logs or touching a stale/changed field buffer.
    private func reconcileAutomaticVisibleText(
        snapshot: WordBoundarySnapshot,
        keyCount: Int,
        visibleWord: String? = nil,
        visibleLine: String? = nil,
        operationID: String
    ) {
        guard !snapshot.lineKeys.isEmpty else { return }
        let range: Range<Int>
        let text: String
        if let visibleLine {
            range = 0..<snapshot.lineKeys.count
            text = visibleLine
        } else if let visibleWord {
            let start = snapshot.lineKeys.count - snapshot.keys.count - snapshot.boundaryCount
            guard start >= 0, keyCount > 0 else { return }
            range = start..<(start + keyCount)
            text = visibleWord
        } else {
            return
        }
        if !keyboardMonitor.reconcileVisibleLine(snapshot: snapshot, range: range, with: text) {
            rslog("auto: context reconcile skipped op=\(operationID) reason=stale-or-length-mismatch")
        }
    }

    /// Run an Accessibility edit in the same FIFO as injected-buffer replacements.
    /// The converter rechecks the captured process, text context, and AX target before
    /// applying the word/suffix plan. State changes happen only after readback succeeds.
    @discardableResult
    private func enqueueAutomaticAXReplacement(
        operationID: String,
        startedAt: UInt64,
        snapshot: WordBoundarySnapshot,
        word: String,
        visibleKeyCount: Int,
        visibleWord: String?,
        visibleLine: String?,
        sourceLayoutID: String?,
        targetLayoutID: String?,
        label: String,
        apply: @escaping @MainActor @Sendable () -> Bool
    ) -> Bool {
        let accepted = textConverter.enqueueSerializedReplacement(
            operationID: operationID,
            processIdentifier: snapshot.processIdentifier,
            contextRejectionReason: {
                guard self.keyboardMonitor.isTextContextCurrent(snapshot.textContextGeneration) else {
                    return "text-context-changed"
                }
                let settings = SettingsManager.shared
                guard settings.autoSwitchEnabled else { return "master-disabled" }
                guard settings.autoConvert else { return "auto-conversion-disabled" }
                if AutoSwitchPolicy.areAllActionsDisabled(snapshot.bundleIdentifier) { return "app-disabled" }
                if AutoSwitchPolicy.isDeniedApp(snapshot.bundleIdentifier) { return "app-manual-only" }
                if AutoSwitchPolicy.secureInputActive { return "secure-input" }
                return nil
            },
            perform: { done in done(apply()) },
            completion: { completed in
                guard completed else {
                    self.logAutomaticReplacementOutcome(
                        operationID: operationID, startedAt: startedAt,
                        result: "cancelled-\(label)", layout: "unchanged"
                    )
                    return
                }
                self.reconcileAutomaticVisibleText(
                    snapshot: snapshot,
                    keyCount: visibleKeyCount,
                    visibleWord: visibleWord,
                    visibleLine: visibleLine,
                    operationID: operationID
                )
                let layoutResult = self.applyAutomaticInputLayout(
                    sourceLayoutID: sourceLayoutID,
                    targetLayoutID: targetLayoutID,
                    operationID: operationID
                )
                _ = self.completeAutomaticConversion(
                    word: word,
                    snapshot: snapshot,
                    changesLayout: layoutResult.changedLayout
                )
                self.updateStatusIcon()
                self.logAutomaticReplacementOutcome(
                    operationID: operationID, startedAt: startedAt,
                    result: "committed-\(label)", layout: layoutResult.logValue
                )
            }
        )
        if !accepted {
            self.logAutomaticReplacementOutcome(
                operationID: operationID, startedAt: startedAt,
                result: "refused-\(label)", layout: "unchanged"
            )
        }
        return accepted
    }

    /// Put manual Option edits through the same replacement FIFO as automatic and
    /// injected-buffer edits. A tap is accepted only for the field and input snapshot
    /// that produced it; if the user typed or moved focus while it waited, it is dropped.
    @discardableResult
    private func enqueueManualReplacement(
        snapshot: ManualConversionSnapshot,
        label: String,
        allowsManualToggleContinuation: Bool = false,
        perform: @escaping @MainActor @Sendable (@escaping @MainActor @Sendable (Bool) -> Void) -> Void,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> Bool {
        let operationID = UUID().uuidString
        let accepted = textConverter.enqueueSerializedReplacement(
            operationID: operationID,
            processIdentifier: snapshot.processIdentifier,
            contextRejectionReason: {
                let inputIsCurrent = self.keyboardMonitor.isInputGenerationCurrent(snapshot.inputGeneration)
                let contextIsCurrent = self.keyboardMonitor.isTextContextCurrent(snapshot.textContextGeneration)
                let continuesManualToggle = allowsManualToggleContinuation
                    && self.hasQueuedManualOptionContinuation(snapshot)
                guard inputIsCurrent else { return "input-generation-changed" }
                guard contextIsCurrent || continuesManualToggle else { return "text-context-changed" }
                guard SettingsManager.shared.autoSwitchEnabled else { return "master-disabled" }
                if AutoSwitchPolicy.areAllActionsDisabled(snapshot.bundleIdentifier) { return "app-disabled" }
                if AutoSwitchPolicy.secureInputActive { return "secure-input" }
                return nil
            },
            perform: perform,
            completion: completion
        )
        if !accepted {
            rslog("trigger: queued manual replacement refused op=\(operationID) " +
                  "label=\(label) reason=queue-full")
        }
        return accepted
    }

    private func hasQueuedManualOptionContinuation(_ snapshot: ManualConversionSnapshot) -> Bool {
        guard let evidence = manualOptionEvidence,
              let currentProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let currentBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return evidence.matchesQueuedToggle(
            snapshotInputGeneration: snapshot.inputGeneration,
            snapshotTextContextGeneration: snapshot.textContextGeneration,
            currentInputGeneration: keyboardMonitor.currentInputGeneration,
            currentTextContextGeneration: keyboardMonitor.currentTextContextGeneration,
            processIdentifier: currentProcessID,
            bundleIdentifier: currentBundleID,
            operationID: textConverter.lastConversionOperationID
        ) && snapshot.processIdentifier == currentProcessID
            && snapshot.bundleIdentifier == currentBundleID
    }

    private func startPerAppLayout() {
        perAppLayoutManager.onLayoutRestored = { [weak self] in
            self?.keyboardMonitor.markConverted()
            self?.textConverter.clearState()
            self?.updateStatusIcon()
        }
        perAppLayoutManager.start()
    }

    // MARK: - Login Item Sync

    /// Синхронизирует состояние автозагрузки с системой при старте.
    /// Если галочка включена, но Login Item потерян (переустановка/обновление) — перерегистрирует.
    /// Если галочка выключена, но Login Item есть — снимает.
    private func syncLoginItem() {
        guard MultiAuditEnvironment.root == nil else { return }
        let settings = SettingsManager.shared
        let wanted = settings.launchAtLogin
        let status = settings.loginItemStatus

        rslog("Login item sync: wanted=\(wanted) status=\(status.rawValue)")

        if wanted && status != .enabled {
            // Галочка стоит, но Login Item не активен — перерегистрируем
            rslog("Re-registering login item...")
            settings.launchAtLogin = true  // setter вызовет doUpdateLoginItem
        } else if !wanted && status == .enabled {
            // Галочка снята, но Login Item активен — убираем
            rslog("Unregistering stale login item...")
            settings.launchAtLogin = false
        }
    }

    // MARK: - Permission Wizard

    private func runPermissionWizard(interactive: Bool = false) {
        let acc = AXIsProcessTrusted()
        let inp = CGPreflightListenEventAccess()
        rslog("Permissions: accessibility=\(acc) inputMonitoring=\(inp)")
        settingsController.updatePermissionStatus(accessibility: acc, inputMonitoring: inp)

        if acc && inp {
            // Запоминаем что разрешения были даны
            SettingsManager.shared.permissionsWereGranted = true
            if !monitoringActive && !SettingsManager.shared.isPaused { startMonitoring() }
            // Ручная проверка из меню должна давать видимый отклик.
            if interactive { showPermissionsGuide(accessibilityGranted: acc, inputMonitoringGranted: inp) }
            return
        }

        if monitoringActive {
            keyboardMonitor.stop()
            monitoringActive = false
            configureIconRefreshFallback()
            perAppLayoutManager.stop()
            caretIndicator?.teardown()
            caretIndicator = nil
        }

        // A previous grant was lost (for example, after replacing an unsigned build).
        // Explain the current state without resetting or requesting TCC permissions.
        let hadPermissionsBefore = SettingsManager.shared.permissionsWereGranted
        if hadPermissionsBefore {
            rslog("Permissions were previously granted — reset detected after update")
            SettingsManager.shared.permissionsWereGranted = false
        }

        // Do not interrupt a first launch with a modal permissions request. Keep the
        // app and settings usable, show the missing state inline/in the menu, and only
        // present the guide after the user explicitly chooses Check Permissions.
        guard interactive else {
            rebuildMenu()
            return
        }
        showPermissionsGuide(accessibilityGranted: acc, inputMonitoringGranted: inp)
    }

    @objc private func showHelp() {
        if helpController == nil {
            helpController = HelpWindowController(openSettings: { [weak self] in self?.openSettings() })
        }
        helpController?.present()
        if let directory = ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let window = self?.helpController?.window else { return }
                let theme = DesignTheme.shared.preference == .dark ? "dark" : "light"
                SettingsWindowController.captureWindow(window, to: directory + "/\(theme)-help.png")
                window.orderOut(nil)
            }
        }
    }

    private func prepareAlertReview(_ alert: NSAlert, name: String) {
        guard let directory = ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] else { return }
        let theme = DesignTheme.shared.preference == .dark ? "dark" : "light"
        let timer = Timer(timeInterval: 0.4, repeats: false) { _ in
            MainActor.assumeIsolated {
                SettingsWindowController.captureWindow(alert.window, to: directory + "/\(theme)-\(name).png")
                NSApp.abortModal()
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
    }

    /// Isolated review exercises navigation, live grants and revocation; it never
    /// opens System Settings or claims a real TCC permission was granted.
    private func reviewPermissionsGuide(to directory: String) {
        var simulated = PermissionsGuideWindowController.Status(accessibility: false, inputMonitoring: false)
        var finishCount = 0
        let guide = PermissionsGuideWindowController(readStatus: { simulated }, openSettings: { _ in }, onStatus: { _ in }, onFinish: { finishCount += 1 })
        permissionsGuide = guide
        guide.present()
        guide.select(2); guide.advance()
        precondition(finishCount == 0, "missing permissions cannot finish")
        guide.select(-10); precondition(guide.step == 0)
        guide.select(10); precondition(guide.step == 2)
        let cases: [(String, Int, Bool, Bool)] = [
            ("text", 0, false, false), ("keyboard", 1, false, false),
            ("check-missing", 2, false, false), ("text-granted", 0, true, false),
            ("ready", 2, true, true), ("revoked", 2, false, true), ("repair", 0, false, false),
        ]
        @MainActor func capture(_ index: Int) {
            guard index < cases.count * 2 else {
                simulated = .init(accessibility: true, inputMonitoring: true)
                guide.refresh(); guide.select(2); guide.advance()
                precondition(finishCount == 1, "finish requires both permissions")
                guide.window?.close()
                let result: [String: Any] = ["states": cases.count * 2, "navigationBounds": true, "missingCannotFinish": true, "grantAndRevocation": true, "readyCanFinish": finishCount == 1, "realPermissionsChanged": false]
                try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: directory + "/checks.json"))
                NSApp.terminate(nil); return
            }
            let item = cases[index % cases.count]
            let dark = index >= cases.count
            DesignTheme.shared.preference = dark ? .dark : .light
            simulated = .init(accessibility: item.2, inputMonitoring: item.3)
            guide.refresh(); guide.select(item.1)
            if item.0 == "repair" { guide.showTroubleshooting() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if let window = guide.window {
                    MultiEcosystemProbe.capture(window, path: directory + "/" + (dark ? "dark-" : "light-") + item.0 + ".png")
                }
                capture(index + 1)
            }
        }
        capture(0)
    }

    /// Step-by-step guidance stays visible while the user changes macOS settings.
    private func showPermissionsGuide(accessibilityGranted: Bool, inputMonitoringGranted: Bool) {
        if permissionsGuide == nil {
            permissionsGuide = PermissionsGuideWindowController(
                readStatus: { .init(accessibility: AXIsProcessTrusted(), inputMonitoring: CGPreflightListenEventAccess()) },
                openSettings: { [weak self] pane in self?.openPrivacySettings(pane: pane) },
                onStatus: { [weak self] status in
                    guard let self else { return }
                    self.settingsController.updatePermissionStatus(accessibility: status.accessibility, inputMonitoring: status.inputMonitoring)
                    SettingsManager.shared.permissionsWereGranted = status.ready
                    self.runPermissionWizard()
                    self.updateStatusIcon()
                    self.rebuildMenu()
                },
                onFinish: { [weak self] in
                    SettingsManager.shared.autoConvert = true
                    SettingsManager.shared.autoSwitchEnabled = true
                    SettingsManager.shared.isPaused = false
                    self?.restartApp()
                }, onRestartCheck: { AppRelauncher.relaunch(arguments: ["--permissions-guide"]) },
                onVisibilityChanged: { [weak self] isVisible in
                    guard let self else { return }
                    NSApp.setActivationPolicy(isVisible || self.settingsWindowVisible ? .regular : .accessory)
                })
        }
        permissionsGuide?.present()
    }

    /// Open the specific Privacy & Security pane. If the deep link is unavailable on this
    /// macOS release, open System Settings and keep the exact manual path in the alert.
    private func openPrivacySettings(pane: String) {
        // This path is entered only by an explicit guide button. Preflight checks
        // and opening Settings alone do not register the current signing identity
        // when TCC still contains a CDHash-bound grant from an older local build.
        // Ask macOS to handle consent for this exact app; never edit/reset TCC.
        switch pane {
        case "Privacy_Accessibility":
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            let granted = AXIsProcessTrustedWithOptions(options)
            rslog("Permission request: accessibility=\(granted)")
        case "Privacy_ListenEvent":
            let granted = CGRequestListenEventAccess()
            rslog("Permission request: inputMonitoring=\(granted)")
        default:
            return
        }
        // Newer System Settings uses the extension bundle identifier; older macOS
        // releases still resolve the original preference-pane identifier.
        let destinations = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)",
            "x-apple.systempreferences:com.apple.preference.security?\(pane)",
        ]
        for destination in destinations {
            guard let url = URL(string: destination) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
        let settingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        _ = NSWorkspace.shared.open(settingsURL)
    }

    private func restartApp() {
        rslog("Restarting from: \(Bundle.main.bundlePath)")
        AppRelauncher.relaunch()
    }

    // MARK: - Start Monitoring

    private func startMonitoring() {
        guard !SettingsManager.shared.isPaused else { return }
        guard !monitoringActive else { return }
        guard !monitoringStartPending else { return }
        let accessibilityGranted = AXIsProcessTrusted()
        let inputMonitoringGranted = CGPreflightListenEventAccess()
        settingsController.updatePermissionStatus(accessibility: accessibilityGranted,
                                                   inputMonitoring: inputMonitoringGranted)
        guard accessibilityGranted && inputMonitoringGranted else {
            rslog("Monitoring start skipped: macOS permissions are not both enabled")
            return
        }
        guard Dict.automaticLexiconsReady else {
            monitoringStartPending = true
            Dict.prepareAutomaticLexicons { [weak self] in
                guard let self else { return }
                self.monitoringStartPending = false
                self.startMonitoring()
            }
            return
        }
        let settings = SettingsManager.shared
        guard settings.automaticRulesReady else {
            monitoringStartPending = true
            settings.prepareAutomaticRules { [weak self] count in
                guard let self else { return }
                rslog("rules: automatic snapshot ready count=\(count)")
                self.monitoringStartPending = false
                self.startMonitoring()
            }
            return
        }

        if !keyboardMonitor.start(
            onAltTap: { [weak self] snapshot in
                guard let self else { return }
                // This callback handles a new conversion; only the separate repeat-
                // toggle callback can complete evidence from the previous conversion.
                // Drop stale evidence when the user starts converting different text.
                self.manualOptionEvidence = nil
                guard self.keyboardMonitor.isInputGenerationCurrent(snapshot.inputGeneration),
                      self.keyboardMonitor.isTextContextCurrent(snapshot.textContextGeneration) else {
                    rslog("trigger: stale input snapshot; conversion cancelled")
                    return
                }
                guard snapshot.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier else {
                    rslog("trigger: focused application changed; conversion cancelled")
                    return
                }
                guard SettingsManager.shared.autoSwitchEnabled else { return }
                guard !AutoSwitchPolicy.areAllActionsDisabled(snapshot.bundleIdentifier) else { return }
                // Приватность: в защищённом поле (пароль) ничего не делаем — ставим ДО
                // remote-defer, чтобы поведение точно совпадало с handleAutoConvert.
                guard !AutoSwitchPolicy.secureInputActive else { rslog("trigger: bail secure-input"); self.notifySecureInputPaused(); return }
                if AutoSwitchPolicy.shouldDeferToRemoteClient {
                    // Удалёнка: текст конвертит офисный инстанс по реальным проброшенным символам
                    // (Fix №6). А здесь меняем СВОЮ раскладку — чтобы дальнейший ввод пошёл уже
                    // в правильной раскладке и не пришлось конвертить каждое слово.
                    LayoutSwitcher.switchToOpposite()
                    self.updateStatusIcon()
                    rslog("trigger: local layout switched, conversion handled by controlled instance")
                    return
                }
                // Spotlight меняет значение активного AX-поля напрямую и проверяет
                // целевой элемент/содержимое перед записью. При неопределённости ниже
                // запрещается любой резервный Backspace/count-путь.
                switch SpotlightAX.inspect() {
                case .active(let field):
                    let targetProcessID = field.processID
                    let targetIdentity = field.identity
                    _ = self.enqueueManualReplacement(
                        snapshot: snapshot,
                        label: "Spotlight Option",
                        perform: { done in
                            done(self.textConverter.convertSpotlight(
                                expectedProcessID: targetProcessID,
                                expectedIdentity: targetIdentity
                            ))
                        },
                        completion: { converted in
                            guard converted else { return }
                            let generation = self.keyboardMonitor.markConverted(boundaryInputGeneration: snapshot.inputGeneration)
                            if self.textConverter.lastConversionChangesLayout { LayoutSwitcher.switchToOpposite() }
                            self.updateStatusIcon()
                            self.lastAutoConverted = nil
                            self.rememberManualOptionConversion(from: snapshot,
                                                                resultingContextGeneration: generation)
                        }
                    )
                    return
                case .uncertain:
                    rslog("trigger: Spotlight may own focus; refusing Backspace fallback")
                    return
                case .inactive:
                    break
                }
                switch SafariAddressBarAX.inspect() {
                case .active(let field):
                    let targetProcessID = field.processID
                    let targetIdentity = field.identity
                    _ = self.enqueueManualReplacement(
                        snapshot: snapshot,
                        label: "Safari address bar Option",
                        perform: { done in
                            done(self.textConverter.convertSafariAddressBar(
                                expectedProcessID: targetProcessID,
                                expectedIdentity: targetIdentity
                            ))
                        },
                        completion: { converted in
                            guard converted else { return }
                            let generation = self.keyboardMonitor.markConverted(boundaryInputGeneration: snapshot.inputGeneration)
                            if self.textConverter.lastConversionChangesLayout { LayoutSwitcher.switchToOpposite() }
                            self.updateStatusIcon()
                            self.lastAutoConverted = nil
                            self.rememberManualOptionConversion(from: snapshot,
                                                                resultingContextGeneration: generation)
                        }
                    )
                    return
                case .uncertain:
                    rslog("trigger: Safari address field uncertain; refusing Backspace fallback")
                    return
                case .inactive:
                    break
                }
                // issue #24: режим «вся строка».
                if SettingsManager.shared.convertWholeLine {
                    let frontID = snapshot.bundleIdentifier
                    if AutoSwitchPolicy.isTerminalApp(frontID) {
                        // Терминал: нет OS-выделения → перепечатываем строку по буферу нажатий.
                        // НЕПУСТОЙ буфер (в т.ч. no-op на уже верной строке) завершаем ЗДЕСЬ и НЕ
                        // проваливаемся на последнее слово — иначе безусловный флип испортил бы
                        // верное слово, напр. «git log»→«git дщп» (скептик 3.2.0). На слово падаем
                        // только при ПУСТОМ/сброшенном буфере (пунктуация/Enter/сдвиг курсора).
                        if !snapshot.lineKeys.isEmpty {
                            self.lastAutoConverted = nil
                            _ = self.textConverter.convertLineBuffer(
                                snapshot.lineKeys,
                                performIfCurrent: { operation in
                                    self.keyboardMonitor.performIfInputGenerationIsCurrent(snapshot.inputGeneration, operation: operation)
                                },
                                completion: { completed in
                                    guard completed else { rslog("trigger: terminal line replacement cancelled") ; return }
                                    self.keyboardMonitor.markConverted(boundaryInputGeneration: snapshot.inputGeneration)
                                    LayoutSwitcher.switchToOpposite()
                                    self.updateStatusIcon()
                                }
                            )
                            return
                        }
                    } else {
                        // Обычные приложения: сами выделяем строку (Shift+Cmd+←) и конвертируем.
                        _ = self.enqueueManualReplacement(
                            snapshot: snapshot,
                            label: "whole-line Option",
                            perform: { done in done(self.textConverter.convertLine()) },
                            completion: { converted in
                                guard converted else { return }
                                self.keyboardMonitor.markConverted()
                                LayoutSwitcher.switchToOpposite()
                                self.updateStatusIcon()
                                self.lastAutoConverted = nil
                            }
                        )
                        return   // whole-line в обычной проге — всегда завершаем (не last-word)
                    }
                }
                self.lastAutoConverted = nil
                _ = self.enqueueManualReplacement(
                    snapshot: snapshot,
                    label: "word Option",
                    perform: { done in
                        _ = self.textConverter.convert(
                            wordKeys: snapshot.currentWordKeys,
                            prevWordKeys: snapshot.previousWordKeys,
                            boundaryCount: snapshot.boundaryCount,
                            performIfCurrent: { operation in
                                self.keyboardMonitor.performIfInputGenerationIsCurrent(snapshot.inputGeneration, operation: operation)
                            },
                            completion: done
                        )
                    },
                    completion: { completed in
                        guard completed else {
                            rslog("trigger: buffered replacement cancelled before text changed")
                            return
                        }
                        let generation = self.keyboardMonitor.markConverted(boundaryInputGeneration: snapshot.inputGeneration)
                        if self.textConverter.lastConversionChangesLayout { LayoutSwitcher.switchToOpposite() }
                        self.updateStatusIcon()
                        self.rememberManualOptionConversion(from: snapshot,
                                                            resultingContextGeneration: generation)
                    }
                )
            },
            onAltReconvert: { [weak self] snapshot in
                guard let self else { return }
                guard self.keyboardMonitor.isInputGenerationCurrent(snapshot.inputGeneration),
                      self.keyboardMonitor.isTextContextCurrent(snapshot.textContextGeneration) else {
                    rslog("reconvert: stale input snapshot; undo cancelled")
                    return
                }
                guard snapshot.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier else {
                    rslog("reconvert: focused application changed; undo cancelled")
                    return
                }
                guard SettingsManager.shared.autoSwitchEnabled else { return }
                guard !AutoSwitchPolicy.areAllActionsDisabled(snapshot.bundleIdentifier) else { return }
                guard !AutoSwitchPolicy.secureInputActive else { rslog("reconvert: bail secure-input"); self.notifySecureInputPaused(); return }
                if AutoSwitchPolicy.shouldDeferToRemoteClient {
                    // Удалёнка: текст конвертит офисный инстанс по реальным проброшенным символам
                    // (Fix №6). А здесь меняем СВОЮ раскладку — чтобы дальнейший ввод пошёл уже
                    // в правильной раскладке и не пришлось конвертить каждое слово.
                    LayoutSwitcher.switchToOpposite()
                    self.updateStatusIcon()
                    rslog("trigger: local layout switched, conversion handled by controlled instance")
                    return
                }
                // Spotlight использует сохранённую транзакцию исходного значения и
                // точный AX target; обычная реконвертация по счётчику здесь запрещена.
                switch SpotlightAX.inspect() {
                case .active(let field):
                    let targetProcessID = field.processID
                    let targetIdentity = field.identity
                    _ = self.enqueueManualReplacement(
                        snapshot: snapshot,
                        label: "Spotlight Option undo",
                        allowsManualToggleContinuation: true,
                        perform: { done in
                            done(self.textConverter.convertSpotlight(
                                expectedProcessID: targetProcessID,
                                expectedIdentity: targetIdentity
                            ))
                        },
                        completion: { converted in
                            guard converted else {
                                self.lastAutoConverted = nil
                                self.manualOptionEvidence = nil
                                return
                            }
                            let generation = self.keyboardMonitor.markConverted(boundaryInputGeneration: snapshot.inputGeneration)
                            if self.textConverter.lastConversionChangesLayout { LayoutSwitcher.switchToOpposite() }
                            self.updateStatusIcon()
                            self.offerExceptionAfterUndo(snapshot, operationID: self.textConverter.lastUndoneOperationID)
                            self.completeManualOptionToggle(from: snapshot,
                                                            undoneOperationID: self.textConverter.lastUndoneOperationID,
                                                            resultingContextGeneration: generation)
                        }
                    )
                    return
                case .uncertain:
                    rslog("reconvert: Spotlight may own focus; refusing Backspace fallback")
                    return
                case .inactive:
                    break
                }
                switch SafariAddressBarAX.inspect() {
                case .active(let field):
                    let targetProcessID = field.processID
                    let targetIdentity = field.identity
                    _ = self.enqueueManualReplacement(
                        snapshot: snapshot,
                        label: "Safari address bar Option undo",
                        allowsManualToggleContinuation: true,
                        perform: { done in
                            done(self.textConverter.convertSafariAddressBar(
                                expectedProcessID: targetProcessID,
                                expectedIdentity: targetIdentity
                            ))
                        },
                        completion: { converted in
                            guard converted else {
                                self.lastAutoConverted = nil
                                self.manualOptionEvidence = nil
                                return
                            }
                            let generation = self.keyboardMonitor.markConverted(boundaryInputGeneration: snapshot.inputGeneration)
                            if self.textConverter.lastConversionChangesLayout { LayoutSwitcher.switchToOpposite() }
                            self.updateStatusIcon()
                            self.offerExceptionAfterUndo(snapshot, operationID: self.textConverter.lastUndoneOperationID)
                            self.completeManualOptionToggle(from: snapshot,
                                                            undoneOperationID: self.textConverter.lastUndoneOperationID,
                                                            resultingContextGeneration: generation)
                        }
                    )
                    return
                case .uncertain:
                    rslog("reconvert: Safari address field uncertain; refusing Backspace fallback")
                    return
                case .inactive:
                    break
                }
                _ = self.enqueueManualReplacement(
                    snapshot: snapshot,
                    label: "word Option undo",
                    allowsManualToggleContinuation: true,
                    perform: { done in
                        _ = self.textConverter.reconvert(
                            performIfCurrent: { operation in
                                self.keyboardMonitor.performIfInputGenerationIsCurrent(snapshot.inputGeneration, operation: operation)
                            },
                            completion: done
                        )
                    },
                    completion: { completed in
                        guard completed else {
                            rslog("reconvert: stale replacement cancelled")
                            self.lastAutoConverted = nil
                            self.manualOptionEvidence = nil
                            return
                        }
                        let generation = self.keyboardMonitor.markConverted(boundaryInputGeneration: snapshot.inputGeneration)
                        if self.textConverter.lastConversionChangesLayout { LayoutSwitcher.switchToOpposite() }
                        self.updateStatusIcon()
                        self.offerExceptionAfterUndo(snapshot, operationID: self.textConverter.lastUndoneOperationID)
                        self.completeManualOptionToggle(from: snapshot,
                                                        undoneOperationID: self.textConverter.lastUndoneOperationID,
                                                        resultingContextGeneration: generation)
                    }
                )
            }
        ) {
            rslog("Event tap failed - will retry in 5s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.startMonitoring()
            }
            return
        }

        monitoringActive = true
        keyboardMonitor.onWordBoundary = { [weak self] snapshot in
            self?.handleAutoConvert(snapshot)
        }
        keyboardMonitor.onUserInput = { [weak self] in
            guard let self,
                  !AutoSwitchPolicy.areAllActionsDisabled(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else { return }
            self.caretIndicator?.userTyped()
        }  // issue #10
        // issue #14: хоткей чистого переключения раскладки (без конверсии). Буфер после
        // явной смены раскладки неактуален — тот же паттерн, что per-app restore и меню.
        keyboardMonitor.onSwitchHotkey = { [weak self] in
            guard let self, SettingsManager.shared.autoSwitchEnabled else { return }
            guard !AutoSwitchPolicy.areAllActionsDisabled(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else { return }
            if AutoSwitchPolicy.shouldDeferToRemoteClient {
                // Удалёнка (фокус в клиенте Screen Sharing): переключаем только СВОЮ
                // раскладку, как defer-ветка триггера. markConverted/clearState тут лишние —
                // буфер наполняется через handleForwardedChar, а проброшенные модификаторы
                // сами переключат раскладку на контролируемой машине.
                LayoutSwitcher.switchToOpposite()
                self.updateStatusIcon()
                rslog("switch hotkey: local layout switched (remote client focused)")
                return
            }
            LayoutSwitcher.switchToOpposite()
            self.keyboardMonitor.markConverted()
            self.textConverter.clearState()
            self.updateStatusIcon()
        }
        // issue #29: хоткей смены регистра последнего слова / выделения. Раскладку не трогает,
        // в защищённом поле — пас (приватность), как у триггера.
        keyboardMonitor.onCaseHotkey = { [weak self] in
            guard let self else { return }
            guard !AutoSwitchPolicy.areAllActionsDisabled(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else { return }
            guard !AutoSwitchPolicy.secureInputActive else { rslog("case: bail secure-input"); self.notifySecureInputPaused(); return }
            // Скептик #29: те же гейты, что у onAltTap/onSwitchHotkey. Удалёнка — текст правит
            // контролируемый инстанс (у нас нет своей раскладки для флипа, регистр просто пропускаем).
            if AutoSwitchPolicy.shouldDeferToRemoteClient { rslog("case: bail remote-defer"); return }
            // Spotlight: count-путь оставил бы лишнюю букву (issue #16), а AX там флейкует — не трогаем.
            switch SpotlightAX.inspect() {
            case .active, .uncertain:
                rslog("case: Spotlight focus unavailable for safe case change")
                return
            case .inactive:
                break
            }
            // issue #29: смена регистра зеркалит триггер конверсии — уважает «Convert whole line»
            // (запрос kobygold). Терминал → по буферу строки; обычное приложение → AX-выделение строки.
            if SettingsManager.shared.convertWholeLine {
                let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                if AutoSwitchPolicy.isTerminalApp(frontID) {
                    if !self.keyboardMonitor.lineKeys.isEmpty {
                        if self.textConverter.changeCaseLineBuffer(self.keyboardMonitor.lineKeys) { self.textConverter.clearState() }
                        return   // непустой буфер строки — завершаем здесь (как onAltTap)
                    }
                    // пустой буфер → падаем на последнее слово ниже
                } else {
                    if self.textConverter.changeCaseLine() { self.textConverter.clearState() }
                    return   // обычное приложение, whole-line — всегда завершаем здесь
                }
            }
            // Скептик #29: НЕ markConverted() — буфер слова нужен, чтобы повторный тап циклил
            // регистр. Чистим reconvert-состояние, иначе следующий реконверт сработал бы по
            // устаревшим lastOriginal/lastConverted и испортил текст.
            let keys = self.keyboardMonitor.currentWordKeys
            if self.textConverter.changeCase(wordKeys: keys) {
                self.textConverter.clearState()
            }
        }
        updateStatusIcon()        // сначала выставляем флаг меню-бара, пока индикатора ещё нет
        syncCaretIndicator()      // затем создаём индикатор — без стартового ложного «попа»
        configureIconRefreshFallback()
        rslog("Monitoring started successfully")

        if SettingsManager.shared.perAppLayout {
            startPerAppLayout()
        }

        // Предлагаем автозагрузку и автозамену при первом запуске (по разу)
        offerLaunchAtLoginIfNeeded()
        offerAutoConvertIfNeeded()
    }

    /// Авто-конвертация на границе слова: детект неправильной раскладки → конверт + смена.
    /// Точность-first: при любой неуверенности ничего не делаем. Ручной триггер не трогаем.
    private func handleAutoConvert(_ snapshot: WordBoundarySnapshot) {
        let replacementOperationID = UUID().uuidString
        let replacementStartedAt = DispatchTime.now().uptimeNanoseconds
        func bail(_ reason: String) {
            logAutomaticReplacementOutcome(
                operationID: replacementOperationID,
                startedAt: replacementStartedAt,
                result: "skipped",
                layout: "unchanged",
                reason: reason
            )
        }

        rslog("auto: fired op=\(replacementOperationID)")
        guard SettingsManager.shared.autoSwitchEnabled else { bail("master-off"); return }
        guard SettingsManager.shared.autoConvert else { bail("auto-convert-off"); return }
        guard !AutoSwitchPolicy.secureInputActive else { bail("secure-input"); return }
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard !AutoSwitchPolicy.areAllActionsDisabled(frontID) else { bail("all-actions-app"); return }
        // Удалёнка: НЕ выходим сразу — прогоняем детектор по своему (чистому) буферу, и при
        // «не той раскладке» переключаем СВОЮ раскладку (конверсию делает инстанс на той стороне).
        let deferToRemote = SettingsManager.shared.remoteDesktopMode && AutoSwitchPolicy.isRemoteDesktopClient(frontID)
        if AutoSwitchPolicy.isDeniedApp(frontID) { bail("denied-app"); return }
        if let capturedPID = snapshot.processIdentifier,
           capturedPID != NSWorkspace.shared.frontmostApplication?.processIdentifier {
            bail("process-changed"); return
        }
        if let captured = snapshot.bundleIdentifier, captured != frontID {
            bail("focus-changed"); return  // фокус уехал между пробелом и сейчас
        }

        let allKeys = snapshot.keys
        let bc = snapshot.boundaryCount
        guard !allKeys.isEmpty else { bail("empty-keys"); return }  // курсор уехал — небезопасно
        guard let fullPair = DynamicKeyMapping.convertKeys(allKeys) else { bail("key-conversion-unavailable"); return }

        // issue #15: слово с прилипшей пунктуацией ("ghbdtn,") — отщепляем хвост, детектим
        // и конвертим ядро, хвост вернётся в поле литералом. Проверка счёта — инвариант
        // «1 клавиша = 1 символ» обоих путей convertKeys; при слиянии графем не отщепляем.
        var keys = allKeys
        var suffix = ""
        let split = LayoutDetector.splitTrailingPunctuation(fullPair.original)
        if !split.suffix.isEmpty, split.coreLength > 0, fullPair.original.count == allKeys.count {
            keys = Array(allKeys.prefix(split.coreLength))
            suffix = split.suffix
        }
        guard let pair = suffix.isEmpty ? fullPair : DynamicKeyMapping.convertKeys(keys) else {
            bail("key-conversion-unavailable"); return
        }

        // Язык для детектора. Для проброшенного через удалёнку текста (все символы — char)
        // направление определяем по СКРИПТУ набранного, а не по раскладке офисной машины:
        // на офисе раскладка может не соответствовать тому, что напечатали на контроллере,
        // и тогда decide ошибочно даёт keep (это и есть «авто в удалёнке не работает»).
        let langs: (current: String, opposite: String)
        let settings = SettingsManager.shared
        let layouts = LayoutSwitcher.installedLayouts()
        let layout1ID = settings.layout1ID.isEmpty ? LayoutSwitcher.autoDetectID1(from: layouts) : settings.layout1ID
        let layout2ID = settings.layout2ID.isEmpty ? LayoutSwitcher.autoDetectID2(from: layouts) : settings.layout2ID
        func configuredLayoutID(for language: String) -> String? {
            let wanted = String(language.prefix(2)).lowercased()
            return [layout1ID, layout2ID].first { id in
                guard let source = layouts.first(where: { LayoutSwitcher.sourceID($0) == id }),
                      let code = LayoutSwitcher.languageCode(source) else { return false }
                return String(code.prefix(2)).lowercased() == wanted
            }
        }
        var capturedSourceLayoutID: String?
        var oppositeLayoutIDAtBoundary: String?
        if let sourceID = keys.reversed().compactMap(\.sourceLayoutID).first,
           let source = layouts.first(where: { LayoutSwitcher.sourceID($0) == sourceID }),
           let sourceLanguage = LayoutSwitcher.languageCode(source) {
            let targetID = sourceID == layout1ID ? layout2ID : sourceID == layout2ID ? layout1ID : nil
            guard let targetID,
                  let target = layouts.first(where: { LayoutSwitcher.sourceID($0) == targetID }),
                  let targetLanguage = LayoutSwitcher.languageCode(target) else {
                bail("captured-layout-not-paired"); return
            }
            langs = (String(sourceLanguage.prefix(2)), String(targetLanguage.prefix(2)))
            capturedSourceLayoutID = sourceID
            oppositeLayoutIDAtBoundary = targetID
        } else if keys.allSatisfy({ $0.char != nil }) {
            let typedIsCyrillic = pair.original.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }
            langs = typedIsCyrillic ? ("ru", "en") : ("en", "ru")
            capturedSourceLayoutID = LayoutSwitcher.currentLayoutID()
            oppositeLayoutIDAtBoundary = configuredLayoutID(for: langs.opposite)
        } else if let l = LayoutSwitcher.currentAndOppositeLanguage() {
            langs = l
            capturedSourceLayoutID = LayoutSwitcher.currentLayoutID()
            oppositeLayoutIDAtBoundary = configuredLayoutID(for: langs.opposite)
        } else {
            bail("language-pair-unavailable"); return
        }
        let currentLayoutIDAtBoundary = LayoutSwitcher.currentLayoutID()
        let sourceLayoutIDAtBoundary = capturedSourceLayoutID
            ?? (currentLayoutIDAtBoundary.isEmpty
                ? configuredLayoutID(for: langs.current)
                : currentLayoutIDAtBoundary)
        // The source recorded on each key is the layout that actually generated the
        // token. A live TIS query here can observe a later switch while the boundary
        // request is queued and invert the language-transition decision.
        let activeLanguageAtBoundary = langs.current
        if SettingsManager.shared.debugLogEnabled {
            func slot(_ id: String?) -> String {
                guard let id, !id.isEmpty else { return "unknown" }
                if id == layout1ID { return "layout-1" }
                if id == layout2ID { return "layout-2" }
                return "other" // Never persist a custom input-source identifier.
            }
            let evidence = keys.allSatisfy { $0.char != nil }
                ? "typed-script"
                : (keys.contains { $0.sourceLayoutID != nil } ? "per-key-source" : "boundary-source")
            let aligned = currentLayoutIDAtBoundary.isEmpty || sourceLayoutIDAtBoundary == currentLayoutIDAtBoundary
            rslog("auto: layout-state op=\(replacementOperationID) evidence=\(evidence) " +
                  "source=\(slot(sourceLayoutIDAtBoundary)) live=\(slot(currentLayoutIDAtBoundary)) " +
                  "aligned=\(aligned) pair=\(langs.current)/\(langs.opposite)")
        }

        guard let ruleEvaluator = settings.preparedAutomaticRuleEvaluator() else {
            settings.prepareAutomaticRules()
            bail("rules-not-ready")
            return
        }
        let initialRuleDecision = ruleEvaluator.decision(typed: pair.original, converted: pair.converted)
        if initialRuleDecision == .neverConvert {
            bail("never-convert-rule")
            return
        }

        let mixedCandidate: LayoutCorrectionEngine.Candidate?
        if LayoutCorrectionEngine.isMixedScript(pair.original),
           Dict.isAvailable(langs.current), Dict.isAvailable(langs.opposite),
           let currentCandidate = DynamicKeyMapping.convertMixedScript(pair.original, towardLang: langs.current),
           let oppositeCandidate = DynamicKeyMapping.convertMixedScript(pair.original, towardLang: langs.opposite) {
            if let selected = LayoutCorrectionEngine.uniqueMixedCandidate(
                typed: pair.original,
                currentLanguage: langs.current,
                oppositeLanguage: langs.opposite,
                currentCandidate: currentCandidate,
                oppositeCandidate: oppositeCandidate,
                isValidWord: { text, language in
                    let word = text.filter(\.isLetter).lowercased()
                    return word.count >= 2 && Dict.isValidWordForAutomaticPath(word, lang: language)
                }
            ) {
                mixedCandidate = LayoutCorrectionEngine.Candidate(
                    text: selected.text,
                    language: selected.language,
                    changesLayout: selected.language != activeLanguageAtBoundary
                )
            } else {
                mixedCandidate = nil
            }
        } else {
            mixedCandidate = nil
        }

        var targetWord = mixedCandidate?.text ?? pair.converted
        var changesLayout = mixedCandidate?.changesLayout ?? (langs.opposite != activeLanguageAtBoundary)
        let ruleDecision: ProfileRuleDecision
        if mixedCandidate != nil {
            ruleDecision = initialRuleDecision == .none
                ? ruleEvaluator.decision(typed: pair.original, converted: targetWord)
                : initialRuleDecision
        } else {
            ruleDecision = initialRuleDecision
        }
        if ruleDecision == .neverConvert { bail("never-convert-rule"); return }
        if case .replace(let value) = ruleDecision {
            targetWord = value
            changesLayout = false
        }

        // Ревью-находка (#15): '.', ',', ';', ':' в EN — клавиши букв ю/б/ж/Ж в ЙЦУКЕН,
        // поэтому начало «хвоста» в целевой раскладке может оказаться буквами, а ядро +
        // эти буквы — словарным словом: «levf.» → «думаю», «levf.!» → «думаю!». Идём по
        // буквенному расширению ядра в полной конверсии и проверяем каждый префикс по
        // словарю: первое словарное расширение = неоднозначность («думаю» vs «дума.») →
        // точность важнее полноты, не делаем НИЧЕГО (ручной триггер конвертирует целиком).
        // Первая не-буква — стоп: дальше хвост пунктуация и в целевой раскладке,
        // двусмысленности нет. NSSpellChecker токенизирует («привет!» для него валиден),
        // поэтому проверять полную конверсию целиком нельзя — только буквенные префиксы.
        // Для пар с ивритом walk не нужен: направление «в иврит» авто-путём не конвертится
        // by design (см. иврит-ветку decide), а ивритский словарь принимает любые буквы —
        // walk дал бы бессмысленный bail на первом же шаге и мусорную строку в логе.
        if mixedCandidate == nil, !suffix.isEmpty, !LayoutDetector.isHebrew(langs.opposite), Dict.isAvailable(langs.opposite) {
            let oth = String(langs.opposite.prefix(2))
            let fullConv = Array(fullPair.converted)
            var candidate = String(fullConv[..<split.coreLength])
            for ch in fullConv[split.coreLength...] {
                guard ch.isLetter else { break }
                candidate.append(ch)
                if Dict.isValidWordForAutomaticPath(candidate.lowercased(), lang: oth) {
                    bail("ambiguous-suffix")
                    return
                }
            }
        }

        let capsLock = keys.contains { $0.caps }
        let verdict: LayoutVerdict
        switch ruleDecision {
        case .alwaysConvert, .replace:
            verdict = .switchToConverted
        case .neverConvert:
            return
        case .none:
            if mixedCandidate != nil {
                verdict = .switchToConverted
            } else {
                verdict = LayoutDetector.decide(typed: pair.original, converted: pair.converted,
                                                currentLang: langs.current, otherLang: langs.opposite,
                                                capsLock: capsLock,
                                                operationID: replacementOperationID,
                                                rulesAlreadyEvaluated: true)
            }
        }
        rslog("auto: decision op=\(replacementOperationID) len=\(pair.original.count) \(langs.current)/\(langs.opposite) verdict=\(verdict)")  // слова не логируем (приватность)
        guard verdict == .switchToConverted else {
            logAutomaticReplacementOutcome(
                operationID: replacementOperationID,
                startedAt: replacementStartedAt,
                result: verdict == .keep ? "kept" : "undecided",
                layout: "unchanged",
                reason: "detector-verdict"
            )
            return
        }

        if changesLayout,
           snapshot.lineKeys.count >= allKeys.count + bc,
           let prefix = DynamicKeyMapping.lineString(
               from: Array(snapshot.lineKeys.dropLast(allKeys.count + bc))
           ) {
            let targetIsConfirmedWord = LayoutCorrectionEngine.canonicalTrustedTerm(for: targetWord) != nil
                || Dict.isValidWordForAutomaticPath(targetWord.lowercased(), lang: langs.opposite)
            if LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
                corrected: targetWord,
                prefix: prefix,
                currentLanguage: langs.current,
                targetLanguage: langs.opposite,
                targetIsConfirmedWord: targetIsConfirmedWord,
                requiredConsecutiveTargetWords: snapshot.languageSwitchWordThreshold,
                isKnownTargetWord: { word, language in
                    LayoutCorrectionEngine.canonicalTrustedTerm(for: word) != nil
                        || Dict.isValidWordForAutomaticPath(word.lowercased(), lang: language)
                }
            ) {
                changesLayout = false
                rslog("auto: input-layout=keep reason=no-consecutive-target-language-run op=\(replacementOperationID)")
            }
        }
        let layoutIDAfterCorrection = changesLayout ? oppositeLayoutIDAtBoundary : nil
        if changesLayout && layoutIDAfterCorrection == nil {
            rslog("auto: input-layout op=\(replacementOperationID) result=target-source-unavailable")
        }

        if deferToRemote {
            // Удалёнка: текст конвертит офисный инстанс по реальным проброшенным символам.
            // Здесь меняем СВОЮ раскладку — чтобы дальнейший ввод пошёл уже в правильной.
            let layoutResult = applyAutomaticInputLayout(
                sourceLayoutID: sourceLayoutIDAtBoundary,
                targetLayoutID: layoutIDAfterCorrection,
                operationID: replacementOperationID
            )
            updateStatusIcon()
            logAutomaticReplacementOutcome(
                operationID: replacementOperationID,
                startedAt: replacementStartedAt,
                result: "remote-layout-only",
                layout: layoutResult.logValue
            )
            return
        }

        // A short leading word has no reliable standalone signal. Keep it unchanged
        // until this independently confirmed word supplies context, then rewrite only
        if let lineOriginal = DynamicKeyMapping.lineString(from: snapshot.lineKeys) {
            let lineCorrected = SmartConvert.selection(lineOriginal, useSystemDictionary: false)
            if LayoutCorrectionEngine.shouldApplyContextualRewrite(
                original: lineOriginal,
                corrected: lineCorrected,
                currentWordWasConfirmed: verdict == .switchToConverted,
                hasAmbiguousShortWordCorrection: SmartConvert.hasAmbiguousShortWordCorrection(
                    original: lineOriginal, corrected: lineCorrected
                )
            ) {
                switch SafariAddressBarAX.inspect() {
                case .active(let field):
                    let targetProcessID = field.processID
                    let targetIdentity = field.identity
                    _ = enqueueAutomaticAXReplacement(
                        operationID: replacementOperationID, startedAt: replacementStartedAt,
                        snapshot: snapshot, word: pair.original, visibleKeyCount: keys.count,
                        visibleWord: nil, visibleLine: lineCorrected,
                        sourceLayoutID: sourceLayoutIDAtBoundary,
                        targetLayoutID: layoutIDAfterCorrection,
                        label: "contextual Safari suffix",
                        apply: {
                            self.textConverter.convertSafariAddressBarSuffix(
                                originalSuffix: lineOriginal,
                                convertedSuffix: lineCorrected,
                                changesLayout: changesLayout,
                                expectedProcessID: targetProcessID,
                                expectedIdentity: targetIdentity
                            )
                        }
                    )
                    return
                case .uncertain:
                    bail("safari-context-field-uncertain")
                    return
                case .inactive:
                    break
                }
                switch SpotlightAX.inspect() {
                case .active(let field):
                    let targetProcessID = field.processID
                    let targetIdentity = field.identity
                    _ = enqueueAutomaticAXReplacement(
                        operationID: replacementOperationID, startedAt: replacementStartedAt,
                        snapshot: snapshot, word: pair.original, visibleKeyCount: keys.count,
                        visibleWord: nil, visibleLine: lineCorrected,
                        sourceLayoutID: sourceLayoutIDAtBoundary,
                        targetLayoutID: layoutIDAfterCorrection,
                        label: "contextual Spotlight suffix",
                        apply: {
                            self.textConverter.convertSpotlightSuffix(
                                originalSuffix: lineOriginal,
                                convertedSuffix: lineCorrected,
                                changesLayout: changesLayout,
                                expectedProcessID: targetProcessID,
                                expectedIdentity: targetIdentity
                            )
                        }
                    )
                case .uncertain:
                    bail("spotlight-context-field-uncertain")
                case .inactive:
                    let accepted = textConverter.replaceBufferTextPreservingTypedSuffix(
                        operationID: replacementOperationID,
                        original: lineOriginal,
                        converted: lineCorrected,
                        backspaceCount: snapshot.lineKeys.count,
                        changesLayout: changesLayout,
                        processIdentifier: snapshot.processIdentifier,
                        performIfCurrent: { operation in
                            self.keyboardMonitor.performIfWordBoundaryIsCurrent(
                                snapshot, operationID: replacementOperationID, operation: operation
                            )
                        },
                        completion: { completed in
                            guard completed else {
                                self.logAutomaticReplacementOutcome(
                                    operationID: replacementOperationID, startedAt: replacementStartedAt,
                                    result: "cancelled-contextual-buffer", layout: "unchanged"
                                )
                                return
                            }
                            self.reconcileAutomaticVisibleText(
                                snapshot: snapshot, keyCount: keys.count,
                                visibleLine: lineCorrected, operationID: replacementOperationID
                            )
                            let layoutResult = self.applyAutomaticInputLayout(
                                sourceLayoutID: sourceLayoutIDAtBoundary,
                                targetLayoutID: layoutIDAfterCorrection,
                                operationID: replacementOperationID
                            )
                            _ = self.completeAutomaticConversion(
                                word: pair.original,
                                snapshot: snapshot,
                                changesLayout: layoutResult.changedLayout
                            )
                            self.updateStatusIcon()
                            self.logAutomaticReplacementOutcome(
                                operationID: replacementOperationID, startedAt: replacementStartedAt,
                                result: "committed-contextual-buffer",
                                layout: layoutResult.logValue
                            )
                        }
                    )
                    if !accepted {
                        logAutomaticReplacementOutcome(
                            operationID: replacementOperationID, startedAt: replacementStartedAt,
                            result: "refused-contextual-buffer", layout: "unchanged"
                        )
                    }
                }
                return
            }
        }

        // Punctuation rules for ordinary layout conversion depend on the keyboard pair.
        // A literal replacement keeps the user's punctuation exactly as typed.
        let convertedSuffix = keys.allSatisfy({ $0.char != nil })
            ? suffix : DynamicKeyMapping.punctThroughCurrentPair(suffix)

        switch SafariAddressBarAX.inspect() {
        case .active(let field):
            let targetProcessID = field.processID
            let targetIdentity = field.identity
            _ = enqueueAutomaticAXReplacement(
                operationID: replacementOperationID, startedAt: replacementStartedAt,
                snapshot: snapshot, word: pair.original, visibleKeyCount: keys.count,
                visibleWord: targetWord, visibleLine: nil,
                sourceLayoutID: sourceLayoutIDAtBoundary,
                targetLayoutID: layoutIDAfterCorrection,
                label: "Safari word",
                apply: {
                    self.textConverter.convertSafariAddressBarWord(
                        original: pair.original, converted: targetWord,
                        boundaryCount: bc, changesLayout: changesLayout,
                        expectedProcessID: targetProcessID, expectedIdentity: targetIdentity
                    )
                }
            )
            return
        case .uncertain:
            bail("safari-field-uncertain")
            return
        case .inactive:
            break
        }

        // Spotlight использует тот же точный AX диапазон, что и ручная конвертация.
        // Суффиксный случай пока пропускается, чтобы не трогать неоднозначный ввод.
        switch SpotlightAX.inspect() {
        case .active(let field):
            let targetProcessID = field.processID
            let targetIdentity = field.identity
            rslog("auto: Spotlight field active op=\(replacementOperationID)")
            _ = enqueueAutomaticAXReplacement(
                operationID: replacementOperationID, startedAt: replacementStartedAt,
                snapshot: snapshot, word: pair.original, visibleKeyCount: keys.count,
                visibleWord: targetWord, visibleLine: nil,
                sourceLayoutID: sourceLayoutIDAtBoundary,
                targetLayoutID: layoutIDAfterCorrection,
                label: "Spotlight word",
                apply: {
                    self.textConverter.convertSpotlightWord(
                        original: pair.original, converted: targetWord,
                        boundaryCount: bc, changesLayout: changesLayout,
                        expectedProcessID: targetProcessID, expectedIdentity: targetIdentity
                    )
                }
            )
            return
        case .uncertain:
            bail("spotlight-field-uncertain")
            return
        case .inactive:
            rslog("auto: Spotlight not detected op=\(replacementOperationID); using regular replacement path")
        }

        let outputSuffix: String
        if case .replace = ruleDecision {
            outputSuffix = suffix
        } else {
            outputSuffix = convertedSuffix
        }
        let spaces = String(repeating: " ", count: bc)
        let originalText = pair.original + suffix + spaces
        let convertedText = targetWord + outputSuffix + spaces
        rslog("auto: convert op=\(replacementOperationID) len=\(keys.count) (+\(suffix.count) punct, +\(bc) sp)")
        guard textConverter.replaceBufferTextPreservingTypedSuffix(
            operationID: replacementOperationID,
            original: originalText,
            converted: convertedText,
            backspaceCount: keys.count + suffix.count + bc,
            changesLayout: changesLayout,
            processIdentifier: snapshot.processIdentifier,
            performIfCurrent: { operation in
                self.keyboardMonitor.performIfWordBoundaryIsCurrent(
                    snapshot, operationID: replacementOperationID, operation: operation
                )
            },
            completion: { completed in
                guard completed else {
                    self.logAutomaticReplacementOutcome(
                        operationID: replacementOperationID, startedAt: replacementStartedAt,
                        result: "cancelled-buffer", layout: "unchanged"
                    )
                    return
                }
                self.reconcileAutomaticVisibleText(
                    snapshot: snapshot, keyCount: keys.count,
                    visibleWord: targetWord, operationID: replacementOperationID
                )
                let layoutResult = self.applyAutomaticInputLayout(
                    sourceLayoutID: sourceLayoutIDAtBoundary,
                    targetLayoutID: layoutIDAfterCorrection,
                    operationID: replacementOperationID
                )
                _ = self.completeAutomaticConversion(
                    word: pair.original,
                    snapshot: snapshot,
                    changesLayout: layoutResult.changedLayout,
                    preservingTypedSuffixKeyCount: self.textConverter.lastPreservedSuffixKeyCount
                )
                self.updateStatusIcon()
                self.logAutomaticReplacementOutcome(
                    operationID: replacementOperationID, startedAt: replacementStartedAt,
                    result: "committed-buffer", layout: layoutResult.logValue
                )
            }
        ) else {
            logAutomaticReplacementOutcome(
                operationID: replacementOperationID, startedAt: replacementStartedAt,
                result: "refused-buffer", layout: "unchanged"
            )
            return
        }
    }

    /// Предлагает включить автозагрузку при первом запуске (один раз)
    private func offerLaunchAtLoginIfNeeded() {
        let settings = SettingsManager.shared
        guard !settings.launchAtLoginAsked else { return }
        settings.launchAtLoginAsked = true

        let alert = GraphiteAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.wizardLaunchAtLoginTitle
        alert.informativeText = L10n.wizardLaunchAtLoginText
        alert.addButton(withTitle: L10n.wizardYes)
        alert.addButton(withTitle: L10n.wizardNo)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            settings.launchAtLogin = true
            settingsController.updateLaunchAtLoginState(true)
            rslog("User enabled launch at login")
        } else {
            rslog("User declined launch at login")
        }
    }

    /// Предлагает включить автозамену при первом запуске (один раз). Фича OFF по умолчанию,
    /// поэтому без явного предложения пользователь о ней не узнает.
    private func offerAutoConvertIfNeeded() {
        let settings = SettingsManager.shared
        guard !settings.autoConvertOffered else { return }
        settings.autoConvertOffered = true

        let alert = GraphiteAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.onboardAutoConvertTitle
        alert.informativeText = L10n.onboardAutoConvertText
        alert.addButton(withTitle: L10n.wizardYes)
        alert.addButton(withTitle: L10n.wizardNo)

        if alert.runModal() == .alertFirstButtonReturn {
            applyAutoConvertOptIn()
            // Synchronize the already-open settings and the status item, not only the menu.
            rslog("User enabled auto-convert at onboarding")
        } else {
            rslog("User declined auto-convert at onboarding")
        }
    }

    private func applyAutoConvertOptIn() {
        SettingsManager.shared.autoConvert = true
        settingsController.updateAutoConvertState(true)
        updateStatusIcon()
        rebuildMenu()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Иконку можно полностью скрыть (Настройки → Расширенные). isVisible вместо
        // removeStatusItem: система помнит позицию, а объект живёт — все пути обновления
        // (updateStatusIcon/rebuildMenu) продолжают работать без nil-проверок.
        statusItem.isVisible = !SettingsManager.shared.hideMenuBarIcon
        rebuildMenu()
        // Set a readable layout badge immediately, including while permissions or the
        // keyboard monitor are still starting up.
        updateStatusIcon()
        // issue #9: иконка должна отражать раскладку и при СИСТЕМНОЙ смене (стандартный/
        // переопределённый хоткей), а не только при нашей конверсии. Слушаем системное
        // распределённое уведомление о смене источника ввода.
        // suspensionBehavior: .deliverImmediately — иначе для фонового menu-bar-приложения
        // распределённое уведомление коалесцируется/откладывается (App Nap / suspend), и
        // иконка после переключения глобусом 🌐 меняется с задержкой до нескольких секунд
        // (ждёт пробуждения или 2-секундного опроса). deliverImmediately обновляет флаг сразу.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemInputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(self,
            selector: #selector(systemInputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifyEnabledKeyboardInputSourcesChanged"),
            object: nil, suspensionBehavior: .deliverImmediately)
    }

    /// The utility stays accessory-only until Settings opens, but a real application
    /// menu routes Cmd+, / Cmd+W / Cmd+Q through AppKit, including when a text control
    /// has focus.
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                             ?? "MultiSwitcher")
        let settingsItem = NSMenuItem(title: L10n.menuSettings,
                                      action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        settingsItem.image = nil
        #if compiler(>=6.4)
        // This property is declared only by the macOS 27 SDK, not older SDKs.
        if #available(macOS 27.0, *) { settingsItem.preferredImageVisibility = .hidden }
        #endif
        appMenu.addItem(settingsItem)

        let closeWindowItem = NSMenuItem(title: L10n.menuCloseWindow,
                                         action: #selector(closeSettingsWindow), keyEquivalent: "w")
        closeWindowItem.keyEquivalentModifierMask = .command
        closeWindowItem.target = self
        appMenu.addItem(closeWindowItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.menuQuit, action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        appMenu.addItem(quitItem)
        mainMenu.setSubmenu(appMenu, for: appMenuItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func systemInputSourceChanged() {
        updateStatusIcon()
        keyboardMonitor.soundArmed = true  // issue #7: следующая буква даст звук раскладки
    }

    /// Isolated acceptance: drive the real system notification path, never the UI refresh directly.
    private func reviewSystemLayout(to directory: String) {
        Task { @MainActor in
            NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .milliseconds(250))
            let original = LayoutSwitcher.currentLayoutID()
            let originalBrand = NSApp.applicationIconImage?.tiffRepresentation
            let sources = layoutPresentation.snapshot.sources
            let first = sources.first(where: { $0.language?.hasPrefix("ru") == true }) ?? sources.first
            let second = sources.first(where: { $0.language?.hasPrefix("en") == true && $0.id != first?.id })
                ?? sources.first(where: { $0.id != first?.id })
            var failures: [String] = [], count = 0, maxLatency = 0.0
            if let first, let second {
                if let menu = statusMenu { menuWillOpen(menu) }
                for index in 0..<30 {
                    let target = LayoutSwitcher.currentLayoutID() == first.id ? second.id : first.id
                    let start = ProcessInfo.processInfo.systemUptime
                    if !LayoutSwitcher.switchTo(layoutID: target) { failures.append("selection \(index)"); continue }
                    while layoutPresentation.snapshot.selectedID != target && ProcessInfo.processInfo.systemUptime - start < 0.5 {
                        try? await Task.sleep(for: .milliseconds(5))
                    }
                    maxLatency = max(maxLatency, (ProcessInfo.processInfo.systemUptime - start) * 1000)
                    let parent = statusMenu?.item(withTag: Self.layoutParentTag)
                    let selected = parent?.submenu?.items.filter { $0.state == .on } ?? []
                    let matches = parent?.title.hasSuffix(layoutPresentation.snapshot.badge) == true
                        && selected.count == 1 && selected.first?.representedObject as? String == target
                    if layoutPresentation.snapshot.selectedID != target || !matches {
                        failures.append("notification/menu \(index)")
                    }
                    if NSApp.applicationIconImage?.tiffRepresentation != originalBrand { failures.append("brand \(index)") }
                    count += 1
                    if [14, 29].contains(index), let window = statusItem.button?.window {
                        MultiEcosystemProbe.capture(window, path: directory + "/live-badge-\(index).png")
                    }
                    try? await Task.sleep(for: .milliseconds(20))
                }
            } else { failures.append("two enabled input sources required") }
            _ = LayoutSwitcher.switchTo(layoutID: original)
            let restoreStart = ProcessInfo.processInfo.systemUptime
            while LayoutSwitcher.currentLayoutID() != original && ProcessInfo.processInfo.systemUptime - restoreStart < 0.5 {
                try? await Task.sleep(for: .milliseconds(5))
            }
            if let menu = statusMenu { menuDidClose(menu) }
            let result: [String: Any] = ["switches": count, "failures": failures, "evidence": "real TIS source changes and native menu snapshot; not physical pointer traversal",
                "maxNotificationLatencyMS": maxLatency, "originalSourceRestored": LayoutSwitcher.currentLayoutID() == original]
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: directory + "/live-layout-results.json"))
            NSLog("LIVE LAYOUT REVIEW switches=%d failures=%d restored=%@", count, failures.count,
                (LayoutSwitcher.currentLayoutID() == original).description)
            NSApp.terminate(nil)
        }
    }

    /// Normal input-source changes arrive through the distributed system notification.
    /// Keep the polling fallback only for remote-desktop sessions, where that notification
    /// has been observed to go missing. This avoids waking the main run loop every 2s on
    /// ordinary idle Macs while preserving the remote-session recovery path.
    private func configureIconRefreshFallback() {
        iconRefreshTimer?.invalidate()
        iconRefreshTimer = nil
        guard monitoringActive, !SettingsManager.shared.isPaused,
              SettingsManager.shared.remoteDesktopMode else { return }
        iconRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusIcon() }
        }
    }

    /// Собирает меню статус-бара. Вызывается заново при смене языка интерфейса,
    /// иначе пункты меню остаются на старом языке.
    private func rebuildMenu() {
        if statusMenuTracking {
            statusMenuNeedsRebuild = true
            refreshNativeMenuState()
            return
        }
        statusMenuNeedsRebuild = false
        let menu = NSMenu()
        menu.autoenablesItems = false
        let enabled = NSMenuItem(title: L10n.menuAutoSwitch, action: #selector(toggleAutoSwitch), keyEquivalent: "")
        enabled.tag = 747
        enabled.target = self
        enabled.state = SettingsManager.shared.autoSwitchEnabled ? .on : .off
        menu.addItem(enabled)

        let layoutItem = NSMenuItem(title: "\(L10n.menuLayout): \(badgeForCurrentLayout())", action: nil, keyEquivalent: "")
        layoutItem.tag = Self.layoutParentTag
        layoutItem.submenu = NSMenu()
        menu.addItem(layoutItem)

        let permissionsReady = AXIsProcessTrusted() && CGPreflightListenEventAccess()
        let autoConvertTitle = permissionsReady
            ? L10n.menuAutoConvert
            : "\(L10n.menuAutoConvert) — \(L10n.menuPausedMissingPermissions)"
        let autoConvertItem = NSMenuItem(title: autoConvertTitle, action: #selector(toggleAutoConvert), keyEquivalent: "")
        autoConvertItem.tag = 748
        autoConvertItem.target = self
        autoConvertItem.state = SettingsManager.shared.autoConvert ? .on : .off
        menu.addItem(autoConvertItem)

        // Keep the everyday menu compact, but surface the exact next step when
        // macOS currently prevents keyboard monitoring. This is informational and
        // never opens System Settings until the user selects it.
        if !permissionsReady {
            let permissionsItem = NSMenuItem(title: L10n.menuCheckPermissions,
                                             action: #selector(recheckPermissions),
                                             keyEquivalent: "")
            permissionsItem.target = self
            menu.addItem(permissionsItem)
        }

        let pauseItem = NSMenuItem(title: SettingsManager.shared.isPaused ? L10n.menuResume : L10n.menuPause,
                                   action: nil, keyEquivalent: "")
        pauseItem.tag = Self.pauseParentTag
        pauseItem.submenu = NSMenu()
        menu.addItem(pauseItem)

        let appModeItem = NSMenuItem(title: L10n.menuForCurrentApp("—"), action: nil, keyEquivalent: "")
        appModeItem.tag = Self.appModeParentTag
        appModeItem.submenu = NSMenu()
        menu.addItem(appModeItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: L10n.menuSettings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = nil
        #if compiler(>=6.4)
        // This property is declared only by the macOS 27 SDK, not older SDKs.
        if #available(macOS 27.0, *) { settingsItem.preferredImageVisibility = .hidden }
        #endif
        menu.addItem(settingsItem)
        let helpItem = NSMenuItem(title: L10n.languageCode == "ru" ? "справка" : "help", action: #selector(showHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        let quitItem = NSMenuItem(title: L10n.menuQuit, action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusMenu = menu
        statusItem.menu = menu
        statusItem.button?.target = nil
        statusItem.button?.action = nil
        rslog("Menu (re)built with \(menu.items.count) items")
    }

    @objc private func toggleStatusPopover() {
        guard let button = statusItem.button, let menu = statusMenu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
    }

    private func toggleLegacyPopoverForReview() {
        guard let button = statusItem.button else { return }
        if statusPopover == nil {
            let controller = StatusPopoverController(behavior: ProcessInfo.processInfo.environment["MULTISWITCHER_LAYOUT_LIVE_REVIEW"] == "1" ? .applicationDefined : .transient)
            controller.menuProvider = { [weak self] in
                guard let self, let menu = self.statusMenu else { return nil }
                self.prepareStatusMenu(menu)
                return menu
            }
            controller.toggleEnabled = { [weak self] in self?.toggleAutoSwitch(NSMenuItem()) }
            statusPopover = controller
        }
        statusPopover?.toggle(near: button)
    }

    /// Calls the shipping NSMenu delegates/state updates; fixtures are isolated from user data.
    private func auditNativeMenu(directory: String, transitions: [[String: Any]]) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let audit = NativeMenuAuditState(transitions: transitions)
        SettingsManager.shared.autoConvert = false
        settingsController.updateAutoConvertState(false)
        applyAutoConvertOptIn()
        if !settingsController.auditAutoConvertMatchesSetting { audit.failures.append("onboarding settings synchronization") }
        for cycle in 0..<100 {
            guard let menu = statusMenu else { audit.failures.append("missing root"); break }
            menuWillOpen(menu)
            let identities = menu.items.map(ObjectIdentifier.init)
            let pauseIdentities = menu.item(withTag: Self.pauseParentTag)?.submenu?.items.map(ObjectIdentifier.init)
            SettingsManager.shared.autoSwitchEnabled = cycle % 2 == 0
            SettingsManager.shared.autoConvert = cycle % 3 == 0
            SettingsManager.shared.isPaused = true
            rebuildMenu()
            if menu.items.map(ObjectIdentifier.init) != identities { audit.failures.append("root identity \(cycle)") }
            SettingsManager.shared.isPaused = false
            refreshNativeMenuState()
            if let pause = menu.item(withTag: Self.pauseParentTag)?.submenu {
                if pause.items.map(ObjectIdentifier.init) != pauseIdentities { audit.failures.append("pause identity \(cycle)") }
                if pause.items.contains(where: { $0.isEnabled != ($0.tag != 0) }) { audit.failures.append("pause expiry state \(cycle)") }
            }
            if menu.item(withTag: 747)?.state != (SettingsManager.shared.autoSwitchEnabled ? .on : .off) { audit.failures.append("enabled state") }
            if menu.item(withTag: 748)?.state != (SettingsManager.shared.autoConvert ? .on : .off) { audit.failures.append("convert state") }
            menuDidClose(menu)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {

            @MainActor func captureMenu(_ index: Int) {
                guard index < 2, let menu = self.statusMenu, let button = self.statusItem.button else {
                    let report: [String: Any] = ["evidence": "native NSMenu and actual controller; programmatic fixture interactions",
                        "cycles": 100, "failures": audit.failures, "pageTransitions": audit.transitions, "captures": audit.captures,
                        "trackingAfterClose": self.statusMenuTracking,
                        "connectedDisplays": NSScreen.screens.count]
                    try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                        .write(to: URL(fileURLWithPath: directory + "/native-results.json"))
                    NSApp.terminate(nil)
                    return
                }
                DesignTheme.shared.preference = index == 0 ? .light : .dark
                let timer = Timer(timeInterval: 0.35, repeats: false) { _ in
                    MainActor.assumeIsolated {
                        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
                        let native = windows.first { entry in
                            guard (entry[kCGWindowOwnerPID as String] as? Int32) == ProcessInfo.processInfo.processIdentifier,
                                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
                            return (entry[kCGWindowLayer as String] as? Int ?? 0) > 0
                                && (bounds["Width"] ?? 0) > 140 && (bounds["Height"] ?? 0) > 100
                        }
                        let name = index == 0 ? "native-menu-light" : "native-menu-dark"
                        var captured = false
                        if let id = native?[kCGWindowNumber as String] as? Int {
                            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                            process.arguments = ["-x", "-o", "-l", String(id), directory + "/" + name + ".png"]
                            try? process.run(); process.waitUntilExit(); captured = process.terminationStatus == 0
                        }
                        audit.captures.append(["name": name, "capturedWindowServer": captured])
                        self.statusMenu?.cancelTrackingWithoutAnimation()
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
                DispatchQueue.main.async { captureMenu(index + 1) }
            }
            captureMenu(0)
        }
    }

    // MARK: - Layout list in menu

    /// Метка пунктов-раскладок, чтобы находить и обновлять их группу в меню.
    private static let layoutItemTag = 741
    private static let undoLearnedItemTag = 742
    private static let currentAppExclusionItemTag = 743
    private static let currentAppAllActionsItemTag = 744
    private static let layoutParentTag = 740
    private static let pauseParentTag = 745
    private static let appModeParentTag = 746
    private static let appModeNormalTag = 1
    private static let appModeManualTag = 2
    private static let appModeOffTag = 3

    /// Пункты списка раскладок: «буквенная метка + локализованное имя», галочка на текущей.
    private func layoutMenuItems() -> [NSMenuItem] {
        let snapshot = layoutPresentation.snapshot
        return snapshot.sources.map { source in
            let item = NSMenuItem(title: source.badge + " " + source.name,
                action: #selector(selectLayout(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = source.id
            item.state = source.id == snapshot.selectedID ? .on : .off
            item.tag = Self.layoutItemTag
            return item
        }
    }

    /// Пересобирает группу раскладок при каждом открытии меню: состав и галочка должны
    /// отражать систему на момент клика (раскладки добавляют/удаляют в настройках ОС,
    /// а текущую меняют и мимо нас — системным хоткеем).
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        prepareStatusMenu(menu)
        statusMenuTracking = true
    }

    private func prepareStatusMenu(_ menu: NSMenu) {
        if layoutPresentation.refresh() { updateStatusIcon() }
        if let layout = menu.items.first(where: { $0.tag == Self.layoutParentTag }) {
            layout.title = "\(L10n.menuLayout): \(badgeForCurrentLayout())"
            layout.submenu?.removeAllItems()
            layoutMenuItems().forEach { layout.submenu?.addItem($0) }
        }
        rebuildPauseSubmenu(menu.items.first(where: { $0.tag == Self.pauseParentTag }))
        rebuildCurrentAppSubmenu(menu.items.first(where: { $0.tag == Self.appModeParentTag }))
        refreshNativeMenuState()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        statusMenuTracking = false
        if statusMenuNeedsRebuild {
            DispatchQueue.main.async { [weak self] in self?.rebuildMenu() }
        }
    }

    private func refreshNativeMenuState() {
        guard let menu = statusMenu else { return }
        menu.item(withTag: 747)?.state = SettingsManager.shared.autoSwitchEnabled ? .on : .off
        menu.item(withTag: 748)?.state = SettingsManager.shared.autoConvert ? .on : .off
        if let layout = menu.item(withTag: Self.layoutParentTag) {
            layout.title = "\(L10n.menuLayout): \(badgeForCurrentLayout())"
            for item in layout.submenu?.items ?? [] {
                let sourceID = item.representedObject as? String
                item.state = sourceID == layoutPresentation.snapshot.selectedID ? .on : .off
                item.isEnabled = layoutPresentation.snapshot.sources.contains { $0.id == sourceID }
            }
        }
        if let pause = menu.item(withTag: Self.pauseParentTag) {
            pause.title = SettingsManager.shared.isPaused ? L10n.menuResume : L10n.menuPause
            for item in pause.submenu?.items ?? [] {
                item.isEnabled = item.tag == 0 ? SettingsManager.shared.isPaused : !SettingsManager.shared.isPaused
            }
        }
    }

    private func rebuildPauseSubmenu(_ item: NSMenuItem?) {
        guard let item, let submenu = item.submenu else { return }
        submenu.removeAllItems()
        item.title = SettingsManager.shared.isPaused ? L10n.menuResume : L10n.menuPause
        for (title, tag) in [(L10n.menuPause15, 15), (L10n.menuPause60, 60),
                             (L10n.menuPauseUntilResume, -1), (L10n.menuResume, 0)] {
            let action = makeMenuAction(title, tag: tag, action: #selector(selectPauseMode(_:)))
            action.isEnabled = tag == 0 ? SettingsManager.shared.isPaused : !SettingsManager.shared.isPaused
            submenu.addItem(action)
        }
    }

    private func rebuildCurrentAppSubmenu(_ item: NSMenuItem?) {
        guard let item, let submenu = item.submenu else { return }
        submenu.removeAllItems()
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else {
            item.title = L10n.menuForCurrentApp("—")
            item.isEnabled = false
            return
        }
        item.title = L10n.menuForCurrentApp(app.localizedName ?? bundleID)
        item.isEnabled = !AutoSwitchPolicy.protectedApps.contains(bundleID)
        let mode = currentAppMode(bundleID)
        let options = [
            (L10n.menuAppNormally, Self.appModeNormalTag),
            (L10n.menuAppManual, Self.appModeManualTag),
            (L10n.menuAppOff, Self.appModeOffTag),
        ]
        for (title, tag) in options {
            let option = makeMenuAction(title, tag: tag, action: #selector(selectCurrentAppMode(_:)))
            option.representedObject = bundleID
            option.state = mode == tag ? .on : .off
            option.isEnabled = item.isEnabled
            submenu.addItem(option)
        }
    }

    private func currentAppMode(_ bundleID: String) -> Int {
        if AutoSwitchPolicy.areAllActionsDisabled(bundleID) { return Self.appModeOffTag }
        if AutoSwitchPolicy.isDeniedApp(bundleID) { return Self.appModeManualTag }
        return Self.appModeNormalTag
    }

    private func makeMenuAction(_ title: String, tag: Int, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }

    @objc private func selectCurrentAppMode(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String,
              !AutoSwitchPolicy.protectedApps.contains(bundleID) else { return }
        var denied = SettingsManager.shared.deniedApps.filter { $0 != bundleID }
        var allActions = SettingsManager.shared.allActionsDeniedApps.filter { $0 != bundleID }
        if sender.tag == Self.appModeManualTag { denied.append(bundleID) }
        if sender.tag == Self.appModeOffTag { allActions.append(bundleID) }
        SettingsManager.shared.deniedApps = denied
        SettingsManager.shared.allActionsDeniedApps = allActions
        keyboardMonitor.markConverted()
        textConverter.clearState()
        updateStatusIcon()
        rebuildMenu()
    }

    @objc private func selectPauseMode(_ sender: NSMenuItem) {
        if sender.tag == 0 {
            setPaused(false)
        } else if sender.tag == -1 {
            setPaused(true, duration: nil)
        } else {
            setPaused(true, duration: TimeInterval(sender.tag * 60))
        }
    }

    private func schedulePauseExpiry() {
        pauseExpiryWorkItem?.cancel()
        pauseExpiryWorkItem = nil
        guard SettingsManager.shared.isPaused, let deadline = SettingsManager.shared.pauseDeadline else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  PauseStatePolicy.hasExpiredDeadline(SettingsManager.shared.pauseDeadline) else { return }
            SettingsManager.shared.clearExpiredPause()
            self.runPermissionWizard()
            self.updateStatusIcon()
            self.rebuildMenu()
        }
        pauseExpiryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow), execute: work)
    }

    private func setPaused(_ paused: Bool, duration: TimeInterval? = nil) {
        pauseExpiryWorkItem?.cancel()
        pauseExpiryWorkItem = nil
        if paused {
            SettingsManager.shared.pause(for: duration)
            keyboardMonitor.stop()
            monitoringActive = false
            iconRefreshTimer?.invalidate()
            iconRefreshTimer = nil
            perAppLayoutManager.stop()
            caretIndicator?.teardown()
            caretIndicator = nil
            learningNotice.show(title: L10n.menuPause, body: L10n.pauseActiveBody,
                                near: statusItem?.button)
            schedulePauseExpiry()
        } else {
            SettingsManager.shared.isPaused = false
            runPermissionWizard()
            learningNotice.show(title: L10n.menuPause, body: L10n.pauseResumedBody,
                                near: statusItem?.button)
        }
        updateStatusIcon()
        rebuildMenu()
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              id != LayoutSwitcher.currentLayoutID() else { return }
        LayoutSwitcher.switchTo(layoutID: id)
        // Явная смена раскладки делает набранный буфер неактуальным — как при per-app restore.
        keyboardMonitor.markConverted()
        textConverter.clearState()
        updateStatusIcon()
    }

    func updateStatusIcon() {
        let layoutChanged = layoutPresentation.refresh()
        let badge = badgeForCurrentLayout()
        // Каретку дёргаем ТОЛЬКО при реальной смене раскладки: updateStatusIcon зовётся ещё и
        // 2-секундным опросом-страховкой, иначе метка у каретки выскакивала бы каждые 2с.
        // Бейдж отражает текущую раскладку независимо от состояния автокоррекции.
        let changed = lastSourceShown != layoutPresentation.snapshot.selectedID
        lastSourceShown = layoutPresentation.snapshot.selectedID
        let autoEnabled = SettingsManager.shared.autoSwitchEnabled
            && SettingsManager.shared.autoConvert
            && !SettingsManager.shared.isPaused
            && AXIsProcessTrusted()
            && CGPreflightListenEventAccess()
        statusItem.button?.image = nil
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        if !autoEnabled { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        statusItem.button?.attributedTitle = NSAttributedString(string: badge, attributes: attributes)
        statusItem.button?.appearsDisabled = false
        statusItem.button?.toolTip = "multiswitcher · \(L10n.menuLayout): \(badge)"
        statusItem.button?.setAccessibilityLabel("multiswitcher · \(L10n.menuLayout): \(badge)")
        if changed { caretIndicator?.layoutChanged() }
        refreshNativeMenuState()
        if layoutChanged { statusPopover?.refresh() }
    }

    /// Буквенная метка текущей раскладки по коду языка (BCP-47).
    func badgeForCurrentLayout() -> String { layoutPresentation.snapshot.badge }

    /// issue #10: создаёт/освобождает индикатор каретки по настройке. Создаётся лениво,
    /// только когда фича включена И мониторинг запущен (нужны разрешения).
    private func syncCaretIndicator() {
        keyboardMonitor.caretFlagEnabled = SettingsManager.shared.caretFlag   // гейт диспатча onUserInput
        if SettingsManager.shared.caretFlag, monitoringActive {
            if caretIndicator == nil {
                let ci = CaretIndicator()
                ci.badgeProvider = { [weak self] in self?.badgeForCurrentLayout() ?? "" }
                caretIndicator = ci
            }
        } else {
            caretIndicator?.teardown()
            caretIndicator = nil
        }
    }

    // MARK: - Actions

    @objc private func toggleCurrentAppExclusion(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String,
              !AutoSwitchPolicy.protectedApps.contains(bundleID) else { return }
        var denied = SettingsManager.shared.deniedApps
        if denied.contains(bundleID) {
            denied.removeAll { $0 == bundleID }
        } else {
            let coveredByWildcard = denied.contains {
                $0.hasSuffix("*") && bundleID.hasPrefix(String($0.dropLast()))
            }
            guard !coveredByWildcard else { return }
            denied.append(bundleID)
        }
        SettingsManager.shared.deniedApps = denied
        rebuildMenu()
    }

    @objc private func toggleCurrentAppAllActions(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String,
              !AutoSwitchPolicy.protectedApps.contains(bundleID) else { return }
        var denied = SettingsManager.shared.allActionsDeniedApps
        if denied.contains(bundleID) {
            denied.removeAll { $0 == bundleID }
        } else {
            let coveredByWildcard = denied.contains {
                $0.hasSuffix("*") && bundleID.hasPrefix(String($0.dropLast()))
            }
            guard !coveredByWildcard else { return }
            denied.append(bundleID)
        }
        SettingsManager.shared.allActionsDeniedApps = denied
        rebuildMenu()
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        SettingsManager.shared.isPaused.toggle()
        sender.state = SettingsManager.shared.isPaused ? .on : .off
        if SettingsManager.shared.isPaused {
            keyboardMonitor.stop()
            monitoringActive = false
            iconRefreshTimer?.invalidate()
            iconRefreshTimer = nil
            perAppLayoutManager.stop()
            caretIndicator?.teardown()
            caretIndicator = nil
            learningNotice.show(title: L10n.menuPause, body: L10n.pauseActiveBody,
                                near: statusItem?.button)
        } else {
            runPermissionWizard()
            learningNotice.show(title: L10n.menuPause, body: L10n.pauseResumedBody,
                                near: statusItem?.button)
        }
        updateStatusIcon()
        rebuildMenu()
    }

    @objc private func toggleLearning(_ sender: NSMenuItem) {
        SettingsManager.shared.learningEnabled.toggle()
        sender.state = SettingsManager.shared.learningEnabled ? .on : .off
        let body = SettingsManager.shared.learningEnabled
            ? L10n.learningEnabledBody : L10n.learningDisabledBody
        learningNotice.show(title: L10n.menuLearning, body: body, near: statusItem?.button)
    }

    @objc private func undoLastLearned(_ sender: NSMenuItem) {
        guard SettingsManager.shared.undoLastLearnedExclusion() != nil else { return }
        lastLearnedWord = nil
        rebuildMenu()
        learningNotice.show(title: L10n.learningAddedTitle, body: L10n.learningRemovedBody,
                            near: statusItem?.button)
    }

    @objc private func toggleAutoSwitch(_ sender: NSMenuItem) {
        SettingsManager.shared.autoSwitchEnabled.toggle()
        let enabled = SettingsManager.shared.autoSwitchEnabled
        sender.state = enabled ? .on : .off
        settingsController.updateAutoSwitchState(enabled)
        updateStatusIcon()
    }

    @objc private func toggleAutoConvert(_ sender: NSMenuItem) {
        SettingsManager.shared.autoConvert.toggle()
        sender.state = SettingsManager.shared.autoConvert ? .on : .off
        settingsController.updateAutoConvertState(SettingsManager.shared.autoConvert)   // #4
        updateStatusIcon()
    }

    @objc private func toggleKeySound(_ sender: NSMenuItem) {
        SettingsManager.shared.keySound.toggle()
        sender.state = SettingsManager.shared.keySound ? .on : .off
    }

    @objc private func toggleCaretFlag(_ sender: NSMenuItem) {
        SettingsManager.shared.caretFlag.toggle()
        sender.state = SettingsManager.shared.caretFlag ? .on : .off
        settingsController.updateCaretFlagState(SettingsManager.shared.caretFlag)
        syncCaretIndicator()   // создать/снести индикатор и обновить гейт onUserInput
    }

    @objc private func toggleRemoteDesktop(_ sender: NSMenuItem) {
        SettingsManager.shared.remoteDesktopMode.toggle()
        sender.state = SettingsManager.shared.remoteDesktopMode ? .on : .off
        settingsController.updateRemoteDesktopState(SettingsManager.shared.remoteDesktopMode)   // #5
        configureIconRefreshFallback()
        reconfigureTap()  // уровень event tap зависит от режима
    }

    /// Пересоздаёт event tap и, если создание не удалось (например, session-tap отклонён),
    /// ретраит — иначе тумблер «вкл», а tap'а нет, и приложение молча не реагирует на триггер.
    private func reconfigureTap() {
        guard !keyboardMonitor.reconfigure() else { return }
        rslog("reconfigure failed (tap denied) — retry in 3s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.keyboardMonitor.reconfigure() == false { rslog("reconfigure retry failed") }
        }
    }

    @objc private func recheckPermissions() {
        runPermissionWizard(interactive: true)
    }

    @objc private func checkForUpdates(_ sender: NSMenuItem) {
        UpdateChecker.checkNow()
    }

    @objc private func openSettings() {
        settingsController.showWindow()
    }

    @objc private func closeSettingsWindow() {
        settingsController.closeSettingsWindow()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        keyboardMonitor.stop()
        perAppLayoutManager.stop()
        guard textConverter.hasPendingReplacements else {
            textConverter.flushPendingClipboardRestore()
            return .terminateNow
        }
        Task { @MainActor [weak self] in
            while self?.textConverter.hasPendingReplacements == true {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            self?.textConverter.flushPendingClipboardRestore()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Не теряем буфер обмена в 2-секундном окне отложенного восстановления
        // (актуально и при само-обновлении, которое завершает процесс).
        textConverter.flushPendingClipboardRestore()
    }

    @objc private func quit() {
        textConverter.flushPendingClipboardRestore()
        perAppLayoutManager.stop()
        keyboardMonitor.stop()
        NSApplication.shared.terminate(nil)
    }
}
