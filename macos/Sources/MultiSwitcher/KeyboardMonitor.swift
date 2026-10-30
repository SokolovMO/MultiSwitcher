import AppKit
import CoreGraphics
import Foundation
import MultiSwitcherCore

/// Маркер для симулированных событий — KeyboardMonitor их игнорирует
let kMultiSwitcherEventMarker: Int64 = 0x52555300

/// Одно нажатие в буфере конверсии. Для обычного локального ввода известен keyCode
/// (char == nil). Для ввода, проброшенного через удалённый стол, Apple Screen Sharing
/// шлёт keyCode 0 + сам символ — тогда char != nil, и конверсия идёт по символу,
/// а не по бесполезному keyCode 0 (именно keyCode 0 рождал «фффффф»).
struct TypedKey: Equatable, Sendable {
    let keyCode: UInt16
    let shift: Bool
    let caps: Bool
    var char: Character? = nil
    /// Input source active for this key, so later layout changes cannot reinterpret it.
    var sourceLayoutID: String? = nil
}

struct WordBoundarySnapshot: Sendable {
    let keys: [TypedKey]
    let boundaryCount: Int
    let bundleIdentifier: String?
    let processIdentifier: pid_t?
    let inputGeneration: UInt64
    let textContextGeneration: UInt64
    let lineKeys: [TypedKey]
    let languageSwitchWordThreshold: Int
}

private struct AppendedInputEvent: Sendable {
    let generation: UInt64
    let character: Character?
    let keyBufferRecoverable: Bool
}

struct ManualConversionSnapshot: Sendable {
    let currentWordKeys: [TypedKey]
    let previousWordKeys: [TypedKey]
    let boundaryCount: Int
    let lineKeys: [TypedKey]
    let inputGeneration: UInt64
    let textContextGeneration: UInt64
    let processIdentifier: pid_t?
    let bundleIdentifier: String?
}

/// Batches diagnostic writes so a debug session does not open and close a file for
/// every keyboard event. All mutable state is confined to the writer's serial queue.
private final class RSLogWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.multiswitcher.log", qos: .utility)
    private var pendingLines: [String] = []
    private var flushTimer: DispatchSourceTimer?
    private let batchSize = 32
    private let maximumFileSize: UInt64 = 5_000_000

    func append(_ message: String) {
        let line = "\(Date()): \(message)\n"
        queue.async { [weak self] in
            guard let self else { return }
            pendingLines.append(line)
            if pendingLines.count >= batchSize {
                flush()
            } else {
                scheduleFlushIfNeeded()
            }
        }
    }

    private func scheduleFlushIfNeeded() {
        guard flushTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(1))
        timer.setEventHandler { [weak self] in self?.flush() }
        flushTimer = timer
        timer.resume()
    }

    private func flush() {
        flushTimer?.cancel()
        flushTimer = nil
        guard !pendingLines.isEmpty else { return }
        let directory = MultiAuditEnvironment.root?.appendingPathComponent("logs", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/MultiSwitcher", isDirectory: true)
        let file = directory.appendingPathComponent("multiswitcher.log")
        let lines = pendingLines.joined()
        pendingLines.removeAll(keepingCapacity: true)
        var data = Data(lines.utf8)

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let fileExists = FileManager.default.fileExists(atPath: file.path)
            let currentSize = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map(UInt64.init) ?? 0
            if fileExists, currentSize + UInt64(data.count) > maximumFileSize {
                data.insert(contentsOf: Data("--- Log rotated ---\n".utf8), at: 0)
                try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: file.path
                )
                return
            }

            if fileExists, let handle = try? FileHandle(forWritingTo: file) {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: file.path
                )
            }
        } catch {
            // Diagnostics must never block or interrupt keyboard input.
        }
    }
}

private let rsLogWriter = RSLogWriter()

func rslog(_ msg: String) {
    guard SettingsManager.shared.debugLogEnabled else { return }
    rsLogWriter.append(msg)
}

/// Конфигурация клавиши-триггера (читается из настроек, кэшируется в KeyboardMonitor).
struct TriggerConfig {
    enum Kind {
        case modifier(mask: CGEventFlags, left: UInt16, right: UInt16)
        /// Комбо из двух модификаторов (например ⌘+⇧). Детект по флагам: оба зажаты без
        /// посторонних → отпущены все без клавиш между. Сторона (left/right) не важна.
        case combo(CGEventFlags, CGEventFlags)
        case capsLock
    }
    let kind: Kind
    let rightOnly: Bool
    let doubleTap: Bool

    var isCapsLock: Bool { if case .capsLock = kind { return true } else { return false } }

    static func current() -> TriggerConfig {
        let s = SettingsManager.shared
        return parse(key: s.triggerKey, rightOnly: s.triggerRightOnly, doubleTap: s.triggerDoubleTap)
    }

    /// issue #14: конфиг хоткея чистого переключения раскладки. nil — выключен.
    /// Совпадение с триггером конверсии игнорируем (иначе один тап делал бы оба действия).
    /// Белый список обязателен: parse() маппит неизвестные строки в Option — рукописный
    /// мусор в defaults дублировал бы дефолтный триггер (ревью-находка).
    static func switchHotkey() -> TriggerConfig? {
        let known: Set<String> = ["option", "command", "control", "shift",
                                  "command+shift", "control+shift", "command+option", "control+option",
                                  "option+shift"]
        let s = SettingsManager.shared
        let key = s.switchHotkey
        guard known.contains(key), key != s.triggerKey else { return nil }
        return parse(key: key, rightOnly: s.switchRightOnly, doubleTap: s.switchDoubleTap)
    }

    /// issue #29: конфиг хоткея смены регистра (nil — выключен). Должен отличаться и от триггера
    /// конверсии, и от хоткея смены раскладки — иначе один тап делал бы два действия.
    static func caseHotkey() -> TriggerConfig? {
        let known: Set<String> = ["option", "command", "control", "shift",
                                  "command+shift", "control+shift", "command+option", "control+option",
                                  "option+shift"]
        let s = SettingsManager.shared
        let key = s.caseHotkey
        guard known.contains(key), key != s.triggerKey, key != s.switchHotkey else { return nil }
        return parse(key: key, rightOnly: s.caseRightOnly, doubleTap: s.caseDoubleTap)
    }

