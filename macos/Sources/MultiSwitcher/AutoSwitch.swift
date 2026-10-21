import AppKit
import Carbon
import IOKit
import MultiSwitcherCore

/// Local spelling lookup combines bundled RU/EN words with AppleSpell when available.
/// Custom open word lists are read on a utility task, outside the keyboard event path.
enum Dict {
    @MainActor private static let checker = NSSpellChecker.shared
    /// Кэш списка словарей: availableLanguages ходит в AppleSpell — не дёргаем на каждое слово.
    @MainActor private static var cachedLanguages: [String]?
    /// Spell checks run on the main actor at word boundaries. A small time-bounded cache
    /// prevents repeated XPC calls for common words without growing with a long session.
    @MainActor private static var wordCache: [String: Bool] = [:]
    @MainActor private static var cacheFlushedAt = Date.timeIntervalSinceReferenceDate
    @MainActor private static var bundledLexicons: [String: WordLexicon] = [:]
    @MainActor private static var thematicLexicons: [String: WordLexicon] = [:]
    @MainActor private static var enabledThemes: Set<String> = ["technology", "design", "brands", "slang"]
    @MainActor private static var lexiconLoadStarted = false

    @MainActor static func isAvailable(_ lang: String) -> Bool {
        let two = String(lang.prefix(2))
        return bundledLexicons[two] != nil || languages().contains { String($0.prefix(2)) == two }
    }

    /// Fast automatic-input check: never starts a synchronous AppleSpell/XPC request.
    /// Bundled dictionaries are authoritative for RU/EN; other languages can use only
    /// a result already cached by a non-keyboard spelling check.
    @MainActor static func isValidWordForAutomaticPath(_ word: String, lang: String) -> Bool {
        let language = String(lang.prefix(2)).lowercased()
        let normalized = word.precomposedStringWithCanonicalMapping.lowercased()
        if bundledLexicons[language]?.contains(normalized) == true { return true }
        if enabledThemes.contains(where: { thematicLexicons["\($0).\(language)"]?.contains(normalized) == true }) {
            return true
        }
        let key = "\(lang.lowercased())\u{0}\(normalized)"
        return wordCache[key] == true
    }

    @MainActor private static func languages() -> [String] {
        if let cached = cachedLanguages { return cached }
        let langs = checker.availableLanguages
        cachedLanguages = langs
        return langs
    }

    /// Прогрев: первое обращение к NSSpellChecker поднимает XPC-процесс AppleSpell
    /// (сотни мс на main) — без прогрева этот фриз пришёлся бы на первый пробел
    /// пользователя после запуска. Вызывается отложенно из applicationDidFinishLaunching.
    @MainActor static func warmUp() {
        if !lexiconLoadStarted {
            lexiconLoadStarted = true
            Task.detached(priority: .utility) {
                let loaded = loadBundledLexicons()
                let themed = loadBundledThematicLexicons()
                await MainActor.run {
                    bundledLexicons = loaded
                    thematicLexicons = themed
                    enabledThemes = SettingsManager.shared.enabledDictionaryThemes
                    wordCache.removeAll(keepingCapacity: true)
                    cacheFlushedAt = Date.timeIntervalSinceReferenceDate
                    rslog("dictionary: bundled packs loaded en=\(loaded["en"]?.count ?? 0) ru=\(loaded["ru"]?.count ?? 0) thematic=\(themed.count)")
                }
            }
        }
        _ = languages()
        _ = isValidWord("тест", lang: "ru")
        _ = isValidWord("test", lang: "en")
    }

    @MainActor static func setEnabledThemes(_ themes: Set<String>) {
        enabledThemes = themes
        wordCache.removeAll(keepingCapacity: true)
    }

    /// true — слово есть в словаре языка (орфография корректна).
    @MainActor static func isValidWord(_ word: String, lang: String) -> Bool {
        guard isAvailable(lang) else { return false }
        let now = Date.timeIntervalSinceReferenceDate
        if now - cacheFlushedAt >= 300 || wordCache.count >= 4096 {
            wordCache.removeAll(keepingCapacity: true)
            cacheFlushedAt = now
        }
        let normalized = word.precomposedStringWithCanonicalMapping.lowercased()
        let key = "\(lang.lowercased())\u{0}\(normalized)"
        if let cached = wordCache[key] { return cached }
        let language = String(lang.prefix(2))
        let bundledMatch = bundledLexicons[language]?.contains(normalized) == true
        let themedMatch = enabledThemes.contains { theme in
            thematicLexicons["\(theme).\(language)"]?.contains(normalized) == true
        }
        if bundledMatch || themedMatch {
            // The packaged, versioned list is already positive evidence. Avoid an
            // AppleSpell/XPC round trip for common RU/EN words on the main event path.
            wordCache[key] = true
            return true
        }
        guard languages().contains(where: { String($0.prefix(2)) == String(lang.prefix(2)) }) else {
            wordCache[key] = false
            return false
        }
        let range = checker.checkSpelling(of: normalized, startingAt: 0, language: lang,
                                          wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        let valid = range.location == NSNotFound
        wordCache[key] = valid
        return valid
    }

    nonisolated private static func loadBundledLexicons() -> [String: WordLexicon] {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Lexicons", isDirectory: true) else {
            return [:]
        }
        var result: [String: WordLexicon] = [:]
        for language in ["en", "ru"] {
            let url = directory.appendingPathComponent("\(language).words")
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            result[language] = WordLexicon(wordList: contents)
        }
        return result
    }

