import Foundation
import MultiSwitcherCore

/// issue #22 (вариант B): умная по-словная конверсия ВЫДЕЛЕННОГО текста.
///
/// Обычный путь конвертирует всё выделение в одну сторону (по активной раскладке), поэтому
/// mixed-мусор «ghtlkj d ьшчув» чинится лишь наполовину. Здесь решаем ПО КАЖДОМУ СЛОВУ:
/// переворачиваем слово только если оно «мусор в своей письменности, но валидное слово после
/// флипа» (по системному словарю). Так mixed-мусор чинится целиком, а намеренное «iPhone
/// стоит»/«стоит,» остаются нетронутыми.
///
/// Точность важнее полноты (скептик #22):
/// • 2-буквенные — только через частотный ShortWords (NSSpellChecker на длине 2 ненадёжен);
/// • ALL-CAPS акронимы и camelCase/смешанные — пропускаем (те же гейты, что в decide);
/// • одиночную букву флипаем ТОЛЬКО в сторону реально флипнутых соседей — «z yt vjue»→
///   «я не могу» (вся фраза — не та раскладка), но «витамин c»/«число e» не трогаем (сосед
///   валиден и остался), т.к. «c»/«e» — научный символ, а не мусор.
///
/// Тумблер «Конвертировать по тексту» (A) идёт мимо — тотальный флип
/// (DynamicKeyMapping.convertBidirectional). Пары не «латиница+кириллица» — обычный путь.
enum SmartConvert {
    private enum Script { case cyr, lat, other, mixed }
    private enum WordDecision { case keep, flip(String, Script), unresolved, ambiguousShort }

    // Частотные однобуквенные слова — доп. страховка для флипа ОДИНОЧНЫХ букв по сигналу.
    private static let cyr1: Set<Character> = ["я", "в", "с", "к", "о", "у", "а", "и"]
    private static let lat1: Set<Character> = ["a", "i"]

    /// Умная по-словная конверсия выделения. При неизвестной паре или недоступном словаре
    /// сохраняет текст без изменений: smart mode никогда не становится слепым full flip.
    @MainActor
    static func selection(_ text: String, useSystemDictionary: Bool = true,
                          allowUnrecognizedSingleWord: Bool = false) -> String {
        guard let (latLang, cyrLang) = classifyPair(),
              Dict.isAvailable(latLang), Dict.isAvailable(cyrLang) else {
            return text
        }
        let toks = tokenize(text)
        // Only an explicitly verified manual selection can override an unknown word.
        // Automatic correction and multiword smart conversion remain dictionary based.
        let singleSelectedWord = allowUnrecognizedSingleWord && toks.filter(\.isWord).count == 1
        var results = [String?](repeating: nil, count: toks.count)
        var pending: [Int] = []                  // неразрешённые токены — решаем в пасе 2 по сигналу
        var ambiguousShorts = Set<Int>()
        var flipDirections = [Script?](repeating: nil, count: toks.count)
        var flippedCyr = 0, flippedLat = 0

        // Пас 1 — валидные оставляем, распознанный мусор флипаем и считаем направление.
        for (i, tok) in toks.enumerated() {
            guard tok.isWord else { results[i] = tok.str; continue }
            switch decideWord(tok.str, latLang: latLang, cyrLang: cyrLang,
                              useSystemDictionary: useSystemDictionary) {
            case .keep:
                results[i] = tok.str
            case let .flip(s, toScript):
                results[i] = s
                flipDirections[i] = toScript
                if toScript == .cyr { flippedCyr += 1 } else if toScript == .lat { flippedLat += 1 }
            case .unresolved:
                if singleSelectedWord, let converted = manualSingleWordFlip(tok.str) {
                    results[i] = converted
                } else {
                    pending.append(i)
                }
            case .ambiguousShort:
                pending.append(i)
                ambiguousShorts.insert(i)
            }
        }

        // Сигнал — направление РЕАЛЬНО флипнутых соседей (не оставленных валидными): если всё
        // выделение флипается в одну сторону, значит это не та раскладка целиком → дотягиваем
        // и неразрешённые токены («до», имена, одиночные буквы) туда же. «z yt vjue»→«я не могу»,
        // «иду до дома», «Вася пришёл». Но «iPhone стоит»/«витамин c» — 0 флипов → сигнала нет →
        // не трогаем. Разнобой (оба скрипта флипались) → сигнала нет.
        let target: Script? = (flippedCyr > 0 && flippedLat == 0) ? .cyr
                            : (flippedLat > 0 && flippedCyr == 0) ? .lat : nil

        // Пас 2 — неразрешённые по сигналу.
        for i in pending {
            if !ambiguousShorts.contains(i) {
                results[i] = signalFlip(toks[i].str, target: target, latLang: latLang, cyrLang: cyrLang)
            } else if let target,
                      hasConfirmedWordsOnBothSides(of: i, target: target, tokens: toks,
                                                   flipDirections: flipDirections) {
                results[i] = signalFlip(toks[i].str, target: target, latLang: latLang, cyrLang: cyrLang)
            } else {
                results[i] = toks[i].str
            }
        }
        return results.map { $0 ?? "" }.joined()
    }