    static func parse(key: String, rightOnly: Bool, doubleTap: Bool) -> TriggerConfig {
        let kind: Kind
        switch key {
        case "command": kind = .modifier(mask: .maskCommand, left: KC.leftCommand, right: KC.rightCommand)
        case "control": kind = .modifier(mask: .maskControl, left: KC.leftControl, right: KC.rightControl)
        case "shift":   kind = .modifier(mask: .maskShift,   left: KC.leftShift,   right: KC.rightShift)
        // Комбо двух модификаторов (issue #12: привычный по Windows стиль Alt+Shift и т.п.).
        case "command+shift":  kind = .combo(.maskCommand, .maskShift)
        case "control+shift":  kind = .combo(.maskControl, .maskShift)
        case "command+option": kind = .combo(.maskCommand, .maskAlternate)
        case "control+option": kind = .combo(.maskControl, .maskAlternate)
        // discussion #32: ⌥+⇧ — виндовый дефолт; тап-детект комбо (любой keyDown между
        // нажатием и отпусканием сбрасывает взвод) исключает конфликт с ⌥⇧+буква/стрелки.
        case "option+shift":   kind = .combo(.maskAlternate, .maskShift)
        // ТЕХДОЛГ: нативный Caps Lock убран из UI (нестабилен — HID-дебаунс/тоггл,
        // нужен HID-драйвер уровня Karabiner). Код consume-пути оставлен на будущее.
        case "capsLock": kind = .capsLock
        default:        kind = .modifier(mask: .maskAlternate, left: KC.leftOption, right: KC.rightOption)
        }
        return TriggerConfig(kind: kind, rightOnly: rightOnly, doubleTap: doubleTap)
    }
}

final class KeyboardMonitor: @unchecked Sendable {
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Длина текущего набираемого слова
    private(set) var currentWordLength = 0
    /// Длина слова до последнего пробела
    private(set) var wordBeforeBoundaryLength = 0
    /// Сколько пробелов после слова (только пробелы, не enter/стрелки)
    private(set) var boundaryCount = 0
    /// Были ли реальные нажатия после последней конвертации?
    private(set) var keysTypedSinceConversion = true

    /// Нажатия набираемого слова — для движка перепечатки (без буфера обмена)
    private(set) var currentWordKeys: [TypedKey] = []
    /// Нажатия слова перед последней границей-пробелом
    private(set) var prevWordKeys: [TypedKey] = []
    /// issue #24: буфер ВСЕЙ строки (буквы + пробелы-сентинелы char==" ") для перепечатки строки
    /// в терминале, где нет OS-выделения. Любая пунктуация/структурная клавиша/сдвиг курсора
    /// (fullReset) очищает буфер → тогда «вся строка» откатывается на последнее слово.
    private(set) var lineKeys: [TypedKey] = []
    /// Фронтмост-приложение на момент границы слова — чтобы авто-путь не перепечатал
    /// в другое поле, если фокус уехал (Cmd-Tab/Spotlight) без клика/Tab.
    private(set) var prevWordBundleID: String?
    /// issue #7: взводится при смене раскладки → на первой букве играем звук раскладки.
    var soundArmed = false

    private var onAltTap: ((ManualConversionSnapshot) -> Void)?
    private var onAltReconvert: ((ManualConversionSnapshot) -> Void)?
    /// Авто-конвертация: вызывается (async) на границе слова, когда включён autoConvert.
    var onWordBoundary: ((WordBoundarySnapshot) -> Void)?
    private let inputLock = NSRecursiveLock()
    private var inputGeneration: UInt64 = 0
    /// Invalidated only when focus/caret/selection may have moved. Ordinary typing
    /// after a boundary keeps the context stable so AX replacement can target the
    /// captured word without touching newer input.
    private var textContextGeneration: UInt64 = 0
    /// Exact printable keystrokes after recent word boundaries. This lets a delayed
    /// correction preserve an empty suffix, punctuation, and later text without guessing
    /// from the current word buffer. The history is deliberately bounded.
    private var appendedInputEvents: [AppendedInputEvent] = []
    private var appendedInputDiscardedThroughGeneration: UInt64 = 0
    private let appendedInputHistoryLimit = 128
    private var workspaceActivationObserver: NSObjectProtocol?
    /// issue #10: любой ввод/клик пользователя — чтобы спрятать флаг у каретки во время печати.
    var onUserInput: (() -> Void)?
    /// issue #10: включена ли фича флага-у-каретки. Гейтит диспатч onUserInput на горячем пути,
    /// чтобы при выключенной фиче (по умолчанию) не будить main-очередь на каждом нажатии.
    var caretFlagEnabled = false

    // Конфиг триггера (кэш; обновляется в start/reconfigure)
    private var triggerConfig = TriggerConfig.current()
    /// issue #14: второй хоткей — чистое переключение раскладки (nil = выключен).
    private var switchConfig = TriggerConfig.switchHotkey()
    private var switchArmed = false
    private var switchPressTime: Date?
    private var switchLastTapTime: Date?   // для double-tap хоткея смены
    /// Колбэк чистого переключения раскладки (issue #14). Ставится из AppDelegate.
    var onSwitchHotkey: (() -> Void)?
    /// issue #29: третий хоткей — смена регистра (nil = выключен).
    private var caseConfig = TriggerConfig.caseHotkey()
    private var caseArmed = false
    private var casePressTime: Date?
    private var caseLastTapTime: Date?
    /// Колбэк смены регистра (issue #29). Ставится из AppDelegate.
    var onCaseHotkey: (() -> Void)?

    // Детект соло-тапа модификатора
    private var triggerArmed = false
    private var triggerPressTime: Date?
    // Для двойного тапа
    private var lastTapTime: Date?
    private let tapWindow: TimeInterval = 0.4
    // issue #21: окно «тапа» для КОМБО из двух модификаторов. Намеренно большое: аккорд
    // из двух клавиш держат заметно дольше флика одной (0.4с было слишком узко). Но верхний
    // потолок оставлен — иначе комбо срабатывало бы и на «случайное» долгое удержание
    // модификаторов во время скролла/жеста (эти события не сбрасывают armed — их нет в маске
    // event tap'а). 2с покрывает любой намеренный тап и отсекает попутные удержания.
    private let comboTapWindow: TimeInterval = 2.0