    nonisolated private static func loadBundledThematicLexicons() -> [String: WordLexicon] {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Lexicons/Themes", isDirectory: true) else {
            return [:]
        }
        var result: [String: WordLexicon] = [:]
        for theme in ["technology", "design", "brands", "slang"] {
            for language in ["en", "ru"] {
                let url = directory.appendingPathComponent("\(theme).\(language).words")
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
                result["\(theme).\(language)"] = WordLexicon(wordList: contents)
            }
        }
        return result
    }
}

/// Политика безопасности авто-конвертации.
enum AutoSwitchPolicy {
    /// Активен ли защищённый ввод (поле пароля, Secure Keyboard Entry в терминале) —
    /// тогда авто-конвертацию НЕ делаем (приватность; пароль не трогаем).
    static var secureInputActive: Bool { IsSecureEventInputEnabled() }

    /// Имя приложения, удерживающего защищённый ввод (Word, Terminal, менеджер
    /// паролей, loginwindow при системном запросе пароля и т.п.), или nil если
    /// определить не удалось. Читаем PID из IORegistry (то же, что `ioreg`:
    /// IOConsoleUsers → kCGSSessionSecureInputPID) и резолвим в человекочитаемое имя.
    static func secureInputHolderName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let sessions = IORegistryEntryCreateCFProperty(
            entry, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [[String: Any]] else { return nil }
        for s in sessions {
            guard let raw = s["kCGSSessionSecureInputPID"] as? Int, raw != 0 else { continue }
            let pid = pid_t(raw)
            if let app = NSRunningApplication(processIdentifier: pid)?.localizedName, !app.isEmpty {
                return app
            }
            var buf = [CChar](repeating: 0, count: 4096)      // системные процессы (loginwindow) — не GUI-приложения
            let len = proc_pidpath(pid, &buf, 4096)
            if len > 0 {
                let bytes = buf.prefix(Int(len)).map { UInt8(bitPattern: $0) }
                let name = (String(decoding: bytes, as: UTF8.self) as NSString).lastPathComponent
                if !name.isEmpty { return name }
            }
            return nil
        }
        return nil
    }

    /// Дефолтный список приложений, где авто выключено: терминалы, IDE, менеджеры
    /// паролей. Возвращается, пока пользователь не отредактировал список
    /// (см. SettingsManager.deniedApps). Запись с суффиксом "*" — префикс (весь вендор).
    static let defaultDeniedApps: [String] = [
        "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty",
        "io.alacritty", "com.github.wez.wezterm", "dev.warp.Warp-Stable", "co.zeit.hyper",
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.sublimetext.4", "com.todesktop.230313mzl4w4u92", "com.google.android.studio",
        "com.jetbrains.*",
        "com.1password.1password", "com.agilebits.onepassword7",
        "com.bitwarden.desktop", "org.keepassxc.keepassxc",
    ]

    /// Менеджеры паролей — несъёмные из списка в UI (безопасность).
    static let protectedApps: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7",
        "com.bitwarden.desktop", "org.keepassxc.keepassxc",
    ]

    /// Терминалы: в них нет OS-выделения текста, поэтому «конвертация строки» (#24) через
    /// Shift+Cmd+← не выделяет строку, а в Terminal.app клавиши протекают мусором. Для них
    /// режим «вся строка» деградирует на буферный путь (последнее слово — он в терминалах
    /// работает, backspace+перепечатка). Список — терминалы из defaultDeniedApps.
    static let terminalApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty",
        "io.alacritty", "com.github.wez.wezterm", "dev.warp.Warp-Stable", "co.zeit.hyper",
    ]
    static func isTerminalApp(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return terminalApps.contains(id)
    }

    static func isDeniedApp(_ bundleID: String?) -> Bool {
        ApplicationExclusionPolicy.isExcluded(
            bundleID: bundleID, entries: SettingsManager.shared.deniedApps, protected: protectedApps)
    }

    static func areAllActionsDisabled(_ bundleID: String?) -> Bool {
        ApplicationExclusionPolicy.isExcluded(
            bundleID: bundleID, entries: SettingsManager.shared.allActionsDeniedApps)
    }

    /// Слово в списке never-convert (обе стороны пары, без регистра).
    static func isDeniedWord(_ typed: String, _ converted: String) -> Bool {
        SettingsManager.shared.automaticRuleDecision(typed: typed, converted: converted) == .neverConvert
    }

    /// Слово в списке always-convert — матчим по СКОНВЕРТИРОВАННОЙ (целевой) форме.
    /// В список кладётся «целевое» слово (что должно получиться), а не мусор раскладки —
    /// иначе правильно набранное слово конвертилось бы обратно (пинг-понг).
    static func isAlwaysConvert(_ converted: String) -> Bool {
        SettingsManager.shared.automaticRuleDecision(typed: "", converted: converted) == .alwaysConvert
    }

    /// Клиенты удалённого рабочего стола: когда такое окно в фокусе, текст живёт
    /// на ДРУГОЙ машине — наш инстанс должен молчать и уступить удалённому MultiSwitcher.
    static let remoteClients: Set<String> = [
        "com.apple.ScreenSharing",   // Apple «Общий экран» / Screen Sharing.app
        "com.apple.RemoteDesktop",   // Apple Remote Desktop
    ]

    static func isRemoteDesktopClient(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return remoteClients.contains(id)
    }

    /// Правило «уступи удалёнке»: режим удалённого стола включён И в фокусе клиент
    /// удалёнки → этот инстанс ничего не делает (ни триггер, ни авто), чтобы не
    /// дублировать работу инстанса на контролируемой машине.
    static var shouldDeferToRemoteClient: Bool {
        guard SettingsManager.shared.remoteDesktopMode else { return false }
        return isRemoteDesktopClient(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
}
