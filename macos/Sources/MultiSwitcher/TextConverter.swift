import AppKit
import ApplicationServices
import CoreGraphics
import MultiSwitcherCore

/// Конвертация текста между раскладками
@MainActor
final class TextConverter {
    private var lastConvertedCount = 0
    private var lastBoundaryCount = 0
    private var savedClipboardItems: [NSPasteboardItem]?
    private var savedClipboardChangeCount: Int?
    private var ownedClipboardChangeCount: Int?
    private var clipboardRestoreWork: DispatchWorkItem?
    private var isConverting = false
    private var pendingBufferReplacements: [PendingBufferReplacement] = []
    /// Очередь для инжекта нажатий буферного движка — чтобы usleep не блокировал
    /// main-поток, на котором висит event tap (иначе тап голодает → лаги/потери нажатий).
    nonisolated private let injectQueue = DispatchQueue(label: "com.ruswitcher.inject", qos: .userInteractive)

    // Состояние движка перепечатки (буфер нажатий → юникод-вставка)
    private var lastOriginal = ""
    private var lastConverted = ""
    private var lastWasBuffer = false
    private var bufferProcessIdentifier: pid_t?
    private(set) var lastConversionChangesLayout = false
    private(set) var lastConversionOperationID: String?
    private(set) var lastUndoneOperationID: String?
    private(set) var lastPreservedSuffixKeyCount = 0
    private var bufferIsCurrentlyConverted = false
    /// Последняя clipboard-конверсия содержала RTL — реконверт стрелками небезопасен.
    private var lastClipboardRTL = false

    private struct SpotlightUndo {
        let processID: pid_t
        let identity: CFHashCode
        let operationID: String
        var state: ExactTextUndoState
        let changesLayout: Bool
    }

    private struct PendingBufferReplacement: @unchecked Sendable {
        let original: String
        let converted: String
        let backspaceCount: Int
        let changesLayout: Bool
        let processIdentifier: pid_t?
        let performIfCurrent: @Sendable (@escaping @Sendable (String) -> Void) -> String?
        let completion: @MainActor @Sendable (Bool) -> Void
    }
    private var spotlightUndo: SpotlightUndo?
    private var safariUndo: SpotlightUndo?

    private struct VerifiedSelection {
        let processID: pid_t
        let element: AXUIElement
        let range: CFRange
        let text: String
    }

    /// RTL-скаляры: иврит, арабский + презентационные формы (копипаста из PDF).
    nonisolated static func containsRTL(_ s: String) -> Bool {
        s.unicodeScalars.contains {
            ($0.value >= 0x0590 && $0.value <= 0x06FF)
            || ($0.value >= 0xFB1D && $0.value <= 0xFDFF)
            || ($0.value >= 0xFE70 && $0.value <= 0xFEFF)
        }
    }

    /// NFC-нормализация перед вставкой — но НЕ для иврита/арабского: канонич. композиция
    /// может переставить/слить комбинирующие знаки (никуд/харакат), и число кодпоинтов
    /// разъедется со счётчиком Backspace/Shift-Left. Для RTL оставляем строку как есть.
    nonisolated static func normalizedForInsert(_ s: String) -> String {
        containsRTL(s) ? s : s.precomposedStringWithCanonicalMapping
    }

