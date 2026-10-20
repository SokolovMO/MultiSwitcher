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

enum LayoutVerdict { case switchToConverted, keep, undecided }

/// Решает, набрано ли слово в неправильной раскладке. Точность важнее полноты:
/// при любой неуверенности → .undecided (ничего не делаем). Ручной триггер остаётся.
enum LayoutDetector {
    @MainActor
    static func decide(typed: String, converted: String, currentLang: String, otherLang: String, capsLock: Bool) -> LayoutVerdict {
        // always-convert — ЯВНЫЙ override: матчим по СКОНВЕРТИРОВАННОЙ (целевой) форме.
        // В список кладётся целевое слово (напр. «жоппа»); так правильно набранное слово
        // не даёт пинг-понг. Жёсткие гейты (secure/denied-app/never) проверены ДО decide.
        if AutoSwitchPolicy.isAlwaysConvert(converted) { return .switchToConverted }

        if !capsLock {
            if isAllCaps(typed) { return .undecided }
            switch LayoutCorrectionEngine.trustedTermDecision(typed: typed, converted: converted) {
            case .preserve:
                return .keep
            case .convert:
                return .switchToConverted
            case nil:
                break
            }
        }

        // --- мягкие вето (дёшево, до словаря) ---
        // 1 буква — не трогаем никогда (неоднозначность запредельная). 2 буквы —
        // отдельная ветка ниже через частотный список (ShortWords), т.к. на такой длине
        // системный словарь ненадёжен; 3+ — обычный путь через NSSpellChecker.
        guard typed.count >= 2 else { return .undecided }
        // Internal hyphens join a compound token (for example `rfr-nj` → `как-то`).
        // Check each segment separately with the same conservative dictionary policy;
        // leading, trailing, repeated hyphens and digits remain untouched.
        if typed.contains("-") || converted.contains("-") {
            switch HyphenatedTokenPolicy.decide(
                typed: typed,
                converted: converted,
                currentLanguage: currentLang,
                targetLanguage: otherLang,
                isValidWord: { word, language in
                    Dict.isValidWordForAutomaticPath(word, lang: language)
                }
            ) {
            case .convert: return .switchToConverted
            case .keep: return .keep
            case .undecided: return .undecided
            }
        }
        // Обычный путь — набранное целиком буквенное. Плюс (issue #22, п.3) случай «буквы
        // на клавишах-пунктуации»: ё/х/ъ/ж/э/б/ю в ЙЦУКЕН живут на ` [ ] ; ' , . — тогда
        // typed содержит эти знаки, но КОНВЕРСИЯ целиком буквенная, и решает словарь ниже.
        // Хвостовые . , ; : уже отщеплены вызывающим (#15) + walk неоднозначности, поэтому
        // сюда доходит только начальная/срединная пунктуация («`krf»→ёлка, «rf;tncz»→
        // кажется) — там трактовки-как-знак-препинания нет, а «дел.»/«думаю» отсеяны выше.
        guard typed.allSatisfy({ $0.isLetter }) || converted.allSatisfy({ $0.isLetter }) else {
            return .undecided // цифры/URL/код/почта/эмодзи
        }
        // Под Caps Lock весь текст в ВЕРХНЕМ регистре — это НЕ акроним и НЕ camelCase,
        // поэтому эти два вето применяем только когда Caps Lock выключен.
        if !capsLock {
            // Mixed-script input is evaluated below by the target dictionary.
            // CamelCase remains protected because it is a strong code/name signal.
            if hasInternalUppercase(typed) { return .undecided }
            if looksLikeCodeIdentifier(typed) && !LayoutCorrectionEngine.isMixedScript(typed) {
                return .undecided
            }
        }

        let cur = String(currentLang.prefix(2))
        let oth = String(otherLang.prefix(2))

        // --- Кросс-скрипт пары с ивритом (3.0) ---
        // Системный ивритский словарь macOS для детекта БЕСПОЛЕЗЕН: он принимает любой
        // набор букв как «валидное слово» (проверено эмпирически), двусторонняя проверка
        // на стороне иврита невозможна. Поэтому конвертим ТОЛЬКО при положительном
        // сигнале второй (не-ивритской) стороны — её собственным словарём:
        //   • набрано в иврит-раскладке, а конверсия — валидное слово второй раскладки
        //     → задумана она, конвертим;
        //   • набрано во второй раскладке и это её валидное слово → keep (не трогаем);
        //   • всё остальное (имена, бренды, опечатки, «задуман иврит») → .undecided:
        //     направление «в иврит» без словаря честно не решаемо — точность важнее
        //     полноты. Ручной триггер конвертирует любые пары всегда.
        // Второй словарь берём по ЯЗЫКУ ПАРЫ (ru/de/fr/…), не хардкодим en — иначе
        // пара русский+иврит конвертила бы каждое валидное русское слово в иврит
        // (ревью-находка июльского аудита).
        if isHebrew(cur) || isHebrew(oth) {
            guard typed.count >= 3 else { return .undecided }              // короткий частотный сигнал для иврита не строим
            let hebrewIsCurrent = isHebrew(cur)
            let sideLang = hebrewIsCurrent ? oth : cur
            guard !isHebrew(sideLang), Dict.isAvailable(sideLang) else { return .undecided }
            if hebrewIsCurrent {
                // NSSpellChecker токенизирует («привет!» для него валиден), а часть ивритских
                // букв живёт на пунктуационных клавишах — EN-образ КОРРЕКТНОГО иврита может
                // получиться «слово + пунктуация» и ложно пройти словарь (ревью-находка,
                // тот же класс, что «думаю vs дума.» в 2.7.0). Словарю отдаём только
                // целиком буквенный образ; иначе .undecided — ручной триггер работает.
                guard converted.allSatisfy({ $0.isLetter }) else { return .undecided }
                return Dict.isValidWordForAutomaticPath(converted.lowercased(), lang: sideLang)
                    ? .switchToConverted : .undecided
            }
            return Dict.isValidWordForAutomaticPath(typed.lowercased(), lang: sideLang) ? .keep : .undecided
        }

        // --- Короткие (2-буквенные) слова: позитивный частотный сигнал (3.1, issue #22) ---
        // NSSpellChecker на длине 2 принимает почти любой набор букв за «слово», поэтому
        // обычная двусторонняя проверка тут ненадёжна (ради этого и стоял гейт count>=3).
        // Вместо словаря — компактный список ЧАСТЫХ коротких слов (ShortWords), строго как
        // позитивный сигнал: конвертим 2 буквы ТОЛЬКО если конверсия — частое слово целевого
        // языка, а набранное — не частое слово текущего (симметрия как у иврит-ветки).
        // Коллизий «частое↔частое» нет (аудит образов раскладки). Пары с языком без списка
        // сюда не попадают → 2-буквенные, как и раньше, не трогаются.
        if typed.count == 2 {
            switch ShortWordPolicy.decide(
                typed: typed, converted: converted, currentLanguage: cur, otherLanguage: oth
            ) {
            case .convert:
                return .switchToConverted
            case .keep:
                return .keep
            case .undecided:
                return .undecided
            }
        }

        // Словарь — без учёта регистра (Caps Lock не должен мешать определению слова).
        guard Dict.isAvailable(oth) else { return .undecided }
        guard Dict.isValidWordForAutomaticPath(converted.lowercased(), lang: oth) else {
            rslog("auto: keep target-dictionary")
            return .keep
        }
        if Dict.isAvailable(cur), Dict.isValidWordForAutomaticPath(typed.lowercased(), lang: cur) {
            rslog("auto: keep source-dictionary")
            return .keep
        }
        return .switchToConverted
    }