    /// Ambiguous two-letter words change only when independently confirmed corrections
    /// sit immediately on both sides; this keeps standalone `kb` and code-like tokens safe.
    private static func hasConfirmedWordsOnBothSides(
        of index: Int,
        target: Script,
        tokens: [(isWord: Bool, str: String)],
        flipDirections: [Script?]
    ) -> Bool {
        let left = tokens.indices[..<index].reversed().first(where: { tokens[$0].isWord })
        let right = tokens.indices[(index + 1)...].first(where: { tokens[$0].isWord })
        guard let left, let right else { return false }
        return flipDirections[left] == target && flipDirections[right] == target
    }

    @MainActor
    static func hasAmbiguousShortWordCorrection(original: String, corrected: String) -> Bool {
        guard let (latLang, cyrLang) = classifyPair() else { return false }
        let before = tokenize(original).filter { $0.isWord }.map { $0.str }
        let after = tokenize(corrected).filter { $0.isWord }.map { $0.str }
        guard before.count == after.count,
              let latinShort = ShortWords.common(latLang),
              let cyrillicShort = ShortWords.common(cyrLang) else { return false }
        for (source, target) in zip(before, after) {
            guard source.count == 2, target.count == 2,
                  source.allSatisfy(\.isLetter), target.allSatisfy(\.isLetter),
                  source.caseInsensitiveCompare(target) != .orderedSame else { continue }
            let fromScript = dominantScript(source)
            let sourceWords = fromScript == .lat ? latinShort : cyrillicShort
            let targetWords = fromScript == .lat ? cyrillicShort : latinShort
            if sourceWords.contains(source.lowercased()), targetWords.contains(target.lowercased()) {
                return true
            }
        }
        return false
    }

