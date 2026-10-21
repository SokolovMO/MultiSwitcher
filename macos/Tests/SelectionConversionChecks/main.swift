import Foundation
import MultiSwitcherCore

@main
struct SelectionConversionChecks {
    @MainActor static func main() throws {
        try Dict.load(baseDirectory: URL(fileURLWithPath: CommandLine.arguments[1]),
                      themeDirectory: URL(fileURLWithPath: CommandLine.arguments[2]))
        guard LayoutSwitcher.installedLayouts().count == 2 else {
            fatalError("Native Apple Russian and US keyboard layouts are required")
        }

        var failures = 0
        var assertions = 0
        func check(_ name: String, _ actual: String, _ expected: String) {
            assertions += 1
            if actual != expected {
                failures += 1
                print("FAIL \(name): actual=\(actual.debugDescription), expected=\(expected.debugDescription)")
            }
        }
        func checkVerdict(_ name: String, _ actual: LayoutVerdict, _ expected: LayoutVerdict) {
            assertions += 1
            if actual != expected {
                failures += 1
                print("FAIL \(name): actual=\(actual), expected=\(expected)")
            }
        }

        let settings = SettingsManager.shared
        settings.smartConversion = true
        settings.convertByText = false
        let converter = TextConverter()
        check("smart mode flags", "\(settings.smartConversion)/\(settings.convertByText)", "true/false")
        check("native keyboard map", DynamicKeyMapping.convertBidirectional("щзуткщгеук"), "openrouter")
        check("openrouter is packaged vocabulary", String(Dict.isValidWord("openrouter", lang: "en")), "true")

        for (name, typed, converted, current, other, expected) in [
            ("automatic Russian typo", "руддщ", "hello", "ru", "en", LayoutVerdict.switchToConverted),
            ("correct Russian stays", "привет", "ghbdtn", "ru", "en", LayoutVerdict.keep),
            ("correct English stays", "hello", "руддщ", "en", "ru", LayoutVerdict.keep),
            ("technical product typo", "шзрщту", "iphone", "ru", "en", LayoutVerdict.switchToConverted),
            ("technical product casing", "шЗрщту", "iPhone", "ru", "en", LayoutVerdict.switchToConverted),
            ("correct iPhone stays", "iPhone", "шЗщрту", "en", "ru", LayoutVerdict.keep),
            ("bad typo candidate waits", "шзщту", "ipone", "ru", "en", LayoutVerdict.keep),
            ("app abbreviation converts", "фзз", "app", "ru", "en", LayoutVerdict.switchToConverted),
            ("single-letter English a waits", "a", "ф", "en", "ru", LayoutVerdict.undecided),
            ("technical term stays", "openrouter", "щзуткщгеук", "en", "ru", LayoutVerdict.keep),
        ] {
            checkVerdict(name, LayoutDetector.decide(typed: typed, converted: converted,
                                                     currentLang: current, otherLang: other,
                                                     capsLock: false), expected)
        }

        let mixedInput = "ghbkj;ение"
        let mixedRussian = DynamicKeyMapping.convertMixedScript(mixedInput, towardLang: "ru") ?? ""
        let mixedEnglish = DynamicKeyMapping.convertMixedScript(mixedInput, towardLang: "en") ?? ""
        check("mixed candidate preserves the Russian fragment", mixedRussian, "приложение")
        let selectedMixed = LayoutCorrectionEngine.uniqueMixedCandidate(
            typed: mixedInput,
            currentLanguage: "ru",
            oppositeLanguage: "en",
            currentCandidate: mixedRussian,
            oppositeCandidate: mixedEnglish,
            isValidWord: { word, language in
                Dict.isValidWordForAutomaticPath(String(word.filter(\.isLetter).lowercased()), lang: language)
            }
        )
        check("mixed automatic path chooses the unique dictionary word",
              selectedMixed?.text ?? "", "приложение")

        for (word, language) in [
            ("cmd", "en"), ("keybinding", "en"), ("affordance", "en"),
            ("monospace", "en"), ("rizz", "en"), ("bussin", "en"),
            ("сдвигается", "ru"), ("душнила", "ru"),
        ] {
            check("curated terminology (word)",
                  String(Dict.isValidWordForAutomaticPath(word, lang: language)), "true")
            check("curated term stays (word)",
                  SmartConvert.selection(word, useSystemDictionary: false), word)
        }

        let examples = [
            ("щзуткщгеук", "openrouter"),
            ("ye cldbuftncz", "ye сдвигается"),
            ("ye cldbuftncz ktdfz", "ну сдвигается левая"),
            ("ye cldbuftncz ktdfz xfcnm", "ну сдвигается левая часть"),
            ("привет купи iphone", "привет купи iphone"),
            ("ghbdtn купи iphone", "привет купи iphone"),
            ("привет купи шзрщту", "привет купи iphone"),
            ("руддщ", "hello"),
            ("фзздуыскшзе", "applescript"),
            ("шзрщту", "iphone"),
            ("шЗрщту", "iPhone"),
            ("iPhone", "iPhone"),
            ("IPHONE", "IPHONE"),
        ]
        for useSystemDictionary in [true, false] {
            for (typed, expected) in examples {
                check("smart selection \(typed) system=\(useSystemDictionary)",
                      SmartConvert.selection(typed, useSystemDictionary: useSystemDictionary), expected)
            }
        }
        check("real selection route openrouter", converter.convertSelectionText("щзуткщгеук"), "openrouter")
        check("real selection route mixed phrase", converter.convertSelectionText("привет купи iphone"), "привет купи iphone")

        // Both-flags legacy state must still choose smart mode. Explicit toggles are exclusive.
        settings.seedRaw(SettingsManager.Keys.convertByText, value: true)
        check("legacy flags prefer smart", "\(settings.smartConversion)/\(settings.convertByText)", "true/false")
        check("legacy selection route", converter.convertSelectionText("привет купи iphone"), "привет купи iphone")
        settings.convertByText = true
        check("full flip disables smart", "\(settings.smartConversion)/\(settings.convertByText)", "false/true")
        check("full flip remains available", converter.convertSelectionText("щзуткщгеук"), "openrouter")
        settings.smartConversion = true
        check("smart disables full flip", "\(settings.smartConversion)/\(settings.convertByText)", "true/false")

        let unknown = "zerodrifter"
        let mistyped = DynamicKeyMapping.convertBidirectional(unknown)
        check("unknown fixture EN", String(Dict.isValidWord(unknown, lang: "en")), "false")
        check("unknown fixture RU", String(Dict.isValidWord(mistyped, lang: "ru")), "false")
        check("default unknown remains", SmartConvert.selection(mistyped), mistyped)
        check("automatic unknown remains", SmartConvert.selection(mistyped, useSystemDictionary: false), mistyped)
        check("unverified selection route remains", converter.convertSelectionText(mistyped), mistyped)
        check("verified unknown single token", SmartConvert.selection(mistyped, allowUnrecognizedSingleWord: true), unknown)
        check("verified selection route", converter.convertSelectionText(mistyped, allowUnrecognizedSingleWord: true), unknown)
        check("unknown multiword remains", SmartConvert.selection("\(mistyped) купи", allowUnrecognizedSingleWord: true), "\(mistyped) купи")

        for protected in ["https://example.com", "foo_bar", "fooBar", "IPHONE", "iPhone", "iphone", "hello", "1234", "kb", "\(mistyped)7", mistyped.uppercased()] {
            check("protected single token \(protected)",
                  SmartConvert.selection(protected, allowUnrecognizedSingleWord: true), protected)
        }
        settings.neverConvertWords = [mistyped, "щзуткщгеук"]
        for protected in [mistyped, "щзуткщгеук"] {
            check("neverConvert overrides explicit selection \(protected)",
                  SmartConvert.selection(protected, allowUnrecognizedSingleWord: true), protected)
        }
        settings.neverConvertWords = []

        print("Selection conversion: \(failures == 0 ? "PASS" : "FAIL") (\(assertions) assertions, \(failures) failures)")
        if failures != 0 { exit(1) }
    }
}