    func start(
        onAltTap: @escaping (ManualConversionSnapshot) -> Void,
        onAltReconvert: @escaping (ManualConversionSnapshot) -> Void
    ) -> Bool {
        self.onAltTap = onAltTap
        self.onAltReconvert = onAltReconvert

        let precheck = CGPreflightListenEventAccess()
        rslog("Preflight check = \(precheck)")
        if !precheck {
            rslog("Input Monitoring is not authorized; event tap will not be created")
            return false
        }
        observeApplicationActivation()

        triggerConfig = TriggerConfig.current()
        switchConfig = TriggerConfig.switchHotkey()
        caseConfig = TriggerConfig.caseHotkey()   // issue #29
        rslog("Attempting to create event tap... (trigger=\(SettingsManager.shared.triggerKey) switch=\(SettingsManager.shared.switchHotkey.isEmpty ? "off" : SettingsManager.shared.switchHotkey) capsLock=\(triggerConfig.isCapsLock))")
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        // Caps Lock требует активного tap (consume), чтобы подавить переключение
        // регистра. Для модификаторов оставляем listenOnly — не вмешиваемся в ввод.
        let options: CGEventTapOptions = triggerConfig.isCapsLock ? .defaultTap : .listenOnly

        // Режим удалённого стола: session-уровень видит проброшенные Screen Sharing
        // нажатия (они инжектятся через CGEventPost, а HID-tap их не видит).
        let tapLocation: CGEventTapLocation =
            SettingsManager.shared.remoteDesktopMode ? .cgSessionEventTap : .cghidEventTap
        rslog("Tap location: \(SettingsManager.shared.remoteDesktopMode ? "session (remote desktop)" : "hid")")

        guard let tap = CGEvent.tapCreate(
            tap: tapLocation,
            place: .tailAppendEventTap,
            options: options,
            eventsOfInterest: mask,
            callback: keyboardCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            rslog("FAILED to create event tap - no permission")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        rslog("Event tap created and enabled successfully")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func observeApplicationActivation() {
        guard workspaceActivationObserver == nil else { return }
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resetBuffersForApplicationActivation()
        }
    }

    /// Перезапускает tap с актуальным конфигом триггера. Нужен при смене настройки —
    /// особенно при переключении на/с Caps Lock, т.к. меняется режим tap (consume).
    @discardableResult
    func reconfigure() -> Bool {
        guard let t = onAltTap, let r = onAltReconvert else { return false }
        rslog("Reconfiguring trigger…")
        stop()
        return start(onAltTap: t, onAltReconvert: r)
    }

    func markConverted() {
        inputLock.lock()
        defer { inputLock.unlock() }
        clearConvertedBuffers()
        textContextGeneration &+= 1
    }

    /// Complete an older boundary replacement without discarding a newer word the
    /// user began typing while Accessibility was validating the captured field.
    @discardableResult
    func markConverted(boundaryInputGeneration expected: UInt64,
                       preservingTypedSuffixKeyCount suffixKeyCount: Int = 0) -> UInt64 {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputGeneration != expected else {
            clearConvertedBuffers()
            textContextGeneration &+= 1
            return textContextGeneration
        }

        wordBeforeBoundaryLength = 0
        boundaryCount = 0
        prevWordKeys = []
        prevWordBundleID = nil
        // Letters already reinserted by a boundary replacement belong to that same
        // conversion. A later physical key will set this back to true in handleKeyDown.
        keysTypedSinceConversion = currentWordLength > suffixKeyCount
        return textContextGeneration
    }

    func isInputGenerationCurrent(_ expected: UInt64) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        return inputGeneration == expected
    }

    var currentInputGeneration: UInt64 {
        inputLock.lock()
        defer { inputLock.unlock() }
        return inputGeneration
    }

    private func clearConvertedBuffers() {
        currentWordLength = 0
        wordBeforeBoundaryLength = 0
        boundaryCount = 0
        currentWordKeys = []
        prevWordKeys = []
        prevWordBundleID = nil
        lineKeys = []
        keysTypedSinceConversion = false
        clearAppendedInputHistory()
    }

