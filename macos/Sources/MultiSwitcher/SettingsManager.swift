import CoreFoundation
import Foundation
import MultiSwitcherCore
import MultiSwitcherCore
import ServiceManagement

/// Централизованное хранение настроек через UserDefaults
/// Настройки приложения. Свойства thread-safe через UserDefaults.
final class SettingsManager: @unchecked Sendable {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let profileStore = ProfileStore.shared

    private enum Keys {
        static let autoSwitch = "com.multiswitcher.autoSwitch"
        static let layout1ID = "com.multiswitcher.layout1ID"
        static let layout2ID = "com.multiswitcher.layout2ID"
        static let debugLog = "com.multiswitcher.debugLog"
        static let checkUpdatesEnabled = "com.multiswitcher.checkUpdatesEnabled"
        static let updateChannel = "com.multiswitcher.updateChannel"
        static let launchAtLogin = "com.multiswitcher.launchAtLogin"
        static let interfaceLanguage = "com.multiswitcher.interfaceLanguage"
        static let permissionsWereGranted = "com.multiswitcher.permissionsWereGranted"
        static let launchAtLoginAsked = "com.multiswitcher.launchAtLoginAsked"
        static let perAppLayout = "com.multiswitcher.perAppLayout"
        static let triggerKey = "com.multiswitcher.triggerKey"
        static let triggerRightOnly = "com.multiswitcher.triggerRightOnly"
        static let triggerDoubleTap = "com.multiswitcher.triggerDoubleTap"
        static let switchHotkey = "com.multiswitcher.switchHotkey"
        static let switchDoubleTap = "com.multiswitcher.switchDoubleTap"
        static let switchRightOnly = "com.multiswitcher.switchRightOnly"
        static let caseHotkey = "com.multiswitcher.caseHotkey"       // issue #29
        static let caseDoubleTap = "com.multiswitcher.caseDoubleTap"
        static let caseRightOnly = "com.multiswitcher.caseRightOnly"
        static let autoConvert = "com.multiswitcher.autoConvert"
        static let smartConversion = "com.multiswitcher.smartConversion"
        static let convertByText = "com.multiswitcher.convertByText"
        static let convertWholeLine = "com.multiswitcher.convertWholeLine"
        static let remoteDesktopMode = "com.multiswitcher.remoteDesktopMode"
        static let showRemoteDesktopBeta = "com.multiswitcher.showRemoteDesktopBeta"
        static let autoConvertOffered = "com.multiswitcher.autoConvertOffered"
        static let keySound = "com.multiswitcher.keySound"
        static let caretFlag = "com.multiswitcher.caretFlag"
        static let secureInputNotice = "com.multiswitcher.secureInputNotice"
        static let hideMenuBarIcon = "com.multiswitcher.hideMenuBarIcon"
        static let monochromeIcon = "com.multiswitcher.monochromeIcon"
        static let deniedAppsAdded = "com.multiswitcher.deniedAppsAdded"
        static let deniedAppsRemoved = "com.multiswitcher.deniedAppsRemoved"
        static let allActionsDeniedApps = "com.multiswitcher.allActionsDeniedApps"
        static let deniedWords = "com.multiswitcher.deniedWords"
        static let alwaysConvertWords = "com.multiswitcher.alwaysConvertWords"
        static let learningEnabled = "com.multiswitcher.learningEnabled"
        static let paused = "com.multiswitcher.paused"
        static let pauseUntil = "com.multiswitcher.pauseUntil"
        static let enabledDictionaryThemes = "com.multiswitcher.enabledDictionaryThemes"
        static let compactSettings = "com.multiswitcher.compactSettings"
        static let settingsSidebarWidth = "com.multiswitcher.settingsSidebarWidth"
    }

    private init() {
        migrateLegacyDefaults()
    }