    /// issue #15: отщепляет прилипшую к концу слова пунктуацию ("ghbdtn," → ядро 6 + ",").
    /// Ядро детектится и конвертится как обычно, хвост возвращается в поле ЛИТЕРАЛОМ —
    /// конвертировать его по кейкодам нельзя: клавиша ',' в EN — это 'б' в RU, а
    /// запятая RU (Shift+6) в EN — '^'. Набор консервативный: цифры, дефис, @/#
    /// НЕ отщепляем — для URL/кода/почты вето детектора отрабатывает по делу.
    /// Кавычки ' и " исключены сознательно: смарт-пунктуация приложений подменяет их
    /// типографскими, а на dead-key раскладках (U.S. International) апостроф — dead key;
    /// оба случая ломают счёт/литеральность. «…»/«»/– недостижимы из буфера (Option-слой).
    /// ВАЖНО: '.', ',', ';', ':' в EN — клавиши букв ю/б/ж/Ж в ЙЦУКЕН, поэтому вызывающий
    /// ОБЯЗАН проверить полную конверсию по словарю (неоднозначность «думаю» vs «дума.»).
    /// Также ` [ ] — клавиши ё/х/ъ: отщепляем их с хвоста, чтобы тот же walk неоднозначности
    /// сработал симметрично (issue #22-скептик: иначе «ружьё»/«цех» шли бы мимо проверки).
    static func splitTrailingPunctuation(_ s: String) -> (coreLength: Int, suffix: String) {
        let punct: Set<Character> = [",", ".", "!", "?", ";", ":", ")", "`", "[", "]"]
        var core = s[...]
        while let last = core.last, punct.contains(last) { core = core.dropLast() }
        return (core.count, String(s.dropFirst(core.count)))
    }

    /// Язык — иврит (BCP-47 `he` или устаревший `iw`). 3.0: гейт кросс-скрипт-детекта.
    static func isHebrew(_ lang: String) -> Bool {
        let two = lang.lowercased().prefix(2)
        return two == "he" || two == "iw"
    }

    static func isAllCaps(_ s: String) -> Bool {
        s == s.uppercased() && s != s.lowercased()
    }

    static func hasInternalUppercase(_ s: String) -> Bool {
        s.enumerated().contains { index, character in index > 0 && character.isUppercase }
    }

    /// Похоже на программный идентификатор: внутренняя заглавная (camelCase/PascalCase)
    /// или смешение латиницы и кириллицы в одном токене → почти всегда код, не слово.
    static func looksLikeCodeIdentifier(_ s: String) -> Bool {
        for (i, c) in s.enumerated() where i > 0 && c.isUppercase { return true }
        var hasLatin = false, hasCyrillic = false
        for u in s.unicodeScalars {
            switch u.value {
            case 0x41...0x5A, 0x61...0x7A: hasLatin = true
            case 0x0400...0x04FF: hasCyrillic = true
            default: break
            }
        }
        return hasLatin && hasCyrillic
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