    /// Решение по слову. .flip несёт письменность РЕЗУЛЬТАТА (сигнал для пасса 2); .unresolved —
    /// кандидат на флип по сигналу соседей (мусор в своём скрипте, но словарём не подтверждён).
    @MainActor
    private static func decideWord(_ w: String, latLang: String, cyrLang: String,
                                   useSystemDictionary: Bool) -> WordDecision {
        let core = letterCore(w)
        let script = dominantScript(core)
        guard core.count >= 1, script != .other else { return .keep }

        let whole = DynamicKeyMapping.convertBidirectional(w)
        let mappedCore = letterCore(whole)
        switch SettingsManager.shared.automaticRuleDecision(typed: w, converted: whole) {
        case .neverConvert:
            return .keep
        case .alwaysConvert:
            let target = dominantScript(mappedCore)
            return whole == w || target == .mixed || target == .other ? .keep : .flip(whole, target)
        case .replace(let replacement):
            let target = dominantScript(letterCore(replacement))
            return target == .mixed || target == .other ? .keep : .flip(replacement, target)
        case .none:
            break
        }

        // Acronyms stay protected; known mixed-case product names are handled explicitly.
        if LayoutDetector.isAllCaps(core) { return .keep }
        switch LayoutCorrectionEngine.trustedTermDecision(typed: core, converted: mappedCore) {
        case .preserve:
            return .keep
        case .convert:
            // Recognition is case-insensitive; replacement preserves the case actually
            // typed: шзрщту → iphone, шЗрщту → iPhone. Correct names stay byte-for-byte.
            return .flip(replacingLetterCore(in: w, with: mappedCore), .lat)
        case nil:
            break
        }
        if LayoutDetector.hasInternalUppercase(core) { return .keep }

        if script == .mixed {
            guard let cyrCandidate = DynamicKeyMapping.convertMixedScript(w, towardLang: cyrLang),
                  let latCandidate = DynamicKeyMapping.convertMixedScript(w, towardLang: latLang),
                  let candidate = LayoutCorrectionEngine.uniqueMixedCandidate(
                    typed: w,
                    currentLanguage: cyrLang,
                    oppositeLanguage: latLang,
                    currentCandidate: cyrCandidate,
                    oppositeCandidate: latCandidate,
                    isValidWord: { text, lang in
                        let word = letterCore(text).lowercased()
                        guard word.count >= 2 && Dict.isAvailable(lang) else { return false }
                        return isValidWord(word, lang: lang, useSystemDictionary: useSystemDictionary)
                    }
                  ) else { return .unresolved }
            return .flip(candidate.text, candidate.language == cyrLang ? .cyr : .lat)
        }

        let wordLang = (script == .cyr) ? cyrLang : latLang
        let flipLang = (script == .cyr) ? latLang : cyrLang
        let flippedScript: Script = (script == .cyr) ? .lat : .cyr

        // 1 буква — по словарю не решаемо; только по сигналу соседей (пас 2).
        if core.count == 1 { return .unresolved }

        // 2 буквы — только частотный список (NSSpellChecker на длине 2 ненадёжен), как decide.
        if core.count == 2 {
            let currentCommon = ShortWords.common(wordLang)?.contains(core.lowercased()) == true
            let whole = DynamicKeyMapping.convertBidirectional(w)
            let wc = letterCore(whole)
            let oppositeCommon = wc.count == 2
                && ShortWords.common(flipLang)?.contains(wc.lowercased()) == true
            if currentCommon && oppositeCommon { return .ambiguousShort }
            if currentCommon { return .keep }
            if oppositeCommon {
                return .flip(whole, flippedScript)
            }
            return .unresolved   // «до», «уж» и т.п. — не в списке → по сигналу
        }

        // 3+ — словарь. Уже валидное слово своего языка → не трогаем (iPhone, стоит).
        if isValidWord(core.lowercased(), lang: wordLang, useSystemDictionary: useSystemDictionary) {
            return .keep
        }
        // (1) флип целиком — ловит «ёлка» (`krf), «делю» (ltk.), «продолжение».
        let wc = letterCore(whole)
        if wc.count >= 2, wc.allSatisfy({ $0.isLetter }),
           isValidWord(wc.lowercased(), lang: flipLang, useSystemDictionary: useSystemDictionary) {
            return .flip(punctFixup(original: w, flipped: whole, towardLang: flipLang), flippedScript)
        }
        // (2) со снятым хвостом реальной пунктуации — «ghtlkj;tybt,» → «продолжение» + «,».
        let (body, suffix) = splitTrailingNonLetters(w)
        if !suffix.isEmpty, !body.isEmpty {
            let bflip = DynamicKeyMapping.convertBidirectional(body)
            let bc = letterCore(bflip)
            if bc.count >= 2, bc.allSatisfy({ $0.isLetter }),
               isValidWord(bc.lowercased(), lang: flipLang, useSystemDictionary: useSystemDictionary) {
                return .flip(bflip + DynamicKeyMapping.punctThroughPair(suffix, towardLang: flipLang), flippedScript)
            }
        }
        return .unresolved   // имя/бренд/термин, словарём не подтверждён → по сигналу
    }

    @MainActor
    private static func isValidWord(_ word: String, lang: String, useSystemDictionary: Bool) -> Bool {
        useSystemDictionary
            ? Dict.isValidWord(word, lang: lang)
            : Dict.isValidWordForAutomaticPath(word, lang: lang)
    }