    /// Создаёт CGEventSource с маркером, чтобы KeyboardMonitor игнорировал наши события
    nonisolated private func makeSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = kMultiSwitcherEventMarker
        return source
    }

    /// Проверяет, что текущий фокусированный элемент — редактируемое текстовое поле
    private func isFocusedElementEditable() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // Занятое приложение (Electron в GC, IDE в индексации) без таймаута держит main
        // до 6с (дефолт AX) — это и есть «фризы». 0.2с хватает живому ответу; SpotlightAX
        // такой же таймаут уже ставит.
        AXUIElementSetMessagingTimeout(axApp, 0.2)

        var focusedRaw: AnyObject?
        let err = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRaw)
        guard err == .success, let focused = focusedRaw else {
            rslog("editable: no focused element")
            return false
        }

        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            rslog("editable: focused element is not an AXUIElement")
            return false
        }
        let element = focused as! AXUIElement

        // Проверяем роль
        var roleRaw: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRaw)
        let role = (roleRaw as? String) ?? ""

        // Текстовые роли
        let textRoles = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXWebArea"]
        if textRoles.contains(role) {
            // Дополнительно: не read-only?
            var editableRaw: AnyObject?
            let editErr = AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableRaw)
            // Если атрибут отсутствует — считаем editable (у AXWebArea его может не быть)
            if editErr == .success, let editable = editableRaw as? Bool {
                rslog("editable: role=\(role) editable=\(editable)")
                return editable
            }
            rslog("editable: role=\(role) (no AXEditable attr, assuming yes)")
            return true
        }

        rslog("editable: role=\(role) — not a text field")
        return false
    }

    // MARK: - Public API

    /// Движок перепечатки: стираем набранное и впечатываем конвертированное через
    /// юникод-вставку — без буфера обмена и без выделения (работает в Atom/Electron).
    /// Падает на clipboard-движок, если буфера нет (текст выделен мышью) или
    /// раскладки не определились.
    /// passthroughSuffix (issue #15): прилипшая к слову пунктуация — стирается вместе со
    /// словом и возвращается в поле как есть, БЕЗ кейкод-конверсии (',' EN ↔ 'б' RU).
    /// typedSuffix (issue #33): суффикс КАК НАБРАН, если passthroughSuffix уже
    /// сконвертирован («?»→«,» на Русской — ПК) — для честного отката реконвертом.
    /// Пустой typedSuffix означает «совпадает с passthroughSuffix».
    func convert(wordKeys: [TypedKey], prevWordKeys: [TypedKey], boundaryCount: Int,
                 passthroughSuffix: String = "", typedSuffix: String = "",
                 replacementOverride: String? = nil, changesLayout: Bool = true,
                 performIfCurrent: @escaping @Sendable (@escaping @Sendable () -> Void) -> Bool,
                 completion: @escaping @MainActor @Sendable (Bool) -> Void) -> Bool {
        let keys: [TypedKey]
        let trailingSpaces: Int
        if !wordKeys.isEmpty {
            keys = wordKeys; trailingSpaces = 0
        } else if !prevWordKeys.isEmpty && boundaryCount > 0 {
            keys = prevWordKeys; trailingSpaces = boundaryCount
        } else {
            // нет буфера — возможно, выделен мышью старый текст: пусть решает clipboard
            let completed = convertViaClipboard(wordLength: 0, prevWordLength: 0, boundaryCount: 0)
            completion(completed)
            return completed
        }

        guard let pair = DynamicKeyMapping.convertKeys(keys) else {
            // A rule replacement cannot safely fall through to a clipboard conversion.
            if replacementOverride != nil { return false }
            // Clipboard-путь про суффикс не знает (селекция посчиталась бы неверно) —
            // точность важнее полноты: с суффиксом тихо отказываемся.
            guard passthroughSuffix.isEmpty else {
                rslog("buffer convert: suffix + unresolved layouts — bail")
                return false
            }
            rslog("buffer convert: layouts not resolved — fallback to clipboard")
            let completed = convertViaClipboard(wordLength: wordKeys.count, prevWordLength: prevWordKeys.count,
                                                boundaryCount: boundaryCount)
            completion(completed)
            return completed
        }

        guard !isConverting else { return false }
        isConverting = true

        let spaces = String(repeating: " ", count: trailingSpaces)
        let bsCount = keys.count + passthroughSuffix.count + trailingSpaces
        // issue #33 (скептик, HIGH): в lastOriginal — суффикс КАК НАБРАН, иначе реконверт
        // после «tkrb?»→«елки,» восстанавливал бы «tkrb,» вместо «tkrb?».
        let originalSuffix = typedSuffix.isEmpty ? passthroughSuffix : typedSuffix
        let targetWord = replacementOverride ?? pair.converted
        guard !targetWord.isEmpty else { isConverting = false; return false }
        let insert = targetWord + passthroughSuffix + spaces
        lastOriginal = pair.original + originalSuffix + spaces
        lastConverted = targetWord + passthroughSuffix + spaces
        lastConversionOperationID = UUID().uuidString
        lastUndoneOperationID = nil
        bufferIsCurrentlyConverted = true
        bufferProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
        lastWasBuffer = true
        lastConversionChangesLayout = changesLayout
        rslog("buffer convert: \(keys.count) keys (+\(passthroughSuffix.count) punct, +\(trailingSpaces) sp)")

        // Инжект — вне main, чтобы usleep не голодал event tap.
        injectQueue.async { [weak self] in
            guard let self else { return }
            let committed = performIfCurrent {
                self.backspace(bsCount)
                usleep(20_000)  // дать целевому приложению обработать удаление до Unicode-вставки
                self.insertText(insert)
            }
            Task { @MainActor in
                self.isConverting = false
                if !committed { self.clearState() }
                completion(committed)
            }
        }
        return true
    }

    /// issue #24: конвертировать всю набранную строку (от курсора до начала строки) без
    /// выделения мышью. Сами выделяем Shift+Cmd+← и прогоняем через путь выделения (умная
    /// конверсия починит только слова не в той раскладке, верные — оставит). При no-op/сбое
    /// снимаем выделение (иначе строка осталась бы подсвеченной). Реконверт восстановит через
    /// сохранённый оригинал (см. convertViaClipboard/reconvertViaClipboard).
    func convertLine() -> Bool {
        guard !isConverting else { return false }
        // Скептик 3.2.0: не шлём Shift+Cmd+← вне текстового поля — иначе аккорд сработает как
        // ярлык приложения (напр. выделит не то). В поле — работаем.
        guard isFocusedElementEditable() else { rslog("convertLine: non-editable focus — bail"); return false }

        // Выделяем до начала строки влево (обычный LTR). Проверяем через AX, реально ли что-то
        // выделилось: только тогда конвертим и (при no-op) безопасно снимаем стрелкой.
        simKey(keyCode: KC.left, flags: [.maskShift, .maskCommand])
        usleep(60_000)
        if !focusedSelectionIsEmpty() {
            let ok = convertViaClipboard(wordLength: 0, prevWordLength: 0, boundaryCount: 0,
                                         allowUnrecognizedSingleWord: false)
            if !ok { simKey(keyCode: KC.right, flags: []) }   // снять выделение (оно есть — стрелка не двигает каретку лишнего)
            return ok
        }

        // issue #26: влево выделилось ПУСТО → RTL-веб-поле (адресная строка Chrome, WhatsApp Web),
        // где начало строки справа. Пробуем вправо. Стрелку-collapse влево НЕ жали — каретка на месте,
        // так что первый символ не теряется. Пробуем другую сторону ТОЛЬКО при пустом влево — значит
        // LTR-строку «вперёд» мы не трогаем (нет переписывания верного текста, скептик #26).
        simKey(keyCode: KC.right, flags: [.maskShift, .maskCommand])
        usleep(60_000)
        if !focusedSelectionIsEmpty() {
            let ok = convertViaClipboard(wordLength: 0, prevWordLength: 0, boundaryCount: 0,
                                         allowUnrecognizedSingleWord: false)
            if !ok { simKey(keyCode: KC.left, flags: []) }
            return ok
        }
        return false   // пусто в обе стороны — пустая строка; каретка не двигалась
    }

    /// true — текущее выделение фокус-элемента ПУСТО (по AX). На любой неопределённости (нет фокуса,
    /// атрибут недоступен) возвращаем false = «выделение есть» — безопасно для LTR: не пробуем вторую
    /// сторону и не переписываем текст «вперёд». RTL-фикс сработает лишь там, где AX надёжно отдаёт пусто.
    private func focusedSelectionIsEmpty() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        var focusedRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRaw) == .success,
              let focused = focusedRaw else { return false }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = focused as! AXUIElement
        var selRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selRaw) == .success,
              let sel = selRaw as? String else { return false }
        return sel.isEmpty
    }

    /// One policy for every selected-text path, including Spotlight and the clipboard
    /// fallback. The forced last-word Option path remains a direct layout flip.
    private func convertSelectionText(_ text: String, allowUnrecognizedSingleWord: Bool = false) -> String {
        let settings = SettingsManager.shared
        if settings.smartConversion {
            return SmartConvert.selection(text, allowUnrecognizedSingleWord: allowUnrecognizedSingleWord)
        }
        if settings.convertByText { return DynamicKeyMapping.convertBidirectional(text) }
        return DynamicKeyMapping.convert(text)
    }

    /// Read only the selected text, never the full document or surrounding chat.
    /// A copied current line is not evidence that a user selected it.
    private func verifiedSelection() -> VerifiedSelection? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.15)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        var subrole: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard (subrole as? String) != kAXSecureTextFieldSubrole else { return nil }
        var selected: AnyObject?
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String, !text.isEmpty,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        let value = rangeValue as! AXValue
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range),
              range.location >= 0, range.location != kCFNotFound,
              range.length > 0, range.length == text.utf16.count else { return nil }
        return VerifiedSelection(processID: app.processIdentifier, element: element, range: range, text: text)
    }

    private func selectionIsCurrent(_ snapshot: VerifiedSelection) -> Bool {
        guard let current = verifiedSelection() else { return false }
        return current.processID == snapshot.processID && CFEqual(current.element, snapshot.element)
            && current.range.location == snapshot.range.location && current.range.length == snapshot.range.length
            && current.text == snapshot.text
    }

    /// issue #24 (терминал): конвертирует всю набранную строку по БУФЕРУ нажатий — backspace на
    /// длину строки + перепечатка сконвертированного. Без OS-выделения (работает в терминалах и
    /// для иврита). Только для свежей непрерывной строки (буфер сбрасывается на пунктуации/Enter/
    /// сдвиге курсора → вызывающий откатывается на последнее слово). Реконверт — через lastOriginal.
    func convertLineBuffer(
        _ lineKeys: [TypedKey],
        performIfCurrent: @escaping @Sendable (@escaping @Sendable () -> Void) -> Bool,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> Bool {
        guard !isConverting, !lineKeys.isEmpty else { return false }
        guard let original = DynamicKeyMapping.lineString(from: lineKeys), !original.isEmpty else { return false }
        let converted = convertSelectionText(original)
        guard converted != original else { return false }   // строка уже верная — no-op
        isConverting = true
        lastWasBuffer = true
        lastOriginal = original
        lastConverted = converted
        lastConversionOperationID = UUID().uuidString
        lastUndoneOperationID = nil
        bufferIsCurrentlyConverted = true
        bufferProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
        lastConversionChangesLayout = true
        let bsCount = original.count
        rslog("line convert (terminal buffer): \(original.count)→\(converted.count) chars")
        injectQueue.async { [weak self] in
            guard let self else { return }
            let committed = performIfCurrent {
                self.backspace(bsCount)
                usleep(20_000)  // дать целевому приложению обработать удаление до Unicode-вставки
                self.insertText(converted)
            }
            Task { @MainActor in
                self.isConverting = false
                if !committed { self.clearState() }
                completion(committed)
            }
        }
        return true
    }

    // MARK: - issue #29: смена регистра (как Alt+Break в Punto)

    private var caseWord: String?   // слово/строка, по которой сейчас циклим регистр (буферный путь)
    private var caseIndex = 0
    private var caseOnScreen = ""   // ТЕКУЩИЙ экранный текст цикла — его длину и стираем (не original.count:
                                    // регистр не всегда сохраняет длину, напр. немецкое ß→SS, скептик #29)

    /// Общий движок цикла регистра по буферу (слово или строка). original — как набрано. Стирает
    /// реальную экранную длину и пропускает варианты, не дающие видимого изменения (односимвольные
    /// слова, каузлес-скрипты вроде иврита → просто no-op вместо мигания). Возвращает true при инжекте.
    private func cycleCaseByBuffer(_ original: String) -> Bool {
        if original != caseWord {
            caseWord = original
            caseIndex = TextConverter.caseVariant(original, 0) == original ? 1 : 0
            caseOnScreen = original                       // на экране — набранный оригинал
        } else {
            caseIndex = (caseIndex + 1) % 3
        }
        // Пропускаем варианты, совпадающие с тем, что уже на экране (иначе мёртвый тап / миганиe).
        var idx = caseIndex, changed = TextConverter.caseVariant(original, idx), tries = 0
        while changed == caseOnScreen && tries < 3 {
            idx = (idx + 1) % 3; changed = TextConverter.caseVariant(original, idx); tries += 1
        }
        guard changed != caseOnScreen else { return false }   // все варианты равны (иврит и т.п.) → пропуск
        let finalChanged = changed
        caseIndex = idx
        let bs = caseOnScreen.count                           // стираем РЕАЛЬНУЮ экранную длину
        caseOnScreen = changed
        isConverting = true
        rslog("case: buffer \(original.count) chars → variant \(idx), bs \(bs)")
        injectQueue.async { [weak self] in
            guard let self else { return }
            self.backspace(bs)
            usleep(20_000)
            self.insertText(finalChanged)
            Task { @MainActor in self.isConverting = false }
        }
        return true
    }

    /// Вариант регистра по индексу цикла: 0 — ВЕРХНИЙ, 1 — нижний, 2 — Заглавный (Title).
    private static func caseVariant(_ s: String, _ i: Int) -> String {
        switch ((i % 3) + 3) % 3 {
        case 0:  return s.uppercased()
        case 1:  return s.lowercased()
        default: return s.capitalized
        }
    }

    /// Сменить регистр последнего набранного слова (буфер) или выделения (clipboard). Раскладку
    /// НЕ трогает. По повторным нажатиям на то же слово циклит ВЕРХНИЙ → нижний → Заглавный.
    func changeCase(wordKeys: [TypedKey]) -> Bool {
        guard !isConverting else { return false }
        if !wordKeys.isEmpty { return changeCaseWord(wordKeys) }
        return changeCaseSelection()
    }

    private func changeCaseWord(_ keys: [TypedKey]) -> Bool {
        guard let pair = DynamicKeyMapping.convertKeys(keys),
              !pair.original.isEmpty, pair.original.contains(where: { $0.isLetter }) else { return false }
        return cycleCaseByBuffer(pair.original)
    }

    private func changeCaseSelection() -> Bool {
        caseWord = nil   // выделение сбрасывает буферный цикл
        let pasteboard = NSPasteboard.general
        cancelClipboardRestore()
        captureClipboardSnapshotIfNeeded(pasteboard)
        isConverting = true
        var ok = false
        defer { if !ok { restoreClipboardNow() }; isConverting = false }

        guard let text = tryCopy(pasteboard), !text.isEmpty,
              text.contains(where: { $0.isLetter }) else { return false }
        let changed = TextConverter.nextCaseFromCurrent(text)
        guard changed != text else { return false }
        pasteText(changed, pasteboard: pasteboard)
        // Скептик #29: НЕ выставляем reconvert-состояние (lastConverted/lastConvertedCount) — смена
        // регистра не должна попадать в путь реконверта (см. clearState() в onCaseHotkey).
        ok = true
        scheduleClipboardRestore()
        return true
    }

    /// Для выделения (без состояния): следующий регистр из текущего — нижний→ВЕРХНИЙ→Заглавный→нижний.
    private static func nextCaseFromCurrent(_ s: String) -> String {
        let letters = s.filter { $0.isLetter }
        if letters.allSatisfy({ $0.isLowercase }) { return s.uppercased() }
        if letters.allSatisfy({ $0.isUppercase }) {
            let cap = s.capitalized
            return cap == s ? s.lowercased() : cap   // односимвольные слова: capitalized==s → идём в нижний
        }
        return s.lowercased()
    }

    /// issue #29: смена регистра ВСЕЙ строки (когда включён «Convert whole line»). Обычные
    /// приложения — тем же AX-гейтом выделения строки, что и convertLine (#26). Повторные тапы
    /// циклят регистр: changeCaseSelection перечитывает текущую строку → nextCaseFromCurrent.
    func changeCaseLine() -> Bool {
        guard !isConverting else { return false }
        guard isFocusedElementEditable() else { rslog("changeCaseLine: non-editable — bail"); return false }
        simKey(keyCode: KC.left, flags: [.maskShift, .maskCommand]); usleep(60_000)
        if !focusedSelectionIsEmpty() {
            let ok = changeCaseSelection()
            if !ok { simKey(keyCode: KC.right, flags: []) }
            return ok
        }
        simKey(keyCode: KC.right, flags: [.maskShift, .maskCommand]); usleep(60_000)   // RTL: начало строки справа
        if !focusedSelectionIsEmpty() {
            let ok = changeCaseSelection()
            if !ok { simKey(keyCode: KC.left, flags: []) }
            return ok
        }
        return false
    }

    /// issue #29 (терминал): смена регистра всей строки по БУФЕРУ нажатий (нет OS-выделения).
    /// Циклит регистр как changeCaseWord, ключ — строка целиком (буфер живёт между тапами).
    func changeCaseLineBuffer(_ lineKeys: [TypedKey]) -> Bool {
        guard !isConverting, !lineKeys.isEmpty,
              let original = DynamicKeyMapping.lineString(from: lineKeys),
              !original.isEmpty, original.contains(where: { $0.isLetter }) else { return false }
        return cycleCaseByBuffer(original)
    }

    /// Replaces only the selected span or final word in Spotlight using AX.
    /// The next Option restores the exact full query and selection if the field is unchanged.
    func convertSpotlight() -> Bool {
        guard !isConverting else { return false }
        guard case .active(let field) = SpotlightAX.inspect() else {
            rslog("spotlight: not confidently editable; skipped")
            spotlightUndo = nil
            return false
        }

        if var undo = spotlightUndo,
           undo.processID == field.processID,
           undo.identity == field.identity {
            var nextState = undo.state
            if let step = nextState.toggle(currentText: field.value, currentSelection: field.selection) {
                guard SpotlightAX.replace(target: field, expectedValue: field.value,
                                          with: step.text, selection: step.selection) else {
                    spotlightUndo = nil
                    return false
                }
                undo.state = nextState
                spotlightUndo = undo
                lastConversionOperationID = undo.operationID
                lastUndoneOperationID = step.isConverted ? nil : undo.operationID
                lastOriginal = step.isConverted ? nextState.originalText : nextState.convertedText
                lastConverted = step.isConverted ? nextState.convertedText : nextState.originalText
                lastConversionChangesLayout = undo.changesLayout
                lastConvertedCount = 0
                lastBoundaryCount = 0
                return true
            }
        }

        spotlightUndo = nil
        guard let plan = TextReplacementPlanner.plan(text: field.value, selection: field.selection) else {
            return false
        }
        let source = (field.value as NSString).substring(with: plan.range)
        let convertedSource = field.selection.length > 0 ? convertSelectionText(source, allowUnrecognizedSingleWord: true)
                                                         : DynamicKeyMapping.convert(source)
        let converted = TextConverter.normalizedForInsert(convertedSource)
        guard !source.isEmpty, converted != source,
              let replacement = TextReplacementPlanner.replacing(text: field.value, plan: plan,
                                                                 with: converted) else { return false }
        let convertedSelection = TextReplacementPlanner.selectionAfterReplacement(
            plan: plan, replacement: converted)
        guard SpotlightAX.replace(target: field, expectedValue: field.value, with: replacement,
                                  selection: convertedSelection) else { return false }

        let operationID = UUID().uuidString
        spotlightUndo = SpotlightUndo(
            processID: field.processID,
            identity: field.identity,
            operationID: operationID,
            state: ExactTextUndoState(
                originalText: field.value,
                convertedText: replacement,
                originalSelection: field.selection,
                convertedSelection: convertedSelection
            ),
            changesLayout: true
        )
        lastOriginal = field.value
        lastConverted = replacement
        lastConversionOperationID = operationID
        lastUndoneOperationID = nil
        lastConvertedCount = 0
        lastBoundaryCount = 0
        lastWasBuffer = false
        lastConversionChangesLayout = true
        return true
    }

    /// Automatic Spotlight replacement uses the same exact-range AX transaction.
    /// Autocomplete selections and stale typed words are skipped.
    func convertSpotlightWord(original: String, converted: String, boundaryCount: Int = 1,
                              changesLayout: Bool = true) -> Bool {
        guard !isConverting else { rslog("spotlight-auto: bail conversion-busy"); return false }
        guard !original.isEmpty, !converted.isEmpty else {
            rslog("spotlight-auto: bail empty-word")
            return false
        }
        let detection = SpotlightAX.inspect()
        let field: SpotlightAX.Field
        switch detection {
        case .active(let activeField): field = activeField
        case .inactive:
            rslog("spotlight-auto: bail field-inactive")
            return false
        case .uncertain:
            rslog("spotlight-auto: bail field-uncertain")
            return false
        }
        guard field.selection.length == 0 else {
            rslog("spotlight-auto: bail nonempty-selection")
            return false
        }
        guard let plan = TextReplacementPlanner.planCapturedToken(
            text: field.value,
            selection: field.selection,
            token: original,
            boundaryCount: boundaryCount
        ) else {
            rslog("spotlight-auto: bail captured-word-not-found")
            return false
        }
        guard let replacement = TextReplacementPlanner.replacing(text: field.value, plan: plan,
                                                                  with: converted) else {
            rslog("spotlight-auto: bail replacement-plan")
            return false
        }
        let convertedSelection = TextReplacementPlanner.selectionAfterReplacement(
            plan: plan, replacement: converted)
        guard SpotlightAX.replace(target: field, expectedValue: field.value, with: replacement,
                                  selection: convertedSelection) else {
            rslog("spotlight-auto: bail ax-transaction")
            return false
        }

        let operationID = UUID().uuidString
        spotlightUndo = SpotlightUndo(
            processID: field.processID,
            identity: field.identity,
            operationID: operationID,
            state: ExactTextUndoState(
                originalText: field.value,
                convertedText: replacement,
                originalSelection: field.selection,
                convertedSelection: convertedSelection
            ),
            changesLayout: changesLayout
        )
        lastOriginal = field.value
        lastConverted = replacement
        lastConversionOperationID = operationID
        lastUndoneOperationID = nil
        lastConvertedCount = 0
        lastBoundaryCount = 0
        lastWasBuffer = false
        lastConversionChangesLayout = changesLayout
        return true
    }

    /// Replaces the captured context suffix, preserving text entered after its boundary.
    /// AX must still report the same field and a collapsed caret before the transaction commits.
    func convertSpotlightSuffix(originalSuffix: String, convertedSuffix: String,
                                changesLayout: Bool = true) -> Bool {
        guard !isConverting, !originalSuffix.isEmpty, !convertedSuffix.isEmpty,
              case .active(let field) = SpotlightAX.inspect(),
              field.selection.length == 0,
              let plan = TextReplacementPlanner.planCapturedSuffix(
                text: field.value, selection: field.selection, suffix: originalSuffix
              ),
              let replacement = TextReplacementPlanner.replacing(
                text: field.value, plan: plan, with: convertedSuffix
              ) else { return false }

        let convertedSelection = TextReplacementPlanner.selectionAfterReplacement(
            plan: plan, replacement: convertedSuffix
        )
        guard SpotlightAX.replace(target: field, expectedValue: field.value,
                                  with: replacement, selection: convertedSelection) else { return false }
        let operationID = UUID().uuidString
        spotlightUndo = SpotlightUndo(
            processID: field.processID,
            identity: field.identity,
            operationID: operationID,
            state: ExactTextUndoState(
                originalText: field.value,
                convertedText: replacement,
                originalSelection: field.selection,
                convertedSelection: convertedSelection
            ),
            changesLayout: changesLayout
        )
        lastOriginal = field.value
        lastConverted = replacement
        lastConversionOperationID = operationID
        lastUndoneOperationID = nil
        lastWasBuffer = false
        lastConvertedCount = 0
        lastBoundaryCount = 0
        lastConversionChangesLayout = changesLayout
        return true
    }

    /// Safari's address/search field has a stable Accessibility identifier. Use its
    /// value and selected range directly so browser autocomplete cannot consume a
    /// synthetic Backspace or leave the first character behind.
    func convertSafariAddressBar() -> Bool {
        guard !isConverting else { return false }
        guard case .active(let field) = SafariAddressBarAX.inspect() else {
            safariUndo = nil
            return false
        }

        if var undo = safariUndo,
           undo.processID == field.processID, undo.identity == field.identity {
            var nextState = undo.state
            if let step = nextState.toggle(currentText: field.value, currentSelection: field.selection) {
                guard SafariAddressBarAX.replace(target: field, expectedValue: field.value,
                                                 with: step.text, selection: step.selection) else {
                    safariUndo = nil
                    return false
                }
                undo.state = nextState
                safariUndo = undo
                lastConversionOperationID = undo.operationID
                lastUndoneOperationID = step.isConverted ? nil : undo.operationID
                lastOriginal = step.isConverted ? nextState.originalText : nextState.convertedText
                lastConverted = step.isConverted ? nextState.convertedText : nextState.originalText
                lastConversionChangesLayout = undo.changesLayout
                lastConvertedCount = 0
                lastBoundaryCount = 0
                return true
            }
        }

        safariUndo = nil
        guard let plan = TextReplacementPlanner.plan(text: field.value, selection: field.selection) else {
            return false
        }
        let source = (field.value as NSString).substring(with: plan.range)
        let convertedSource = field.selection.length > 0 ? convertSelectionText(source, allowUnrecognizedSingleWord: true)
                                                         : DynamicKeyMapping.convert(source)
        let converted = TextConverter.normalizedForInsert(convertedSource)
        guard !source.isEmpty, converted != source,
              let replacement = TextReplacementPlanner.replacing(text: field.value, plan: plan,
                                                                 with: converted) else { return false }
        let convertedSelection = TextReplacementPlanner.selectionAfterReplacement(
            plan: plan, replacement: converted)
        guard SafariAddressBarAX.replace(target: field, expectedValue: field.value,
                                         with: replacement, selection: convertedSelection) else { return false }
        storeSafariUndo(field: field, replacement: replacement, selection: convertedSelection,
                        changesLayout: true)
        return true
    }

    /// Automatic correction of the word at Safari's caret. The captured keystroke
    /// word must still match exactly; stale autocomplete or moved-caret states are skipped.
    func convertSafariAddressBarWord(original: String, converted: String, boundaryCount: Int = 1,
                                     changesLayout: Bool = true) -> Bool {
        guard !isConverting, !original.isEmpty, !converted.isEmpty,
              case .active(let field) = SafariAddressBarAX.inspect(), field.selection.length == 0,
              let plan = TextReplacementPlanner.planCapturedToken(
                text: field.value, selection: field.selection, token: original,
                boundaryCount: boundaryCount
              ),
              let replacement = TextReplacementPlanner.replacing(text: field.value, plan: plan,
                                                                 with: converted) else { return false }
        let selection = TextReplacementPlanner.selectionAfterReplacement(plan: plan, replacement: converted)
        guard SafariAddressBarAX.replace(target: field, expectedValue: field.value,
                                         with: replacement, selection: selection) else { return false }
        storeSafariUndo(field: field, replacement: replacement, selection: selection,
                        changesLayout: changesLayout)
        return true
    }

    /// Contextual short-word correction may arrive after more typing. Replace only the
    /// exact captured suffix and preserve the newer text and caret position.
    func convertSafariAddressBarSuffix(originalSuffix: String, convertedSuffix: String,
                                       changesLayout: Bool = true) -> Bool {
        guard !isConverting, !originalSuffix.isEmpty, !convertedSuffix.isEmpty,
              case .active(let field) = SafariAddressBarAX.inspect(), field.selection.length == 0,
              let plan = TextReplacementPlanner.planCapturedSuffix(
                text: field.value, selection: field.selection, suffix: originalSuffix
              ),
              let replacement = TextReplacementPlanner.replacing(text: field.value, plan: plan,
                                                                 with: convertedSuffix) else { return false }
        let selection = TextReplacementPlanner.selectionAfterReplacement(plan: plan,
                                                                          replacement: convertedSuffix)
        guard SafariAddressBarAX.replace(target: field, expectedValue: field.value,
                                         with: replacement, selection: selection) else { return false }
        storeSafariUndo(field: field, replacement: replacement, selection: selection,
                        changesLayout: changesLayout)
        return true
    }

    private func storeSafariUndo(field: SafariAddressBarAX.Field, replacement: String,
                                 selection: NSRange, changesLayout: Bool) {
        let operationID = UUID().uuidString
        safariUndo = SpotlightUndo(
            processID: field.processID,
            identity: field.identity,
            operationID: operationID,
            state: ExactTextUndoState(originalText: field.value, convertedText: replacement,
                                      originalSelection: field.selection, convertedSelection: selection),
            changesLayout: changesLayout
        )
        lastOriginal = field.value
        lastConverted = replacement
        lastConversionOperationID = operationID
        lastUndoneOperationID = nil
        lastConvertedCount = 0
        lastBoundaryCount = 0
        lastWasBuffer = false
        lastConversionChangesLayout = changesLayout
    }

    /// Performs a buffer replacement only if the input generation captured at the word
    /// boundary is still current. The callback holds the event-tap input lock around the edit.
    func replaceBufferText(
        original: String,
        converted: String,
        backspaceCount: Int,
        changesLayout: Bool,
        performIfCurrent: @escaping @Sendable (@escaping @Sendable () -> Void) -> Bool,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> Bool {
        guard !original.isEmpty, !converted.isEmpty,
              original != converted, backspaceCount > 0 else {
            rslog("buffer replacement unavailable: invalid replacement request")
            return false
        }
        guard pendingBufferReplacements.count < 8 else {
            rslog("buffer replacement queue full; request refused")
            return false
        }
        pendingBufferReplacements.append(PendingBufferReplacement(
            original: original,
            converted: converted,
            backspaceCount: backspaceCount,
            changesLayout: changesLayout,
            processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            performIfCurrent: { operation in
                performIfCurrent { operation("") } ? "" : nil
            },
            completion: completion
        ))
        processNextBufferReplacement()
        return true
    }

    /// Automatic correction variant that preserves letters typed after the captured
    /// space while the replacement waits in the main/injection queues.
    func replaceBufferTextPreservingTypedSuffix(
        original: String,
        converted: String,
        backspaceCount: Int,
        changesLayout: Bool,
        processIdentifier: pid_t?,
        performIfCurrent: @escaping @Sendable (@escaping @Sendable (String) -> Void) -> String?,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> Bool {
        guard !original.isEmpty, !converted.isEmpty, original != converted,
              backspaceCount > 0, pendingBufferReplacements.count < 8 else {
            rslog("buffer replacement unavailable: invalid request or queue full")
            return false
        }
        pendingBufferReplacements.append(PendingBufferReplacement(
            original: original,
            converted: converted,
            backspaceCount: backspaceCount,
            changesLayout: changesLayout,
            processIdentifier: processIdentifier,
            performIfCurrent: performIfCurrent,
            completion: completion
        ))
        processNextBufferReplacement()
        return true
    }

    private func processNextBufferReplacement() {
        guard !isConverting, !pendingBufferReplacements.isEmpty else { return }
        let request = pendingBufferReplacements.removeFirst()
        isConverting = true
        injectQueue.async { [weak self] in
            guard let self else { return }
            let sameProcess = request.processIdentifier
                == NSWorkspace.shared.frontmostApplication?.processIdentifier
            let preservedSuffix = sameProcess ? request.performIfCurrent { typedSuffix in
                self.backspace(request.backspaceCount + typedSuffix.count)
                usleep(20_000)
                self.insertText(request.converted + typedSuffix)
            } : nil
            let committed = preservedSuffix != nil
            Task { @MainActor in
                self.isConverting = false
                if !committed {
                    rslog("buffer replacement cancelled: captured process or input changed before commit")
                } else {
                    let suffix = preservedSuffix ?? ""
                    self.lastOriginal = request.original + suffix
                    self.lastConverted = request.converted + suffix
                    self.lastConversionOperationID = UUID().uuidString
                    self.lastUndoneOperationID = nil
                    self.bufferIsCurrentlyConverted = true
                    self.bufferProcessIdentifier = request.processIdentifier
                    self.lastWasBuffer = true
                    self.lastConversionChangesLayout = request.changesLayout
                    self.lastConvertedCount = 0
                    self.lastBoundaryCount = 0
                    self.lastPreservedSuffixKeyCount = suffix.count
                    rslog("buffer replacement committed")
                }
                request.completion(committed)
                self.processNextBufferReplacement()
            }
        }
    }

    /// Повторная конвертация (второй триггер) — на тот движок, которым делали последнюю.
    func reconvert(
        performIfCurrent: @escaping @Sendable (@escaping @Sendable () -> Void) -> Bool,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> Bool {
        guard !isConverting else { return false }
        if lastWasBuffer {
            guard let bufferProcessIdentifier,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == bufferProcessIdentifier else {
                rslog("buffer reconvert: foreground process changed; stale undo discarded")
                clearState()
                return false
            }
            guard !lastConverted.isEmpty else { return false }
            isConverting = true
            rslog("buffer reconvert")
            let bsCount = lastConverted.count
            let insert = lastOriginal
            injectQueue.async { [weak self] in
                guard let self else { return }
                let committed = performIfCurrent {
                    self.backspace(bsCount)
                    usleep(20_000)
                    self.insertText(insert)
                }
                Task { @MainActor in
                    self.isConverting = false
                    if committed {
                        swap(&self.lastOriginal, &self.lastConverted)
                        self.lastWasBuffer = true
                        self.bufferIsCurrentlyConverted.toggle()
                        self.lastUndoneOperationID = self.bufferIsCurrentlyConverted
                            ? nil : self.lastConversionOperationID
                    } else {
                        self.clearState()
                    }
                    completion(committed)
                }
            }
            return true
        }
        let committed = reconvertViaClipboard()
        completion(committed)
        return committed
    }

    /// Конвертация через буфер обмена (фолбэк: выделенный мышью текст и т.п.).
    /// Сначала проверяет выделение, потом пробует слово по счётчику.
    func convertViaClipboard(wordLength: Int, prevWordLength: Int, boundaryCount: Int,
                             allowUnrecognizedSingleWord: Bool = true) -> Bool {
        guard !isConverting else {
            rslog("convert: skipped — already converting")
            return false
        }
        isConverting = true
        lastWasBuffer = false
        bufferProcessIdentifier = nil
        lastConversionChangesLayout = true
        defer { isConverting = false }

        if !isFocusedElementEditable() {
            rslog("convert: element may not be editable, trying anyway")
        }
        let pasteboard = NSPasteboard.general
        cancelClipboardRestore()
        // Скептик 3.2.0: не перезаписываем сохранённый буфер при повторной конверсии в окне
        // восстановления (2с) — иначе «оригиналом» стал бы промежуточный конвертированный текст.
        captureClipboardSnapshotIfNeeded(pasteboard)

        var conversionSucceeded = false
        defer {
            // Любой ранний выход без успеха обязан вернуть буфер пользователю —
            // иначе clipboard остаётся пустым или с конвертированным текстом.
            if !conversionSucceeded { restoreClipboardNow() }
        }

        // --- Попытка 1: уже есть выделенный текст? ---
        let selection = verifiedSelection()
        if let text = tryCopy(pasteboard) {
            rslog("convert: selection len=\(text.count)")
            // Selection, Spotlight, and line conversion share this policy.
            let hasVerifiedSelection = allowUnrecognizedSingleWord && selection?.text == text
            let converted = TextConverter.normalizedForInsert(convertSelectionText(
                text, allowUnrecognizedSingleWord: hasVerifiedSelection))
            // Конверсия не изменила текст (пара не разрешилась / комбинирующие знаки —
            // см. bail'ы в DynamicKeyMapping) — не гоняем вставку впустую.
            if converted == text {
                rslog("convert: no-op conversion — bail")
                return false
            }
            if let selection, !selectionIsCurrent(selection) || selection.text != text {
                rslog("convert: selected range changed — bail")
                return false
            }
            pasteText(converted, pasteboard: pasteboard)
            // Курсор остаётся в конце вставленного текста — не пере-выделяем,
            // чтобы следующий ввод не затёр результат. Для reconvert используется
            // унифицированный путь через selectBack(lastConvertedCount).
            lastConvertedCount = converted.count
            lastBoundaryCount = 0
            // issue #22: сохраняем пару до/после — реконверт восстанавливает ТОЧНО,
            // а не пере-конвертирует (умный/тотальный флип односторонней convert не
            // инвертируется, особенно смешанный результат).
            lastOriginal = text
            lastConverted = converted
            // RTL: реконверт этого результата шёл бы стрелочной селекцией, а стрелки
            // двигают каретку ВИЗУАЛЬНО — в RTL выделился бы не тот диапазон и
            // конверсия заменила бы чужой текст (ревью-находка). Помечаем, чтобы
            // reconvertViaClipboard отказался.
            lastClipboardRTL = TextConverter.containsRTL(text) || TextConverter.containsRTL(converted)
            conversionSucceeded = true
            scheduleClipboardRestore()
            return true
        }

        // RTL-пара: счётчиковый путь выделяет Shift+Left'ами, а в RTL «влево» —
        // логически вперёд: выделили бы не то и заменили чужой текст. Точность
        // важнее полноты — отказ (буферный движок ивриту не нужен только при
        // выделении мышью, а это Попытка 1 выше).
        if let l = LayoutSwitcher.currentAndOppositeLanguage(),
           LayoutDetector.isHebrew(l.current) || LayoutDetector.isHebrew(l.opposite) {
            rslog("convert: hebrew pair — count-based clipboard path unsafe, bail")
            return false
        }

        // --- Попытка 2: выделяем слово по счётчику ---
        let charCount: Int
        let usedBoundary: Int

        if wordLength > 0 {
            charCount = wordLength
            usedBoundary = 0
        } else if prevWordLength > 0 && boundaryCount > 0 {
            moveLeft(boundaryCount)
            charCount = prevWordLength
            usedBoundary = boundaryCount
        } else {
            rslog("convert: nothing to convert (wordLen=\(wordLength) prevLen=\(prevWordLength))")
            return false
        }

        rslog("convert: selecting \(charCount) chars (boundary=\(usedBoundary))")
        selectBack(charCount)
        usleep(50_000)

        guard let text = tryCopy(pasteboard) else {
            rslog("convert: copy failed")
            simKey(keyCode: KC.right, flags: []) // снять выделение
            moveRight(usedBoundary)
            return false
        }

        rslog("convert: word len=\(text.count)")
        // A forced Option on the last word remains a direct layout flip. Smart mode is
        // reserved for explicit selections and whole-line conversion.
        let converted = TextConverter.normalizedForInsert(
            SettingsManager.shared.convertByText
                ? DynamicKeyMapping.convertBidirectional(text)
                : DynamicKeyMapping.convert(text))
        pasteText(converted, pasteboard: pasteboard)

        moveRight(usedBoundary)

        lastConvertedCount = converted.count
        lastBoundaryCount = usedBoundary
        lastOriginal = text          // issue #22: точное восстановление в reconvert
        lastConverted = converted
        // Симметрично Попытке 1: актуализируем флаг, чтобы прошлое RTL-выделение
        // не блокировало реконверт свежей LTR-конверсии (залипший флаг).
        lastClipboardRTL = TextConverter.containsRTL(text) || TextConverter.containsRTL(converted)
        conversionSucceeded = true
        scheduleClipboardRestore()
        return true
    }

    /// Повторная конвертация через буфер обмена (фолбэк).
    private func reconvertViaClipboard() -> Bool {
        guard !isConverting else {
            rslog("reconvert: skipped — already converting")
            return false
        }
        isConverting = true
        defer { isConverting = false }

        rslog("reconvert: lastCount=\(lastConvertedCount) boundary=\(lastBoundaryCount)")
        guard lastConvertedCount > 0 else { return false }
        // RTL-результат: стрелочная селекция в RTL выделит не тот диапазон (см. convert).
        guard !lastClipboardRTL else {
            rslog("reconvert: RTL selection — arrow-based path unsafe, bail")
            return false
        }

        let pasteboard = NSPasteboard.general
        // Отменяем отложенное восстановление clipboard — мы ещё работаем
        cancelClipboardRestore()
        // Скептик 3.2.0: если восстановление уже отработало (snapshot пуст), снимаем свежий —
        // иначе финальный scheduleClipboardRestore очистил бы буфер пользователя.
        captureClipboardSnapshotIfNeeded(pasteboard)

        moveLeft(lastBoundaryCount)

        selectBack(lastConvertedCount)
        usleep(80_000)  // дать приложению обработать выделение

        guard let text = tryCopy(pasteboard) else {
            rslog("reconvert: copy failed, count=\(lastConvertedCount)")
            simKey(keyCode: KC.right, flags: [])
            moveRight(lastBoundaryCount)
            scheduleClipboardRestore()
            return false
        }

        // issue #22: если выделенное совпадает с прошлым результатом — ВОССТАНАВЛИВАЕМ
        // исходник точно (умный/тотальный флип односторонней convert не инвертируется).
        // Иначе (текст изменился) — безопасный фолбэк на обычную одностороннюю конверсию.
        let converted: String
        if text == lastConverted, !lastOriginal.isEmpty {
            converted = lastOriginal
            let tmp = lastOriginal; lastOriginal = lastConverted; lastConverted = tmp   // toggle
            rslog("reconvert: restored original (len=\(converted.count))")
        } else {
            converted = TextConverter.normalizedForInsert(DynamicKeyMapping.convert(text))
            rslog("reconvert: len=\(text.count) → converting (fallback)")
        }
        pasteText(converted, pasteboard: pasteboard)

        moveRight(lastBoundaryCount)

        lastConvertedCount = converted.count
        scheduleClipboardRestore()
        return true
    }

    func clearState() {
        lastConvertedCount = 0
        lastBoundaryCount = 0
        lastOriginal = ""
        lastConverted = ""
        lastWasBuffer = false
        lastConversionOperationID = nil
        lastUndoneOperationID = nil
        bufferIsCurrentlyConverted = false
        lastClipboardRTL = false
        lastConversionChangesLayout = false
        spotlightUndo = nil
        safariUndo = nil
    }

    // MARK: - Private

    /// Стирает текст перед перепечаткой. Порядок CGEvents сохраняется, но это не
    /// гарантирует, что каждое приложение успеет обработать серию событий до следующего.
    /// Пауза перед первым Backspace закрывает гонку с Option/границей слова; 3 мс между
    /// нажатиями дают текстовым полям обработать каждое удаление.
    nonisolated private func backspace(_ n: Int) {
        guard n > 0 else { return }
        usleep(10_000)
        for _ in 0..<n {
            simKey(keyCode: KC.backspace, flags: [])
            usleep(3_000)
        }
    }

    /// Впечатывает строку напрямую (юникод-вставка), без буфера обмена.
    nonisolated private func insertText(_ text: String) {
        guard !text.isEmpty, let source = makeSource() else { return }
        let utf16 = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        utf16.withUnsafeBufferPointer { buf in
            down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Вставляет текст через Cmd+V и ждёт завершения
    private func pasteText(_ text: String, pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        ownedClipboardChangeCount = pasteboard.changeCount
        simKey(keyCode: KC.letterV, flags: .maskCommand) // Cmd+V
        usleep(150_000) // 150мс — дать приложению вставить текст и обновить курсор
    }

    /// Отменяет отложенное восстановление clipboard
    private func cancelClipboardRestore() {
        clipboardRestoreWork?.cancel()
        clipboardRestoreWork = nil
    }

    /// Capture all available pasteboard formats and note the current generation.
    private func captureClipboardSnapshotIfNeeded(_ pasteboard: NSPasteboard) {
        let currentCount = pasteboard.changeCount
        if let savedCount = savedClipboardChangeCount {
            guard ClipboardRestorePolicy.userChangedClipboard(
                savedChangeCount: savedCount,
                ownedChangeCount: ownedClipboardChangeCount,
                currentChangeCount: currentCount
            ) else { return }
            // A newer user copy supersedes the snapshot from our previous conversion.
            clearClipboardSnapshot()
        }
        savedClipboardItems = snapshotPasteboard(pasteboard)
        savedClipboardChangeCount = currentCount
        ownedClipboardChangeCount = nil
    }

    private func clearClipboardSnapshot() {
        savedClipboardItems = nil
        savedClipboardChangeCount = nil
        ownedClipboardChangeCount = nil
    }

    /// Restore only if the current pasteboard generation is still ours.
    private func restoreClipboardNow() {
        cancelClipboardRestore()
        guard let saved = savedClipboardItems,
              let savedCount = savedClipboardChangeCount else {
            clearClipboardSnapshot()
            return
        }
        let pasteboard = NSPasteboard.general
        guard ClipboardRestorePolicy.mayRestore(
            savedChangeCount: savedCount,
            ownedChangeCount: ownedClipboardChangeCount,
            currentChangeCount: pasteboard.changeCount
        ) else {
            rslog("clipboard restore skipped (ownership changed)")
            clearClipboardSnapshot()
            return
        }

        pasteboard.clearContents()
        if !saved.isEmpty { pasteboard.writeObjects(saved) }
        clearClipboardSnapshot()
    }

    /// Сбрасывает отложенное восстановление немедленно — вызывается перед
    /// завершением приложения, чтобы не потерять буфер в 2-секундном окне.
    func flushPendingClipboardRestore() {
        guard clipboardRestoreWork != nil else { return }
        restoreClipboardNow()
    }

    /// Планирует восстановление clipboard через 2 секунды
    /// (если за это время придёт reconvert — отменится и перепланируется)
    private func scheduleClipboardRestore() {
        cancelClipboardRestore()
        let saved = self.savedClipboardItems
        let expectedChangeCount = ownedClipboardChangeCount
        let savedCount = saved?.count ?? 0
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let pasteboard = NSPasteboard.general
            guard let originalCount = self.savedClipboardChangeCount,
                  ClipboardRestorePolicy.mayRestore(
                    savedChangeCount: originalCount,
                    ownedChangeCount: expectedChangeCount,
                    currentChangeCount: pasteboard.changeCount
                  ) else {
                self.clearClipboardSnapshot()
                self.clipboardRestoreWork = nil
                rslog("clipboard restore skipped (ownership changed)")
                return
            }
            pasteboard.clearContents()
            if let saved, !saved.isEmpty {
                pasteboard.writeObjects(saved)
            }
            self.clearClipboardSnapshot()
            self.clipboardRestoreWork = nil
            rslog("clipboard restored (\(savedCount) items)")
        }
        clipboardRestoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    /// Делает глубокую копию всех pasteboard items (со всеми типами данных).
    /// Это нужно потому, что NSPasteboardItem становится невалидным после
    /// pasteboard.clearContents() — поэтому копируем data по каждому типу
    /// в новые NSPasteboardItem.
    private func snapshotPasteboard(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pb.pasteboardItems else { return [] }
        return items.map { oldItem in
            let newItem = NSPasteboardItem()
            for type in oldItem.types {
                if let data = oldItem.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
    }

    /// Копирует выделенный текст. Делает до 3 попыток (Cmd+C не всегда срабатывает с первого раза)
    private func tryCopy(_ pasteboard: NSPasteboard) -> String? {
        for attempt in 0..<3 {
            // Очищаем буфер перед копированием — гарантирует что changeCount изменится
            pasteboard.clearContents()
            let oldCount = pasteboard.changeCount
            ownedClipboardChangeCount = oldCount

            simKey(keyCode: KC.letterC, flags: .maskCommand) // Cmd+C
            usleep(attempt == 0 ? 80_000 : 120_000)
            ownedClipboardChangeCount = pasteboard.changeCount

            if pasteboard.changeCount != oldCount,
               let text = pasteboard.string(forType: .string),
               !text.isEmpty {
                return text
            }
            usleep(50_000) // пауза перед retry
        }
        return nil
    }

    /// Выделяет N символов влево (Shift+Left × N)
    nonisolated private func selectBack(_ count: Int) {
        for _ in 0..<count {
            simKey(keyCode: KC.left, flags: .maskShift)
            usleep(1_000)
        }
    }

    /// Сдвигает курсор влево на N символов
    nonisolated private func moveLeft(_ count: Int) {
        for _ in 0..<count {
            simKey(keyCode: KC.left, flags: [])
            usleep(1_000)
        }
    }

    /// Сдвигает курсор вправо на N символов (восстановление границ-пробелов)
    nonisolated private func moveRight(_ count: Int) {
        for _ in 0..<count {
            simKey(keyCode: KC.right, flags: [])
            usleep(1_000)
        }
    }

    /// Симулирует нажатие клавиши с маркером (чтобы наш monitor игнорировал)
    nonisolated private func simKey(keyCode: UInt16, flags: CGEventFlags) {
        guard let source = makeSource() else { return }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