    func isTextContextCurrent(_ expected: UInt64) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        return textContextGeneration == expected
    }

    /// An app switch invalidates the word snapshot even if macOS did not deliver a
    /// mouse or keyboard event through our tap (for example, a window was activated
    /// by another process). This also prevents a queued replacement crossing fields.
    func resetBuffersForApplicationActivation() {
        inputLock.lock()
        defer { inputLock.unlock() }
        inputGeneration &+= 1
        fullReset()
    }

    var currentTextContextGeneration: UInt64 {
        inputLock.lock()
        defer { inputLock.unlock() }
        return textContextGeneration
    }

    /// Drop input and pending hotkeys while an all-actions application is focused.
    func ignoreEventsForExcludedApp() {
        inputLock.lock()
        defer { inputLock.unlock() }
        triggerArmed = false; triggerPressTime = nil; lastTapTime = nil
        switchArmed = false; switchPressTime = nil; switchLastTapTime = nil
        caseArmed = false; casePressTime = nil; caseLastTapTime = nil
        keysTypedSinceConversion = true
        fullReset()
    }

    private func fullReset() {
        textContextGeneration &+= 1
        currentWordLength = 0
        wordBeforeBoundaryLength = 0
        boundaryCount = 0
        currentWordKeys = []
        prevWordKeys = []
        prevWordBundleID = nil
        lineKeys = []
        clearAppendedInputHistory()
    }

    private func clearAppendedInputHistory() {
        appendedInputEvents.removeAll(keepingCapacity: true)
        appendedInputDiscardedThroughGeneration = inputGeneration
    }

    private func recordAppendedInput(_ character: Character?, keyBufferRecoverable: Bool = true) {
        if appendedInputEvents.count >= appendedInputHistoryLimit {
            let removeCount = 32
            let removed = appendedInputEvents.prefix(removeCount)
            if let last = removed.last {
                appendedInputDiscardedThroughGeneration = last.generation
            }
            appendedInputEvents.removeFirst(removed.count)
        }
        appendedInputEvents.append(AppendedInputEvent(
            generation: inputGeneration,
            character: character,
            keyBufferRecoverable: keyBufferRecoverable
        ))
    }

    /// Literal punctuation and digits end token tracking, but they do not move the caret.
    /// Keep an earlier boundary snapshot valid so it can preserve this exact suffix.
    private func resetWordTrackingPreservingAppendHistory() {
        currentWordLength = 0
        wordBeforeBoundaryLength = 0
        boundaryCount = 0
        currentWordKeys = []
        prevWordKeys = []
        prevWordBundleID = nil
        lineKeys = []
        keysTypedSinceConversion = true
    }

    /// Context is useful only for a bounded recent suffix. Resetting at the limit keeps
    /// a long document from retaining every typed key for the lifetime of the line.
    private func appendLineKey(_ key: TypedKey) {
        if lineKeys.count >= 2048 { lineKeys.removeAll(keepingCapacity: true) }
        lineKeys.append(key)
    }

    /// After a verified replacement, keep the bounded in-memory line buffer aligned
    /// with what the user actually sees. Later language-transition decisions must use
    /// committed output (for example `руддщ` → `hello`), not stale physical key text.
    /// Only edits the captured prefix when the field generation and all key identities
    /// still match; unsupported length changes simply leave the context conservative.
    @discardableResult
    func reconcileVisibleLine(
        snapshot: WordBoundarySnapshot,
        range: Range<Int>,
        with visibleText: String
    ) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }

        guard textContextGeneration == snapshot.textContextGeneration,
              lineKeys.count >= snapshot.lineKeys.count,
              range.lowerBound >= 0,
              range.upperBound <= snapshot.lineKeys.count else { return false }

        let capturedPrefix = lineKeys.prefix(snapshot.lineKeys.count)
        let prefixIsUnchanged = zip(capturedPrefix, snapshot.lineKeys).allSatisfy { pair in
            let (current, captured) = pair
            return current.keyCode == captured.keyCode
                && current.shift == captured.shift
                && current.caps == captured.caps
                && current.char == captured.char
                && current.sourceLayoutID == captured.sourceLayoutID
        }
        guard prefixIsUnchanged else { return false }

        let characters = Array(visibleText)
        guard characters.count == range.count else { return false }
        for (offset, character) in characters.enumerated() {
            lineKeys[range.lowerBound + offset].char = character
        }
        return true
    }

    /// Keep internal hyphens inside a tracked token. The surrounding letters
    /// are required so ordinary punctuation never becomes a deletion/conversion range.
    /// A repeated hyphen stays in the same token, where the decision policy rejects it;
    /// resetting here could otherwise convert only the suffix after `--`.
    @discardableResult
    private func appendInternalHyphen(_ key: TypedKey) -> Bool {
        guard currentWordLength > 0,
              HyphenatedTokenPolicy.shouldTrackHyphen(after: currentWordKeys.last?.char) else { return false }
        recordAppendedInput(key.char)
        currentWordKeys.append(key)
        appendLineKey(key)
        currentWordLength += 1
        wordBeforeBoundaryLength = 0
        boundaryCount = 0
        prevWordKeys = []
        return true
    }

    /// Завершилось слово на пробеле — если включён autoConvert, дёргаем авто-путь
    /// (async, чтобы не блокировать доставку текущего события).
    private func fireWordBoundary() {
        guard SettingsManager.shared.autoConvert else { return }
        let cb = onWordBoundary
        let snapshot = WordBoundarySnapshot(
            keys: prevWordKeys,
            boundaryCount: boundaryCount,
            bundleIdentifier: prevWordBundleID,
            processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            inputGeneration: inputGeneration,
            textContextGeneration: textContextGeneration,
            lineKeys: lineKeys,
            languageSwitchWordThreshold: SettingsManager.shared.languageSwitchWordThreshold
        )
        DispatchQueue.main.async { cb?(snapshot) }
    }

    /// Holds input delivery while an automatic text replacement is being emitted.
    func performIfInputGenerationIsCurrent(_ expected: UInt64, operation: @Sendable () -> Void) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputGeneration == expected else { return false }
        operation()
        return true
    }

    /// Preserves exact printable text typed after the captured Space boundary. An
    /// empty suffix is valid; deletion, navigation, shortcuts, stale history, or
    /// unsupported composed input safely cancels the replacement.
    func performIfWordBoundaryIsCurrent(
        _ snapshot: WordBoundarySnapshot,
        operationID: String? = nil,
        operation: @Sendable (_ typedSuffix: String) -> Void
    ) -> String? {
        let lockRequestedAt = DispatchTime.now().uptimeNanoseconds
        inputLock.lock()
        let lockAcquiredAt = DispatchTime.now().uptimeNanoseconds

        guard textContextGeneration == snapshot.textContextGeneration else {
            inputLock.unlock()
            let operationTag = operationID.map { " op=\($0)" } ?? ""
            rslog("auto replacement cancelled:\(operationTag) reason=context-changed")
            return nil
        }
        let suffixEvents = appendedInputEvents.filter { $0.generation > snapshot.inputGeneration }
        let suffix: String? = suffixEvents.reduce(into: Optional(String())) { result, event in
            guard result != nil, let character = event.character else {
                result = nil
                return
            }
            result?.append(character)
        }
        let decision = AppendedInputPolicy.decide(
            generationDelta: inputGeneration &- snapshot.inputGeneration,
            trackedKeyCount: suffixEvents.count,
            suffix: suffix,
            historyAvailable: snapshot.inputGeneration >= appendedInputDiscardedThroughGeneration
        )
        let typedSuffix: String
        switch decision {
        case .preserve(let suffix):
            typedSuffix = suffix
        case .reject(let reason):
            let canRecoverFromKeyBuffer = reason == .missingCharacter
                || reason == .suffixCountMismatch
                || reason == .unsupportedCharacter
            guard canRecoverFromKeyBuffer,
                  snapshot.lineKeys.count <= lineKeys.count,
                  lineKeys.starts(with: snapshot.lineKeys) else {
                inputLock.unlock()
                let operationTag = operationID.map { " op=\($0)" } ?? ""
                rslog("auto replacement cancelled:\(operationTag) reason=\(reason.rawValue) key-buffer-prefix=unavailable")
                return nil
            }

            let suffixKeys = Array(lineKeys.dropFirst(snapshot.lineKeys.count))
            let recovered = DynamicKeyMapping.lineString(from: suffixKeys)
            guard AppendedInputPolicy.canPreserveRecoveredTypedSuffix(
                generationDelta: inputGeneration &- snapshot.inputGeneration,
                recoveredKeyCount: suffixKeys.count,
                suffix: recovered,
                capturedPrefixMatches: true,
                allKeyEventsAreRecoverable: suffixEvents.allSatisfy(\.keyBufferRecoverable)
            ), let recovered else {
                inputLock.unlock()
                let operationTag = operationID.map { " op=\($0)" } ?? ""
                rslog("auto replacement cancelled:\(operationTag) reason=\(reason.rawValue) key-buffer-recovery=unavailable")
                return nil
            }
            typedSuffix = recovered
            let operationTag = operationID.map { " op=\($0)" } ?? ""
            rslog("auto replacement suffix recovered:\(operationTag) reason=\(reason.rawValue) " +
                  "key-count=\(suffixKeys.count) character-count=\(recovered.count)")
        }

        operation(typedSuffix)
        let lockReleasedAt = DispatchTime.now().uptimeNanoseconds
        inputLock.unlock()
        let lockWaitMS = (lockAcquiredAt &- lockRequestedAt) / 1_000_000
        let lockHoldMS = (lockReleasedAt &- lockAcquiredAt) / 1_000_000
        if lockWaitMS >= 4 || lockHoldMS >= 4 {
            let operationTag = operationID.map { " op=\($0)" } ?? ""
            rslog("auto replacement lock timing:\(operationTag) wait-ms=\(lockWaitMS) hold-ms=\(lockHoldMS)")
        }
        return typedSuffix
    }

    /// Сброс буфера при клике мышью — иначе backspace перепечатки сотрёт не то
    /// (курсор мог уехать в другое место).
    fileprivate func resetBuffersOnClick() {
        inputLock.lock()
        defer { inputLock.unlock() }
        inputGeneration &+= 1
        triggerArmed = false
        switchArmed = false
        caseArmed = false; caseLastTapTime = nil   // issue #29
        lastTapTime = nil
        switchLastTapTime = nil
        keysTypedSinceConversion = true
        if caretFlagEnabled { DispatchQueue.main.async { [weak self] in self?.onUserInput?() } }   // issue #10: клик прячет флаг у каретки
        fullReset()
    }

    // MARK: - Event Handling

    fileprivate func handleKeyDown(
        keyCode: UInt16,
        flags: CGEventFlags,
        char: Character? = nil,
        suffixKeyBufferRecoverable: Bool = true,
        textEventRepresentable: Bool = true
    ) {
        inputLock.lock()
        defer { inputLock.unlock() }
        inputGeneration &+= 1
        triggerArmed = false
        switchArmed = false   // issue #14: клавиша между модификаторами = шорткат, не хоткей
        caseArmed = false; caseLastTapTime = nil   // issue #29
        lastTapTime = nil
        switchLastTapTime = nil
        keysTypedSinceConversion = true
        if caretFlagEnabled { DispatchQueue.main.async { [weak self] in self?.onUserInput?() } }   // issue #10: спрятать флаг при печати

        // The event tap tracks one grapheme per key. Input methods can commit
        // multiple/composed characters from a single event; physical keycodes do
        // not describe that text. Invalidate pending snapshots before any code can
        // auto-convert or later reconstruct this word from keycodes.
        guard textEventRepresentable else {
            if SettingsManager.shared.debugLogEnabled {
                rslog("input tracking reset: unrepresentable Unicode event")
            }
            fullReset()
            return
        }

        // Удалёнка: Screen Sharing шлёт проброшенные символы как keyCode 0 + юникод. Перехватываем
        // ТОЛЬКО в режиме удалённого стола. КРИТИЧНО: локально keyCode 0 — это обычная клавиша
        // 'a' (и 'ф' в ЙЦУКЕН), её нельзя глотать, иначе ломается локальная конверсия слов с
        // этими буквами. В локальном режиме сюда не заходим — буква идёт обычным путём ниже.
        if SettingsManager.shared.remoteDesktopMode, keyCode == 0 {
            // ⌘A/⌘C/⌘X и т.п. по удалёнке прилетают как символ 'a' (keyCode 0) с флагом Cmd.
            // НЕ копим их в буфер: иначе ⌘A добавляет лишнюю «ф» (keyCode 0 = 'ф' в ЙЦУКЕН)
            // и рушит выделение. Сбрасываем буфер — триггер уйдёт по clipboard-пути (выделение).
            // Локальный аналог этого guard — ниже, на ветке модификаторов (PR #13).
            let modifiers = flags.intersection([.maskCommand, .maskControl, .maskAlternate])
            if !modifiers.isEmpty { fullReset(); return }
            if let ch = char { handleForwardedChar(ch) }
            return
        }

        // Структурные клавиши обрабатываем ВСЕГДА, даже если в flags остался
        // «грязный» модификатор (stale .maskAlternate и т.п.) — иначе счётчик
        // слова не сбрасывается и конвертация захватывает лишние символы.

        // Пробел — единственная граница через которую можно вернуться
        if keyCode == KC.space {
            let disposition = SpaceShortcutPolicy.disposition(
                commandDown: flags.contains(.maskCommand),
                controlDown: flags.contains(.maskControl)
            )
            switch disposition {
            case .resetForShortcut:
                // ⌘Space opens Spotlight; discard the previous app's buffered word.
                fullReset()
                return
            case .preserveWordForLayoutSwitch:
                // Ctrl+Space changes the input source, but is not a delimiter. Keep
                // the captured characters and their per-key source layout intact.
                return
            case .wordBoundary:
                break
            }
            recordAppendedInput(" ")
            if currentWordLength > 0 {
                wordBeforeBoundaryLength = currentWordLength
                boundaryCount = 1
                prevWordKeys = currentWordKeys
                prevWordBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                if !lineKeys.isEmpty {
                    appendLineKey(TypedKey(keyCode: KC.space, shift: false, caps: false, char: " "))
                }
                fireWordBoundary()
            } else {
                boundaryCount += 1
                if !lineKeys.isEmpty {
                    appendLineKey(TypedKey(keyCode: KC.space, shift: false, caps: false, char: " "))
                }
            }
            currentWordLength = 0
            currentWordKeys = []
            return
        }

        // Enter, Tab — полный сброс
        if keyCode == KC.enter || keyCode == KC.tab {
            fullReset()
            return
        }

        // Стрелки (Left…Up) — полный сброс
        if keyCode >= KC.left && keyCode <= KC.up {
            fullReset()
            return
        }

        // Backspace
        if keyCode == KC.backspace {
            let disposition = KeyboardBufferEditPolicy.backspaceDisposition(
                command: flags.contains(.maskCommand),
                option: flags.contains(.maskAlternate),
                control: flags.contains(.maskControl)
            )
            switch disposition {
            case .removePreviousCharacter:
                if currentWordLength > 0 {
                    currentWordLength -= 1
                    if !currentWordKeys.isEmpty { currentWordKeys.removeLast() }
                    if !lineKeys.isEmpty { lineKeys.removeLast() }   // #24: синхронно с буфером строки
                } else {
                    fullReset()   // стирание через границу слова — буфер строки ненадёжен, сброс
                }
            case .invalidateTrackedText:
                // Option/Command/Control-Backspace can remove more than one character.
                // The event tap cannot infer the actual range, so never reuse a stale count.
                fullReset()
            }
            return
        }

        // (Cmd+A, Cmd+C, Cmd+X и т.п.) могло изменить выделение — сбрасываем наш буфер.
        let modifiers = flags.intersection([.maskCommand, .maskControl, .maskAlternate])
        if !modifiers.isEmpty {
            fullReset()
            return
        }

        if keyCode == KC.hyphen, !flags.contains(.maskShift), char == "-",
           appendInternalHyphen(TypedKey(
            keyCode: keyCode, shift: false, caps: flags.contains(.maskAlphaShift),
            char: char, sourceLayoutID: LayoutSwitcher.currentLayoutID()
           )) {
            return
        }

        // Digits are part of an alphanumeric token (for example, `chrono24`).
        // Keep their physical key in the same buffer so exact user rules can match
        // the whole token when the next word boundary arrives.
        if DynamicKeyMapping.isLetterKeycode(keyCode) || (char?.isNumber ?? false) {
            let tk = TypedKey(keyCode: keyCode, shift: flags.contains(.maskShift), caps: flags.contains(.maskAlphaShift),
                              char: char, sourceLayoutID: LayoutSwitcher.currentLayoutID())
            recordAppendedInput(char, keyBufferRecoverable: suffixKeyBufferRecoverable)
            currentWordKeys.append(tk)
            appendLineKey(tk)   // #24: символ токена в буфер строки
            currentWordLength += 1
            wordBeforeBoundaryLength = 0
            boundaryCount = 0
            prevWordKeys = []
            if DynamicKeyMapping.isLetterKeycode(keyCode) { playLayoutSoundIfArmed() }
        } else {
            // Literal punctuation should be preserved if an earlier conversion is
            // still pending. Unknown/control input remains a hard reset.
            if let char, AppendedInputPolicy.isSafePrintableCharacter(char) {
                recordAppendedInput(char, keyBufferRecoverable: suffixKeyBufferRecoverable)
                resetWordTrackingPreservingAppendHistory()
            } else {
                fullReset()
            }
        }
    }

    /// Обработка символа, проброшенного через удалённый стол (keyCode 0 + юникод).
    /// Работаем по самому символу: пробел — граница слова, backspace — откат,
    /// буква — кладём реальный символ в буфер (конверсия пойдёт по нему, см. convertKeys).
    private func handleForwardedChar(_ ch: Character) {
        // Пробел — граница слова (как локальный keyCode space)
        if ch == " " {
            recordAppendedInput(ch)
            if currentWordLength > 0 {
                wordBeforeBoundaryLength = currentWordLength
                boundaryCount = 1
                prevWordKeys = currentWordKeys
                prevWordBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                if !lineKeys.isEmpty {
                    appendLineKey(TypedKey(keyCode: KC.space, shift: false, caps: false, char: " "))
                }
                fireWordBoundary()
            } else {
                boundaryCount += 1
                if !lineKeys.isEmpty {
                    appendLineKey(TypedKey(keyCode: KC.space, shift: false, caps: false, char: " "))
                }
            }
            currentWordLength = 0
            currentWordKeys = []
            return
        }
        // Перенос строки / таб — полный сброс
        if ch == "\n" || ch == "\r" || ch == "\t" {
            fullReset()
            return
        }
        // Backspace / Delete — откат одной буквы
        if ch == "\u{8}" || ch == "\u{7f}" {
            if currentWordLength > 0 {
                currentWordLength -= 1
                if !currentWordKeys.isEmpty { currentWordKeys.removeLast() }
                if !lineKeys.isEmpty { lineKeys.removeLast() }   // #24
            } else {
                fullReset()
            }
            return
        }
        // Буква — кладём реальный символ (keyCode 0 = «проброшено»). shift несём из регистра.
        if ch == "-", appendInternalHyphen(TypedKey(
            keyCode: KC.hyphen, shift: false, caps: false, char: ch
        )) {
            return
        }
        if ch.isLetter || ch.isNumber {
            let tk = TypedKey(keyCode: 0, shift: ch.isUppercase, caps: false, char: ch)
            recordAppendedInput(ch)
            currentWordKeys.append(tk)
            appendLineKey(tk)   // #24
            currentWordLength += 1
            wordBeforeBoundaryLength = 0
            boundaryCount = 0
            prevWordKeys = []
            if ch.isLetter { playLayoutSoundIfArmed() }
            return
        }
        // Punctuation remains an exact suffix for any earlier pending conversion.
        // Controls and composed text are rejected.
        if AppendedInputPolicy.isSafePrintableCharacter(ch) {
            recordAppendedInput(ch)
            resetWordTrackingPreservingAppendHistory()
        } else {
            fullReset()
        }
    }

    /// issue #7: на первой букве после смены раскладки даём короткий звук, зависящий от
    /// раскладки — слышно, в какой раскладке начал печатать. Опц., по умолчанию выключено.
    private func playLayoutSoundIfArmed() {
        guard soundArmed, SettingsManager.shared.keySound,
              !AutoSwitchPolicy.areAllActionsDisabled(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else { return }
        soundArmed = false
        let sources = LayoutSwitcher.installedLayouts()
        let id1 = SettingsManager.shared.layout1ID.isEmpty
            ? LayoutSwitcher.autoDetectID1(from: sources) : SettingsManager.shared.layout1ID
        let name = LayoutSwitcher.currentLayoutID() == id1 ? "Tink" : "Pop"
        NSSound(named: name)?.play()
    }

    /// Возвращает true, если событие надо «съесть» (только Caps Lock в consume-режиме).
    fileprivate func handleFlagsChanged(flags: CGEventFlags, keyCode: UInt16) -> Bool {
        handleSwitchFlags(flags: flags, keyCode: keyCode)   // issue #14: второй хоткей
        handleCaseFlags(flags: flags, keyCode: keyCode)     // issue #29: третий хоткей (регистр)
        switch triggerConfig.kind {
        case .capsLock:
            guard keyCode == KC.capsLock else { return false }
            // Caps Lock шлёт одно событие на нажатие. Используем как тап и съедаем,
            // чтобы не переключался регистр.
            registerTap()
            return true

        case let .modifier(mask, left, right):
            let accepted: Set<UInt16> = triggerConfig.rightOnly ? [right] : [left, right]
            let allMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            let otherMods = allMods.subtracting(mask)

            if flags.contains(mask) {
                // нажатие: армим только если это нужная клавиша и нет других модификаторов
                if accepted.contains(keyCode) && flags.intersection(otherMods).isEmpty {
                    triggerArmed = true
                    triggerPressTime = Date()
                } else {
                    triggerArmed = false  // не та сторона / комбо
                }
            } else {
                // отпускание: соло-тап нужной клавиши, быстро и без клавиш между
                if triggerArmed, accepted.contains(keyCode), let t = triggerPressTime,
                   Date().timeIntervalSince(t) < tapWindow {
                    registerTap()
                }
                triggerArmed = false
                triggerPressTime = nil
            }
            return false

        case let .combo(maskA, maskB):
            let both: CGEventFlags = [maskA, maskB]
            let allMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            let others = allMods.subtracting(both)
            if !flags.intersection(others).isEmpty {
                triggerArmed = false                 // зажат посторонний модификатор — не наш триггер
            } else if flags.contains(both) {
                triggerArmed = true                  // ровно оба нужных, без посторонних → армим
                triggerPressTime = Date()
            } else if flags.intersection(allMods).isEmpty {
                // всё отпущено: комбо, если был армлен и без клавиш между (triggerArmed это
                // гарантирует). Окно расширено 0.4→2с (comboTapWindow, issue #21), но потолок
                // сохранён — не срабатывать на попутное удержание во время скролла/жеста.
                if triggerArmed, let t = triggerPressTime, Date().timeIntervalSince(t) < comboTapWindow {
                    registerTap()
                }
                triggerArmed = false
                triggerPressTime = nil
            }
            // частичное состояние (зажат один из двух) — ждём, ничего не трогаем
            return false
        }
    }

    /// issue #14: параллельная машина второго хоткея — чистое переключение раскладки.
    /// Зеркалит триггерную логику; Caps Lock не поддерживается, сторона (left/right) не
    /// различается, одиночный/двойной тап — как у триггера (switchDoubleTap). Разоружается
    /// на keyDown/клике вместе с триггером — Ctrl+Shift+P и подобные не переключают.
    private func handleSwitchFlags(flags: CGEventFlags, keyCode: UInt16) {
        guard let cfg = switchConfig else { return }
        let allMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        switch cfg.kind {
        case .capsLock:
            return
        case let .modifier(mask, left, right):
            let accepted: Set<UInt16> = cfg.rightOnly ? [right] : [left, right]
            let otherMods = allMods.subtracting(mask)
            if flags.contains(mask) {
                if accepted.contains(keyCode) && flags.intersection(otherMods).isEmpty {
                    switchArmed = true
                    switchPressTime = Date()
                } else {
                    switchArmed = false
                }
            } else {
                if switchArmed, accepted.contains(keyCode), let t = switchPressTime,
                   Date().timeIntervalSince(t) < tapWindow {
                    registerSwitchTap()
                }
                switchArmed = false
                switchPressTime = nil
            }
        case let .combo(maskA, maskB):
            let both: CGEventFlags = [maskA, maskB]
            let others = allMods.subtracting(both)
            if !flags.intersection(others).isEmpty {
                switchArmed = false
            } else if flags.contains(both) {
                switchArmed = true
                switchPressTime = Date()
            } else if flags.intersection(allMods).isEmpty {
                // issue #21: окно расширено 0.4→2с (comboTapWindow) — аккорд держат дольше
                // флика, но потолок оставлен, чтобы не срабатывать на попутное удержание
                // во время скролла/жеста (не сбрасывают switchArmed).
                if switchArmed, let t = switchPressTime, Date().timeIntervalSince(t) < comboTapWindow {
                    registerSwitchTap()
                }
                switchArmed = false
                switchPressTime = nil
            }
        }
    }

    /// Учитывает одиночный/двойной тап хоткея смены (зеркало registerTap).
    private func registerSwitchTap() {
        if switchConfig?.doubleTap == true {
            if let last = switchLastTapTime, Date().timeIntervalSince(last) < tapWindow {
                switchLastTapTime = nil
                fireSwitch()
            } else {
                switchLastTapTime = Date()  // ждём второй тап
            }
        } else {
            fireSwitch()
        }
    }

    private func fireSwitch() {
        rslog("switch hotkey: fire")
        DispatchQueue.main.async { [weak self] in self?.onSwitchHotkey?() }
    }

    /// issue #29: параллельная машина хоткея смены регистра — зеркало handleSwitchFlags.
    private func handleCaseFlags(flags: CGEventFlags, keyCode: UInt16) {
        guard let cfg = caseConfig else { return }
        let allMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        switch cfg.kind {
        case .capsLock:
            return
        case let .modifier(mask, left, right):
            let accepted: Set<UInt16> = cfg.rightOnly ? [right] : [left, right]
            let otherMods = allMods.subtracting(mask)
            if flags.contains(mask) {
                if accepted.contains(keyCode) && flags.intersection(otherMods).isEmpty {
                    caseArmed = true
                    casePressTime = Date()
                } else {
                    caseArmed = false
                }
            } else {
                if caseArmed, accepted.contains(keyCode), let t = casePressTime,
                   Date().timeIntervalSince(t) < tapWindow {
                    registerCaseTap()
                }
                caseArmed = false
                casePressTime = nil
            }
        case let .combo(maskA, maskB):
            let both: CGEventFlags = [maskA, maskB]
            let others = allMods.subtracting(both)
            if !flags.intersection(others).isEmpty {
                caseArmed = false
            } else if flags.contains(both) {
                caseArmed = true
                casePressTime = Date()
            } else if flags.intersection(allMods).isEmpty {
                if caseArmed, let t = casePressTime, Date().timeIntervalSince(t) < comboTapWindow {
                    registerCaseTap()
                }
                caseArmed = false
                casePressTime = nil
            }
        }
    }

    private func registerCaseTap() {
        if caseConfig?.doubleTap == true {
            if let last = caseLastTapTime, Date().timeIntervalSince(last) < tapWindow {
                caseLastTapTime = nil
                fireCase()
            } else {
                caseLastTapTime = Date()
            }
        } else {
            fireCase()
        }
    }

    private func fireCase() {
        rslog("case hotkey: fire")
        DispatchQueue.main.async { [weak self] in self?.onCaseHotkey?() }
    }

    /// Учитывает одиночный/двойной тап и запускает конвертацию.
    private func registerTap() {
        if triggerConfig.doubleTap {
            if let last = lastTapTime, Date().timeIntervalSince(last) < tapWindow {
                lastTapTime = nil
                fireConversion()
            } else {
                lastTapTime = Date()  // ждём второй тап
            }
        } else {
            fireConversion()
        }
    }

    private func fireConversion() {
        let snapshot: ManualConversionSnapshot
        inputLock.lock()
        let frontmost = NSWorkspace.shared.frontmostApplication
        snapshot = ManualConversionSnapshot(
            currentWordKeys: currentWordKeys,
            previousWordKeys: prevWordKeys,
            boundaryCount: boundaryCount,
            lineKeys: lineKeys,
            inputGeneration: inputGeneration,
            textContextGeneration: textContextGeneration,
            processIdentifier: frontmost?.processIdentifier,
            bundleIdentifier: frontmost?.bundleIdentifier
        )
        inputLock.unlock()

        if !keysTypedSinceConversion {
            rslog("trigger: RECONVERT")
            DispatchQueue.main.async { [weak self] in self?.onAltReconvert?(snapshot) }
        } else {
            rslog("trigger: CONVERT")
            DispatchQueue.main.async { [weak self] in self?.onAltTap?(snapshot) }
        }
    }
}

