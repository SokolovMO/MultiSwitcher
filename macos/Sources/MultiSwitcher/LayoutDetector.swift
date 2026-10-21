import Foundation
import MultiSwitcherCore

enum LayoutVerdict: Equatable { case switchToConverted, keep, undecided }

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
    /// The policy also recognizes the US Shift+6 glyph; its Russian key position is colon.
    static func splitTrailingPunctuation(_ s: String) -> (coreLength: Int, suffix: String) {
        KeyboardPunctuationPolicy.splitTrailing(from: s)
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