    @MainActor
    private static func manualSingleWordFlip(_ word: String) -> String? {
        guard (3...128).contains(word.count), word.allSatisfy(\.isLetter),
              !LayoutDetector.isAllCaps(word), !LayoutDetector.hasInternalUppercase(word) else { return nil }
        let source = dominantScript(word)
        guard source == .cyr || source == .lat else { return nil }
        let converted = DynamicKeyMapping.convertBidirectional(word)
        let target = dominantScript(converted)
        guard converted != word, converted.allSatisfy(\.isLetter),
              (source == .cyr && target == .lat) || (source == .lat && target == .cyr) else { return nil }
        return converted
    }

    /// Флипаем неразрешённый токен ТОЛЬКО при явном сигнале (соседи флипнулись в одну сторону)
    /// и только если сам токен в ДРУГОМ скрипте (флип ведёт к target). Флипаем лишь буквенное
    /// ядро, окружающую пунктуацию сохраняем: «lj,»→«до,», «z»→«я». Одиночную букву дополнительно
    /// страхуем частотным списком (её флип должен быть частым 1-букв. словом target).
    /// ВАЖНО: главная защита научных «c»/«e» — ОТСУТСТВИЕ сигнала (сосед-слово валиден → target
    /// nil → сюда не входим). При СИЛЬНОМ сигнале «c»/«e» всё же флипаются (c→с, e→у — частотные
    /// 1-букв. слова), т.е. это часть агрессивности «умной» (по решению владельца, вариант A).
    private static func signalFlip(_ orig: String, target: Script?, latLang: String, cyrLang: String) -> String {
        guard let target else { return orig }
        var lead = "", trail = ""
        var chars = Array(orig)
        while let f = chars.first, !f.isLetter { lead.append(f); chars.removeFirst() }
        while let l = chars.last, !l.isLetter { trail = String(l) + trail; chars.removeLast() }
        let core = String(chars)
        guard !core.isEmpty, dominantScript(core) != target else { return orig }
        // Скептик 3.2.0 (#4/#6): 3+ буквенные неразрешённые по сигналу НЕ тянем — раз словарь их
        // флип не подтвердил (иначе были бы .flip в decideWord), это скорее иностранное слово/
        // бренд/термин (Github, гугл), а не мусор. Реальные слова и известные имена (Вася,
        // Комаров) словарь ловит в decideWord. Тянем только 1–2 буквы («до», «z») — их словарь
        // на длине 1–2 надёжно не решает, а частотные функц. слова важно дочинить.
        guard core.count <= 2 else { return orig }
        let flipped = DynamicKeyMapping.convertBidirectional(core)
        if core.count == 1 {                                    // одиночная — доп. страховка
            guard let fch = letterCore(flipped).first,
                  (target == .cyr ? cyr1 : lat1).contains(Character(fch.lowercased())) else { return orig }
        }
        // issue #33: окружающие знаки — сквозь направленную карту (знак→знак; Русская — ПК).
        let toward = (target == .cyr) ? cyrLang : latLang
        return DynamicKeyMapping.punctThroughPair(lead, towardLang: toward)
             + flipped
             + DynamicKeyMapping.punctThroughPair(trail, towardLang: toward)
    }

    // MARK: - Helpers

    /// Классификация пары раскладок: (латинский язык, кириллический язык) или nil, если пара
    /// не «латиница+кириллица» (тогда умный путь неприменим).
    @MainActor
    private static func classifyPair() -> (latLang: String, cyrLang: String)? {
        guard let (a, b) = LayoutSwitcher.currentAndOppositeLanguage() else { return nil }
        let aCyr = isCyrillicLang(a), bCyr = isCyrillicLang(b)
        let aLat = isLatinLang(a), bLat = isLatinLang(b)
        if aCyr && bLat { return (b, a) }
        if bCyr && aLat { return (a, b) }
        return nil
    }

