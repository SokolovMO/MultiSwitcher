# Selected-text conversion checks

From the repository root on macOS:

```sh
./scripts/check_selection_conversion.sh
```

Requires the Xcode command line tools and Python 3. All generated sources, dictionaries,
compiler caches and executables live in one temporary directory removed on exit.
The running app, user profile, clipboard and selected keyboard layout are untouched.

The harness compiles the current **real SmartConvert, LayoutDetector, DynamicKeyMapping,
KeyMapping, and MultiSwitcherCore sources**. It extracts the real TextConverter selection-routing
method, settings flag accessors and case guards into a small dependency boundary.
Native read-only Apple Russian/US sources feed real UCKeyTranslate keyboard maps.
The actual packaged RU/EN and thematic wordlists feed the real WordLexicon type.

Boundaries: settings and neverConvert lookup are in memory; Dict loads synchronously
and excludes AppleSpell/XPC/cache state. Both dictionary modes use packaged lists for
repeatability. LayoutSwitcher pins RU/US without enabling/selecting either source.
Unused keyboard-buffer types and RTL detection have minimal structural stubs.
The check covers automatic-word decisions, selection conversion and routing, including explicit verified-selection intent.
AX verification, Option event delivery and text insertion require separate app checks.

Regression coverage includes exact lowercase openrouter, spelling/case preservation,
mixed phrases, smart/full-flip precedence, explicit unknown-single-token conversion,
and protection of automatic input, unverified copies, multiword text, URLs, code,
acronyms, camelCase, digits and neverConvert rules.