// MARK: - C Callback

private func keyboardCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Core Graphics owns the incoming event and documents returning that same event
    // without transferring ownership. passRetained here leaked one retain per key event.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo {
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    // Игнорируем собственные симулированные события по маркеру
    if event.getIntegerValueField(.eventSourceUserData) == kMultiSwitcherEventMarker {
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    // Secure fields must not enter the key buffer at all. Check before reading the
    // event's Unicode string so no typed characters can reach conversion or learning.
    if AutoSwitchPolicy.secureInputActive {
        monitor.ignoreEventsForExcludedApp()
        return Unmanaged.passUnretained(event)
    }

    if AutoSwitchPolicy.areAllActionsDisabled(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
        monitor.ignoreEventsForExcludedApp()
        return Unmanaged.passUnretained(event)
    }

    if type == .keyDown {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let remote = SettingsManager.shared.remoteDesktopMode
        // Удалёнка: игнорируем авто-повтор клавиш — латентность Screen Sharing рождает
        // ложные повторы (тот самый «фффффф»), засоряющие буфер конверсии.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0, remote {
            return Unmanaged.passUnretained(event)
        }
        // Сохраняем фактически введённый символ для локальной клавиатуры тоже.
        // Кейкод остаётся для перевода в соседнюю раскладку, символ — для точного оригинала.
        var unicodeText: String? = nil
        var unicodeBuffer = [UniChar](repeating: 0, count: 4)
        var unicodeLength = 0
        event.keyboardGetUnicodeString(
            maxStringLength: unicodeBuffer.count,
            actualStringLength: &unicodeLength,
            unicodeString: &unicodeBuffer
        )
        let unicodeWasTruncated = unicodeLength < 0 || unicodeLength > unicodeBuffer.count
        if unicodeLength > 0, !unicodeWasTruncated {
            unicodeText = String(utf16CodeUnits: unicodeBuffer, count: unicodeLength)
        }
        let disposition = AppendedInputPolicy.classifyUnicodeEvent(
            text: unicodeText,
            wasTruncated: unicodeWasTruncated
        )
        let forwardedChar: Character?
        switch disposition {
        case .keyCodeOnly:
            forwardedChar = nil
        case .character(let character):
            forwardedChar = character
            if remote, keyCode == 0, SettingsManager.shared.debugLogEnabled {
                // Privacy: never log the character or code point, only that the
                // remote keyboard supplied Unicode input.
                rslog("remote: forwarded char")
            }
        case .invalidate:
            // The event payload cannot be represented by one physical key. Clear
            // the tracked word and cancel pending conversions without editing text.
            monitor.handleKeyDown(
                keyCode: keyCode,
                flags: event.flags,
                suffixKeyBufferRecoverable: false,
                textEventRepresentable: false
            )
            return Unmanaged.passUnretained(event)
        }
        monitor.handleKeyDown(
            keyCode: keyCode,
            flags: event.flags,
            char: forwardedChar
        )
    } else if type == .flagsChanged {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if monitor.handleFlagsChanged(flags: event.flags, keyCode: keyCode) {
            return nil  // съедаем Caps Lock, чтобы не переключался регистр
        }
    } else if type == .leftMouseDown || type == .rightMouseDown {
        monitor.resetBuffersOnClick()
    }

    return Unmanaged.passUnretained(event)
}