    private func migrateLegacyDefaults() {
        guard !profileStore.current.legacyDefaultsMigrated else { return }
        let domainName = Bundle.main.bundleIdentifier ?? "com.multiswitcher.app"
        let legacy = defaults.persistentDomain(forName: domainName) ?? [:]
        do {
            try profileStore.update { profile in
                guard !profile.legacyDefaultsMigrated else { return }
                for (key, value) in legacy where key.hasPrefix("com.multiswitcher.") {
                    if let strings = value as? [String] {
                        profile.settings[key] = .strings(strings)
                    } else if let string = value as? String {
                        profile.settings[key] = .string(string)
                    } else if let number = value as? NSNumber,
                              CFGetTypeID(number) == CFBooleanGetTypeID() {
                        profile.settings[key] = .bool(number.boolValue)
                    } else if let number = value as? NSNumber {
                        profile.settings[key] = .integer(number.intValue)
                    }
                }
                profile.legacyDefaultsMigrated = true
            }
        } catch {
            rslog("Profile migration failed: \(error.localizedDescription)")
        }
    }

    private func readBool(_ key: String, default fallback: Bool = false) -> Bool {
        if case .bool(let value) = profileStore.current.settings[key] { return value }
        return defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func readString(_ key: String, default fallback: String = "") -> String {
        if case .string(let value) = profileStore.current.settings[key] { return value }
        return defaults.string(forKey: key) ?? fallback
    }

    private func readInt(_ key: String, default fallback: Int) -> Int {
        if case .integer(let value) = profileStore.current.settings[key] { return value }
        return defaults.object(forKey: key) as? Int ?? fallback
    }

    private func readStrings(_ key: String) -> [String] {
        if case .strings(let value) = profileStore.current.settings[key] { return value }
        return defaults.stringArray(forKey: key) ?? []
    }

    private func write(_ value: Bool, forKey key: String) {
        saveSetting(.bool(value), forKey: key)
    }

    private func write(_ value: String, forKey key: String) {
        saveSetting(.string(value), forKey: key)
    }

    private func write(_ value: Int, forKey key: String) {
        saveSetting(.integer(value), forKey: key)
    }

    private func write(_ value: [String], forKey key: String) {
        saveSetting(.strings(value), forKey: key)
    }

    private func saveSetting(_ value: ProfileSetting, forKey key: String) {
        do {
            try profileStore.update { $0.settings[key] = value }
        } catch {
            rslog("Profile setting save failed for \(key): \(error.localizedDescription)")
        }
    }

    // MARK: - Properties

    var autoSwitchEnabled: Bool {
        get { readBool(Keys.autoSwitch, default: true) }
        set { write(newValue, forKey: Keys.autoSwitch) }
    }

    var learningEnabled: Bool {
        get { readBool(Keys.learningEnabled, default: true) }
        set { write(newValue, forKey: Keys.learningEnabled) }
    }

    var isPaused: Bool {
        get {
            guard readBool(Keys.paused) else { return false }
            let deadline = readInt(Keys.pauseUntil, default: 0)
            return deadline == 0 || deadline > Int(Date().timeIntervalSince1970)
        }
        set {
            write(newValue, forKey: Keys.paused)
            write(0, forKey: Keys.pauseUntil)
        }
    }

    var pauseDeadline: Date? {
        let value = readInt(Keys.pauseUntil, default: 0)
        return value > 0 ? Date(timeIntervalSince1970: TimeInterval(value)) : nil
    }

    func pause(for duration: TimeInterval?) {
        write(true, forKey: Keys.paused)
        let deadline = duration.map { Int(Date().addingTimeInterval($0).timeIntervalSince1970) } ?? 0
        write(deadline, forKey: Keys.pauseUntil)
    }

    func clearExpiredPause() {
        guard readBool(Keys.paused), PauseStatePolicy.hasExpiredDeadline(pauseDeadline) else { return }
        isPaused = false
    }

    /// Optional themed vocabularies add accepted words; they never rewrite spelling.
    var enabledDictionaryThemes: Set<String> {
        get {
            let configured = readStrings(Keys.enabledDictionaryThemes)
            if configured == ["__none__"] { return [] }
            return configured.isEmpty
                ? Set(["technology", "design", "brands", "slang"])
                : Set(configured)
        }
        set { write(newValue.isEmpty ? ["__none__"] : newValue.sorted(), forKey: Keys.enabledDictionaryThemes) }
    }

    var compactSettings: Bool {
        get { readBool(Keys.compactSettings) }
        set { write(newValue, forKey: Keys.compactSettings) }
    }

    var settingsSidebarWidth: Int {
        get { min(320, max(180, readInt(Keys.settingsSidebarWidth, default: 206))) }
        set { write(min(320, max(180, newValue)), forKey: Keys.settingsSidebarWidth) }
    }

    var learningEntries: [LearningEntry] {
        LearningEngine.sortedForReview(profileStore.current.learning)
    }

    var hasLearnedExclusions: Bool {
        profileStore.current.rules.contains { $0.origin == .learned && $0.enabled }
    }

    @discardableResult
    func undoLastLearnedExclusion() -> String? {
        let latest = profileStore.current.learning
            .filter(\.isExcluded)
            .max { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }
        guard let latest, undoLearnedExclusion(latest.word) else { return nil }
        return latest.word
    }

    func forgetLearnedWord(_ word: String) {
        do {
            try profileStore.update { LearningEngine.forget(word: word, in: &$0) }
        } catch {
            rslog("Learning profile save failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func confirmManualLearningCandidate(_ word: String) -> Bool {
        var confirmed = false
        do {
            try profileStore.update { profile in
                confirmed = LearningEngine.confirmManualCandidate(word: word, in: &profile)
            }
        } catch {
            rslog("Manual learning confirmation failed: \(error.localizedDescription)")
        }
        return confirmed
    }

    @discardableResult
    func undoLearnedExclusion(_ word: String) -> Bool {
        var removed = false
        do {
            try profileStore.update { removed = LearningEngine.undoLearnedExclusion(word: word, in: &$0) }
        } catch {
            rslog("Learning profile save failed: \(error.localizedDescription)")
        }
        return removed
    }

    /// ID первой раскладки (пустая строка = авто-определение)
    var layout1ID: String {
        get { readString(Keys.layout1ID, default: "") }
        set { write(newValue, forKey: Keys.layout1ID) }
    }

    /// ID второй раскладки (пустая строка = авто-определение)
    var layout2ID: String {
        get { readString(Keys.layout2ID, default: "") }
        set { write(newValue, forKey: Keys.layout2ID) }
    }

    var checkUpdatesEnabled: Bool {
        get { defaults.object(forKey: Keys.checkUpdatesEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.checkUpdatesEnabled) }
    }

    var updateChannel: UpdateChannel {
        get {
            let fallback = Bundle.main.object(forInfoDictionaryKey: "MSUpdateChannel") as? String ?? UpdateChannel.stable.rawValue
            return UpdateChannel(rawValue: readString(Keys.updateChannel, default: fallback)) ?? .stable
        }
        set { write(newValue.rawValue, forKey: Keys.updateChannel) }
    }

    var debugLogEnabled: Bool {
        get { readBool(Keys.debugLog) }
        set { write(newValue, forKey: Keys.debugLog) }
    }

    var launchAtLogin: Bool {
        get { readBool(Keys.launchAtLogin, default: false) }
        set {
            write(newValue, forKey: Keys.launchAtLogin)
            let enabled = newValue
            DispatchQueue.main.async {
                self.doUpdateLoginItem(enabled: enabled)
            }
        }
    }

    /// Язык интерфейса (пустая строка = авто-определение по системе)
    var interfaceLanguage: String {
        get { readString(Keys.interfaceLanguage, default: "") }
        set {
            write(newValue, forKey: Keys.interfaceLanguage)
            L10n.reloadLanguage()
        }
    }

    /// Флаг: разрешения были ранее выданы (для определения сброса после обновления)
    var permissionsWereGranted: Bool {
        get { readBool(Keys.permissionsWereGranted) }
        set { write(newValue, forKey: Keys.permissionsWereGranted) }
    }

    var launchAtLoginAsked: Bool {
        get { readBool(Keys.launchAtLoginAsked) }
        set { write(newValue, forKey: Keys.launchAtLoginAsked) }
    }

    var perAppLayout: Bool {
        get { readBool(Keys.perAppLayout) }
        set { write(newValue, forKey: Keys.perAppLayout) }
    }

    /// Persisted input-source choice by app bundle identifier. Kept in the versioned profile.
    var rememberedLayoutsByApp: [String: String] {
        PerAppLayoutMemory.layouts(in: profileStore.current)
    }

    func rememberLayout(_ layoutID: String, for bundleID: String) {
        guard rememberedLayoutsByApp[bundleID] != layoutID else { return }
        do {
            try profileStore.update { PerAppLayoutMemory.remember(layoutID, for: bundleID, in: &$0) }
        } catch {
            rslog("Per-app layout profile save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Триггер конвертации

    /// Клавиша-триггер: "option" | "command" | "control" | "shift" | "capsLock".
    /// Дефолт — option (как было до 2.3, поведение не меняется).
    var triggerKey: String {
        get { readString(Keys.triggerKey, default: "option") }
        set { write(newValue, forKey: Keys.triggerKey) }
    }

    /// Реагировать только на правую клавишу модификатора (для option/command/control/shift).
    var triggerRightOnly: Bool {
        get { readBool(Keys.triggerRightOnly) }
        set { write(newValue, forKey: Keys.triggerRightOnly) }
    }

    /// Двойной тап вместо одиночного.
    var triggerDoubleTap: Bool {
        get { readBool(Keys.triggerDoubleTap) }
        set { write(newValue, forKey: Keys.triggerDoubleTap) }
    }

    /// issue #14: отдельный хоткей «просто переключить раскладку» (без конверсии) —
    /// в т.ч. модификаторные комбо (Ctrl+Shift), которые системно назначить нельзя.
    /// Кодировка как у triggerKey; пустая строка — выключен (дефолт).
    var switchHotkey: String {
        get { readString(Keys.switchHotkey, default: "") }
        set { write(newValue, forKey: Keys.switchHotkey) }
    }

    /// issue #14: смена раскладки по ДВОЙНОМУ тапу хоткея (зеркало triggerDoubleTap).
    var switchDoubleTap: Bool {
        get { readBool(Keys.switchDoubleTap) }
        set { write(newValue, forKey: Keys.switchDoubleTap) }
    }

    /// issue #14: реагировать только на ПРАВУЮ клавишу хоткея (зеркало triggerRightOnly).
    /// Действует лишь для одиночных модификаторов; для комбо сторона не различается.
    var switchRightOnly: Bool {
        get { readBool(Keys.switchRightOnly) }
        set { write(newValue, forKey: Keys.switchRightOnly) }
    }

    /// issue #29: хоткей смены регистра (кодировка как triggerKey; пустая строка — выключен, дефолт).
    var caseHotkey: String {
        get { readString(Keys.caseHotkey, default: "") }
        set { write(newValue, forKey: Keys.caseHotkey) }
    }
    var caseDoubleTap: Bool {
        get { readBool(Keys.caseDoubleTap) }
        set { write(newValue, forKey: Keys.caseDoubleTap) }
    }
    var caseRightOnly: Bool {
        get { readBool(Keys.caseRightOnly) }
        set { write(newValue, forKey: Keys.caseRightOnly) }
    }

    /// Caps Lock как триггер требует consume-tap (чтобы подавить переключение регистра).
    var triggerIsCapsLock: Bool { triggerKey == "capsLock" }

    /// Автоматическая конвертация «на лету» (детект неправильной раскладки на границе
    /// слова). Отдельный флаг от autoSwitchEnabled (тот гейтит РУЧНОЙ триггер).
    /// По умолчанию ВЫКЛ — точность важнее, не делаем ничего без явного включения.
    var autoConvert: Bool {
        get { readBool(Keys.autoConvert) }
        set { write(newValue, forKey: Keys.autoConvert) }
    }

    /// issue #22 (вариант B): умная по-словная конверсия выделения — флипаем только слова не в
    /// той раскладке, а верный текст оставляем («iPhone стоит»). По умолчанию ВКЛ. Выключено —
    /// старое одностороннее поведение (всё выделение в одну сторону по текущей раскладке).
    var smartConversion: Bool {
        get { readBool(Keys.smartConversion, default: true) }
        set {
            write(newValue, forKey: Keys.smartConversion)
            if newValue { write(false, forKey: Keys.convertByText) }
        }
    }

    /// issue #22 (вариант A): ручной триггер конвертирует ПО ТЕКСТУ — тотальный флип обеих
    /// письменностей (латиница↔кириллица) вместо направления по активной раскладке. Полезно
    /// для mixed-мусора, но переворачивает и намеренный второй язык. По умолчанию ВЫКЛ.
    /// Перебивает «Умную конверсию».
    var convertByText: Bool {
        // Smart mode is the safe default and wins over legacy profiles that happened
        // to persist both flags. Enabling full flip explicitly turns smart mode off.
        get { readBool(Keys.convertByText) && !smartConversion }
        set {
            write(newValue, forKey: Keys.convertByText)
            if newValue { write(false, forKey: Keys.smartConversion) }
        }
    }

    /// issue #24: триггер конвертирует ВСЮ строку (от курсора до начала строки), а не только
    /// последнее слово — сам выделяет строку (без мыши) и прогоняет через умную конверсию.
    /// Удобно в терминале и когда набрал несколько слов не в той раскладке. По умолчанию ВЫКЛ.
    var convertWholeLine: Bool {
        get { readBool(Keys.convertWholeLine) }
        set { write(newValue, forKey: Keys.convertWholeLine) }
    }

    /// issue #10: показывать буквенную метку раскладки у текстовой каретки (бета). По умолчанию ВЫКЛ.
    /// issue #27: показывать неактивирующую подсказку, когда защищённый ввод ставит на паузу.
    /// По умолчанию включено; можно отключить тем, кому она мешает.
    var secureInputNoticeEnabled: Bool {
        get { readBool(Keys.secureInputNotice, default: true) }
        set { write(newValue, forKey: Keys.secureInputNotice) }
    }

    /// Полностью скрыть иконку из меню-бара (запрос пользователя: «значок мозолит глаз»).
    /// По умолчанию ВЫКЛ. Путь назад — повторный запуск приложения: reopen-обработчик
    /// открывает Настройки (см. applicationShouldHandleReopen). Аварийный сброс:
    /// defaults delete com.multiswitcher.app com.multiswitcher.hideMenuBarIcon
    var hideMenuBarIcon: Bool {
        get { readBool(Keys.hideMenuBarIcon) }
        set { write(newValue, forKey: Keys.hideMenuBarIcon) }
    }

    var caretFlag: Bool {
        get { readBool(Keys.caretFlag) }
        set { write(newValue, forKey: Keys.caretFlag) }
    }

    /// Режим работы через удалённый рабочий стол (Apple Screen Sharing и т.п.).
    /// При включении: tap поднимается на session-уровень (видит проброшенные
    /// нажатия), и инстанс «уступает удалёнке», если в фокусе клиент удалёнки.
    var remoteDesktopMode: Bool {
        get { readBool(Keys.remoteDesktopMode) }
        set { write(newValue, forKey: Keys.remoteDesktopMode) }
    }

    /// Показывать ли тумблер «Режим удалённого стола» (видимая бета в 2.5). По умолчанию
    /// ВКЛючён; спрятать можно явно: `defaults write com.multiswitcher.app com.multiswitcher.showRemoteDesktopBeta -bool NO`.
    var showRemoteDesktopBeta: Bool {
        get {
            // Нет записи в defaults → считаем включённым (дефолт ON для 2.5).
            return readBool(Keys.showRemoteDesktopBeta, default: true)
        }
        set { write(newValue, forKey: Keys.showRemoteDesktopBeta) }
    }

    /// Предлагали ли уже автозамену при первом запуске (онбординг показывается один раз).
    var autoConvertOffered: Bool {
        get { readBool(Keys.autoConvertOffered) }
        set { write(newValue, forKey: Keys.autoConvertOffered) }
    }

    /// issue #7: звук раскладки на первой букве после смены раскладки. По умолчанию OFF.
    var keySound: Bool {
        get { readBool(Keys.keySound) }
        set { write(newValue, forKey: Keys.keySound) }
    }

    /// Иконка меню-бара в системном стиле: монохромная плашка вместо символического значка.
    /// По умолчанию OFF.
    var monochromeIcon: Bool {
        get { readBool(Keys.monochromeIcon) }
        set { write(newValue, forKey: Keys.monochromeIcon) }
    }

    /// Приложения, где авто-конверсия выключена. Эффективный список = дефолты минус
    /// явно удалённые пользователем плюс явно добавленные. Так новые дефолты из будущих
    /// версий подхватываются автоматически, а правки пользователя сохраняются.
    var deniedApps: [String] {
        get {
            let removed = Set(readStrings(Keys.deniedAppsRemoved))
            let added = readStrings(Keys.deniedAppsAdded)
            var result = AutoSwitchPolicy.defaultDeniedApps.filter { !removed.contains($0) }
            for a in added where !result.contains(a) { result.append(a) }
            return result
        }
        set {
            let defaultsSet = Set(AutoSwitchPolicy.defaultDeniedApps)
            let newSet = Set(newValue)
            let removed = AutoSwitchPolicy.defaultDeniedApps.filter { !newSet.contains($0) }
            let added = newValue.filter { !defaultsSet.contains($0) }
            write(removed, forKey: Keys.deniedAppsRemoved)
            write(added, forKey: Keys.deniedAppsAdded)
        }
    }

    /// Applications where every conversion, case and app-layout action is disabled.
    var allActionsDeniedApps: [String] {
        get { readStrings(Keys.allActionsDeniedApps) }
        set { write(newValue, forKey: Keys.allActionsDeniedApps) }
    }

    var allRules: [ProfileRule] {
        var rules = profileStore.current.rules
        for word in readStrings(Keys.deniedWords) where !rules.contains(where: {
            $0.action == .neverConvert && $0.match == .exact
                && normalizedWordKey($0.pattern) == normalizedWordKey(word)
        }) {
            rules.append(ProfileRule(pattern: word, match: .exact, action: .neverConvert, origin: .user))
        }
        for word in readStrings(Keys.alwaysConvertWords) where !rules.contains(where: {
            $0.action == .alwaysConvert && $0.match == .exact
                && normalizedWordKey($0.pattern) == normalizedWordKey(word)
        }) {
            rules.append(ProfileRule(pattern: word, match: .exact, action: .alwaysConvert, origin: .user))
        }
        return rules
    }

    var userRules: [ProfileRule] { allRules.filter { $0.origin == .user } }

    func replaceUserRules(_ rules: [ProfileRule]) throws {
        _ = try UserRuleFileCodec.encode(rules)
        try profileStore.update { profile in
            profile.rules.removeAll { $0.origin == .user }
            profile.rules.append(contentsOf: rules)
            profile.settings[Keys.deniedWords] = .strings([])
            profile.settings[Keys.alwaysConvertWords] = .strings([])
        }
    }

    var removedPuntoRuleCount: Int {
        guard case .strings(let ids) = profileStore.current.settings[PuntoProfileMigration.removedRuleIDsSettingKey] else {
            return 0
        }
        return ids.count
    }

    @discardableResult
    func deleteRule(_ rule: ProfileRule) throws -> Bool {
        var removed = false
        try profileStore.update { profile in
            switch rule.origin {
            case .punto:
                hydrateImportedPuntoRulesIfNeeded(&profile)
                removed = PuntoProfileMigration.removeImportedRule(rule.id, from: &profile)
            case .learned:
                let oldRules = profile.rules.count
                let oldLearning = profile.learning.count
                LearningEngine.forget(word: rule.pattern, in: &profile)
                removed = profile.rules.count != oldRules || profile.learning.count != oldLearning
            case .user:
                let oldRules = profile.rules.count
                profile.rules.removeAll {
                    $0.origin == .user && ($0.id == rule.id || (
                        $0.pattern == rule.pattern && $0.match == rule.match && $0.action == rule.action
                            && $0.replacement == rule.replacement
                    ))
                }
                removed = profile.rules.count != oldRules

                let legacyKey: String?
                switch rule.action {
                case .neverConvert: legacyKey = Keys.deniedWords
                case .alwaysConvert: legacyKey = Keys.alwaysConvertWords
                case .replace: legacyKey = nil
                }
                if let legacyKey, case .strings(let values) = profile.settings[legacyKey] {
                    let retained = values.filter { normalizedWordKey($0) != normalizedWordKey(rule.pattern) }
                    if retained.count != values.count {
                        profile.settings[legacyKey] = .strings(retained)
                        removed = true
                    }
                }
            }
        }
        return removed
    }

    @discardableResult
    func restoreDeletedPuntoRules() throws -> Int {
        var restored = 0
        try profileStore.update { profile in
            hydrateImportedPuntoRulesIfNeeded(&profile)
            restored = PuntoProfileMigration.restoreRemovedRules(in: &profile)
        }
        return restored
    }

    private func hydrateImportedPuntoRulesIfNeeded(_ profile: inout MultiSwitcherProfile) {
        guard profile.importedPuntoRules == nil,
              let metadata = profile.lastPuntoImport,
              !metadata.sourceSnapshotName.hasPrefix("/"),
              !metadata.sourceSnapshotName.split(separator: "/").contains("..") else { return }
        let snapshot = profileStore.backupsURL.appendingPathComponent(metadata.sourceSnapshotName)
        guard let data = try? Data(contentsOf: snapshot),
              let report = try? PuntoProfileImporter.parse(data: data) else { return }
        profile.importedPuntoRules = report.profileRules
    }

    /// Effective typed rules, including legacy list values not yet represented as rule rows.
    var automaticRules: [ProfileRule] {
        allRules
    }

    func automaticRuleDecision(typed: String, converted: String) -> ProfileRuleDecision {
        ProfileRuleEngine.evaluate(typed: typed, converted: converted, rules: automaticRules)
    }

    /// Слова, которые авто-конверсия никогда не трогает.
    var deniedWords: [String] {
        get {
            let stored = readStrings(Keys.deniedWords)
            let imported = profileStore.current.rules
                .filter { $0.enabled && $0.action == .neverConvert
                    && ($0.match == .unverifiedPunto || $0.match == .exact) }
                .map(\.pattern)
            var seen = Set<String>()
            return (imported + stored).filter {
                seen.insert(normalizedWordKey($0)).inserted
            }
        }
        set {
            write(newValue, forKey: Keys.deniedWords)
            do {
                try profileStore.update { profile in
                    profile.rules.removeAll { $0.origin == .user && $0.action == .neverConvert }
                    profile.rules.append(contentsOf: newValue.map {
                        ProfileRule(pattern: $0, match: .exact, action: .neverConvert,
                                    origin: .user, semanticStatus: .verified)
                    })
                }
            } catch {
                rslog("Rule save failed: \(error.localizedDescription)")
            }
        }
    }
    var deniedWordsSet: Set<String> {
        Set(deniedWords.map { normalizedWordKey($0) })
    }

    /// Merge imported exclusions without replacing any words already configured here.
    @discardableResult
    func mergeDeniedWords(_ importedWords: [String]) -> Int {
        var current = deniedWords
        var known = Set(current.map { normalizedWordKey($0) })
        var added = 0
        for word in importedWords {
            let cleanWord = word.precomposedStringWithCanonicalMapping
            let key = normalizedWordKey(cleanWord)
            guard !key.isEmpty, known.insert(key).inserted else { continue }
            current.append(cleanWord)
            added += 1
        }
        deniedWords = current
        return added
    }

    private func normalizedWordKey(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Слова, которые авто-конверсия переключает всегда (даже если их нет в словаре).
    var alwaysConvertWords: [String] {
        get {
            let stored = readStrings(Keys.alwaysConvertWords)
            let rules = profileStore.current.rules
                .filter { $0.enabled && $0.action == .alwaysConvert && $0.origin == .user }
                .map(\.pattern)
            var seen = Set<String>()
            return (rules + stored).filter {
                seen.insert(normalizedWordKey($0)).inserted
            }
        }
        set {
            write(newValue, forKey: Keys.alwaysConvertWords)
            do {
                try profileStore.update { profile in
                    profile.rules.removeAll { $0.origin == .user && $0.action == .alwaysConvert }
                    profile.rules.append(contentsOf: newValue.map {
                        ProfileRule(pattern: $0, match: .exact, action: .alwaysConvert,
                                    origin: .user, semanticStatus: .verified)
                    })
                }
            } catch {
                rslog("Rule save failed: \(error.localizedDescription)")
            }
        }
    }
    var alwaysConvertWordsSet: Set<String> {
        Set(alwaysConvertWords.map { normalizedWordKey($0) })
    }

    @discardableResult
    func importPuntoProfile(from sourceURL: URL) throws -> PuntoAppliedImportReport {
        try profileStore.importPuntoProfile(from: sourceURL)
    }

    // MARK: - Login Item

    private func doUpdateLoginItem(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
                rslog("Login item registered")
            } else {
                try service.unregister()
                rslog("Login item unregistered")
            }
        } catch {
            rslog("Login item error: \(error)")
        }
    }

    /// Текущий статус автозапуска (может отличаться от настройки)
    var loginItemStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }
}