    private static let cyrillicLangs: Set<String> = ["ru", "uk", "be", "bg", "sr", "mk", "kk", "ky", "mn", "tg"]
    private static func isCyrillicLang(_ lang: String) -> Bool {
        cyrillicLangs.contains(String(lang.lowercased().prefix(2)))
    }
    // Латинская письменность = не кириллица и не иврит/греческий/армянский/грузинский/арабский.
    private static let nonLatinLangs: Set<String> = ["he", "iw", "el", "hy", "ka", "ar", "fa", "yi"]
    private static func isLatinLang(_ lang: String) -> Bool {
        let two = String(lang.lowercased().prefix(2))
        return !cyrillicLangs.contains(two) && !nonLatinLangs.contains(two)
    }

    private static func dominantScript(_ s: String) -> Script {
        var cyr = 0, lat = 0
        for u in s.unicodeScalars {
            if u.value >= 0x0400 && u.value <= 0x04FF { cyr += 1 }
            else if (u.value >= 0x41 && u.value <= 0x5A) || (u.value >= 0x61 && u.value <= 0x7A) { lat += 1 }
        }
        if cyr > 0 && lat > 0 { return .mixed }
        if cyr > 0 { return .cyr }
        if lat > 0 { return .lat }
        return .other
    }

    /// Слово без окружающих не-букв (для проверки по словарю). «`krf»→«krf», «дел.»→«дел».
    private static func letterCore(_ s: String) -> String {
        var chars = Array(s)
        while let f = chars.first, !f.isLetter { chars.removeFirst() }
        while let l = chars.last, !l.isLetter { chars.removeLast() }
        return String(chars)
    }

    private static func replacingLetterCore(in text: String, with replacement: String) -> String {
        var leading = ""
        var body = text
        while let first = body.first, !first.isLetter {
            leading.append(first)
            body.removeFirst()
        }
        let (core, suffix) = splitTrailingNonLetters(body)
        guard !core.isEmpty else { return text }
        return leading + replacement + suffix
    }

    /// issue #33: пост-обработка флипа-целиком. Позиции, где НЕ-буква ПРЕВРАТИЛАСЬ в букву
    /// («ltk.» → «делю»: . → ю), подтверждены словарём вместе со словом — не трогаем.
    /// Позиции, где не-буква ОСТАЛАСЬ не-буквой (двунаправленная карта её не разрешила или
    /// разрешила коллизией не туда), прогоняем через направленную карту знак→знак:
    /// «tkrb?» на Русской — ПК → «елки,». Несовпадение длин (прекомпоза) — отдаём как есть.
    private static func punctFixup(original: String, flipped: String, towardLang: String) -> String {
        let o = Array(original), f = Array(flipped)
        guard o.count == f.count, zip(o, f).contains(where: { !$0.0.isLetter && !$0.0.isNumber && !$0.1.isLetter }) else {
            return flipped
        }
        return String(zip(o, f).map { oc, fc in
            guard !oc.isLetter, !oc.isNumber, !fc.isLetter else { return fc }
            let mapped = DynamicKeyMapping.punctThroughPair(String(oc), towardLang: towardLang)
            return mapped.count == 1 ? mapped.first! : fc
        })
    }

    /// Отделяет хвост НЕ-букв (реальную пунктуацию) от тела слова: «прод,»→(«прод»,«,»).
    private static func splitTrailingNonLetters(_ s: String) -> (body: String, suffix: String) {
        var body = Array(s); var suffix = ""
        while let l = body.last, !l.isLetter { suffix = String(l) + suffix; body.removeLast() }
        return (String(body), suffix)
    }

    /// Разбивает текст на чередующиеся куски: слова (не-пробелы) и разделители (пробелы),
    /// сохраняя всё — сборка обратно даёт исходную длину.
    private static func tokenize(_ s: String) -> [(isWord: Bool, str: String)] {
        var out: [(Bool, String)] = []
        var cur = ""
        var curWS: Bool? = nil
        for ch in s {
            let ws = ch.isWhitespace
            if let w = curWS {
                if ws == w { cur.append(ch) }
                else { out.append((!w, cur)); cur = String(ch); curWS = ws }
            } else {
                curWS = ws; cur = String(ch)
            }
        }
        if let w = curWS, !cur.isEmpty { out.append((!w, cur)) }
        return out
    }
}
