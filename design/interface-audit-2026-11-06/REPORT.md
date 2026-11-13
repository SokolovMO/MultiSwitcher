# Аудит интерфейса MultiSwitcher и пакет исправлений 70

Проверено 6 ноября 2026. Стек: AppKit с отдельными SwiftUI-компонентами; существующая графитовая палитра и системные SF Symbols. Основной язык прогона — русский; окно Sparkle дополнительно проверено на английском. Основной установленный профиль не использовался как тестовый.

Исходные соглашения прочитаны в DESIGN_PLAN.md, SystemTypography.swift, MultiInterfaceMetrics.swift и существующих design/*/REPORT.md. Отдельных PRODUCT.md/DESIGN.md в проекте нет. Загрузчик Impeccable не смог запуститься из-за отсутствия движка/доступа к кэшу; native-аудит выполнен существующими AppKit QA-путями и по первичным исходникам.

## Охват

Проверены основные, расширенные, автокоррекция/исключения, правила, обучение, оформление, о приложении; форма правила; справка; три состояния помощника разрешений; native NSMenu; окно готовности Sparkle. Использованы обычный, плотный и пустой синтетические профили, длинные значения и поисковые запросы. Настройки проверяются в поддерживаемых desktop-размерах: минимум/обычный/максимум и односторонние изменения; ширина desktop-окна не оценивается по мобильному правилу 320 px.

| Область | Доказательства | Результат |
|---|---|---|
| Доступность | Явные подписи полей и popup, геометрия редактора, Enter/Escape/стрелки/удаление, фокус в InteractionChecks. | Исправлено; полноценный VoiceOver не сертифицирован. |
| Компоновка | 252 состояния исходной 69, 252 после структурных правок 70, 84 состояния финального 70; все 7 разделов, обе темы и обе панели. | Геометрия, навигация, восстановление и направляющие проходят. |
| Тексты | О приложении, версия/сборка, журнал, appcast, RU/EN окно Sparkle. | Убраны проверенные устаревшие/английские сообщения в русском сценарии. |
| Типографика | Редактирование поиска, длинные слова/замены, редактор правил и реальная кнопка Sparkle. | Текст поиска не пересекает иконки; кнопка полностью видна. |
| Цвет | Светлая/тёмная темы, вторичный текст, поля и выделенные строки. | Контраст динамических токенов >=4.5:1 проверен тестом; disabled-контролы исключаются. |
| Полировка | Состояния native кнопок, disabled popup, сворачивание панели, раскрытие справок, Reduce Motion. | Исправлены найденные несогласованности; системные контролы сохранены. |

## Найденные причины и исправления

Одна строка — одна группа причин. Все перечисленные изменения входят в единый пакет 70; промежуточные build-70 каталоги не являются опубликованными выпусками.

| ID / важность | Где | До | Исправление |
|---|---|---|---|
| UI-01 / HIGH | [DesignSystem.swift:291](/Users/sokolovmo/Documents/MultiSwitcher/macos/Sources/MultiSwitcher/DesignSystem.swift:291) | Поиск: ввод налезает на лупу. Реальный field editor начинался в x=2,y=0, а лупа занимала x=8..24. Воспроизведено 8 раз. | Штатная ячейка NSSearchField, единая высота и фокус. |
| UI-02 / HIGH | [DesignSystem.swift:228](/Users/sokolovmo/Documents/MultiSwitcher/macos/Sources/MultiSwitcher/DesignSystem.swift:228) | Обрезание кнопки Sparkle. На присланном снимке временного предпросмотра оставалось Install and. Ранняя отрисовка заменяла native cell; последующие попытки компенсировали это отступами. | Сохранена native NSButtonCell; графит задаётся bezelColor, метрики/действие/Enter принадлежат AppKit. |
| UI-03 / MEDIUM | [Localization.swift:8](/Users/sokolovmo/Documents/MultiSwitcher/macos/Sources/MultiSwitcher/Localization.swift:8) | Окно обновления не следует языку приложения. В .app отсутствовали CFBundleLocalizations/AllowMixedLocalizations; отдельный тест выбирал en вместо ru. | Метаданные локализаций и process-local AppleLanguages до инициализации AppKit; RU/EN проверены на релизном бинарнике. |
| UI-04 / MEDIUM | [UserRuleEditor.swift:633](/Users/sokolovmo/Documents/MultiSwitcher/macos/Sources/MultiSwitcher/UserRuleEditor.swift:633) | У полей и списков нет понятного имени для доступности. В редакторе четыре поля имели пустую accessibilityLabel; пять popup основных настроек также без подписи. Полное прохождение VoiceOver не выполнялось; это проверка явных подписей AppKit. | Явные подписи поиска и полей; общий settingsFormRow связывает название с контролом. |
| UI-05 / HIGH | [DesignSystem.swift:21](/Users/sokolovmo/Documents/MultiSwitcher/macos/Sources/MultiSwitcher/DesignSystem.swift:21) | Недостаточный контраст вторичного текста в светлой теме. Измеренная secondaryLabelColor с alpha 0.498 на поверхности 0.995 даёт 3.94:1. | DesignPalette.secondary для подсказок и динамических строк: значения 0.38/0.66 дают расчётный минимум 4.83:1/4.94:1 на стандартном выделении. Регрессия измеряет цвета AppKit в обеих темах. |
| UI-06 / HIGH | [SettingsWindowController.swift:1006](/Users/sokolovmo/Documents/MultiSwitcher/macos/Sources/MultiSwitcher/SettingsWindowController.swift:1006) | Стиль таблиц зависит от порядка открытия страниц. NSTabView монтирует только текущую страницу; одноразовый обход не стилизовал остальные, на матрице выделение отличалось. | Применение DesignStyler при каждом didSelect; отдельная регрессия выделения Learning. |
| UI-07 / MEDIUM | [LearningListEditor.swift:175](/Users/sokolovmo/Documents/MultiSwitcher/macos/Sources/MultiSwitcher/LearningListEditor.swift:175) | Нельзя прочитать длинное слово в обучении/исключении. Обрезание хвостом, tooltip отсутствовал; строка не редактируется. | Полное значение доступно в подсказке; для приложения также показывается bundle ID. |
| UI-08 / MEDIUM | [UserRuleEditor.swift:30](/Users/sokolovmo/Documents/MultiSwitcher/macos/Sources/MultiSwitcher/UserRuleEditor.swift:30) | Ручная ширина колонок правил сбрасывается. RuleScrollView.tile каждый раз заново назначал фиксированные пропорции. | Распределение только при изменении viewport; ручные пропорции и горизонтальная прокрутка сохраняются. Регрессия в InteractionChecks. |
| UI-09 / MEDIUM | [SettingsWindowController.swift:1829](/Users/sokolovmo/Documents/MultiSwitcher/macos/Sources/MultiSwitcher/SettingsWindowController.swift:1829) | Обновление спрятано, номер сборки не виден. В О приложении показывалась только 0.4.0, а кнопка обновления была внутри технического disclosure. | Сборка в версии, обновление и автопроверка видимы в основной карточке. |
| UI-10 / MEDIUM | [Localization.swift:8](/Users/sokolovmo/Documents/MultiSwitcher/macos/Sources/MultiSwitcher/Localization.swift:8) | Устаревшие и английские сообщения. О приложении ошибочно указывало GitHub и несуществующий переключатель отчётов; лог и feed имели только английские тексты. | Актуальный адрес сервера, русская инструкция создания журнала и локализованные RU/EN описания appcast. |
| UI-11 / LOW | [DesignSystem.swift:134](/Users/sokolovmo/Documents/MultiSwitcher/macos/Sources/MultiSwitcher/DesignSystem.swift:134) | Отключённый custom popup выглядит включённым. Custom draw игнорировал isEnabled. | Отключённый текст и стрелка используют вторичный цвет. |

## Проверки

- `swift run --package-path macos MultiSwitcherCoreTests`: 313 проверок, PASS ([лог](core-final.log)).
- `bash scripts/check_selection_conversion.sh`: 111 утверждений, PASS ([лог](selection-final.log)).
- `bash scripts/check_interactions.sh`: PASS; дополнительно проверяются координаты текста поиска, сохранение ручной ширины колонок, применение оформления при первом открытии Learning и контраст реальных динамических NSColor ([лог](interaction-publish.log)).
- `python3 -m unittest discover -s tests/release -v`: 6 тестов, включая подписи/подмену архивов и RU/EN описания appcast, PASS.
- Исходная полная матрица 69: 252/252 системных снимка ([геометрия](matrix/geometry-results.json), [измерения](matrix/layout-measurements.json)).
- Матрица после структурных исправлений 70: 252/252 ([геометрия](matrix-after/geometry-results.json)).
- Заключительный финальный бинарник с последней палитрой: 84/84 состояния и ещё обычные страницы/низ прокрутки/диалоги ([геометрия](final-matrix/geometry-results.json), [окно](final-matrix/window-results.json), [native menu](final-matrix/native-results.json)). Повторённая сокращённая матрица отличается от предшествующей полной только последним шагом палитры; компоновка/обработчики те же.
- Во всех 8 замерах до исправления текст пересекал лупу. Во всех 8 замерах после — пересечений нет; field editor совпадает со штатным text rect ([до](probe/search-geometry.json), [после](probe-after/search-geometry.json)).
- Поля правила получили явные названия ([до](probe/inventory.json), [после](probe-after/inventory.json)).
- Настоящий SPUStandardUserDriver финального release .app: русский — «Установить и перезапустить», английский — «Install and Relaunch»; native cell, Return и routing действия сохранены. Этот изолированный QA-путь не создаёт updater/download/install ([RU](updates-final/ru/update-ui-results.json), [EN](updates-final/en/update-ui-results.json)).
- ZIP, распакованный .app, смонтированный DMG, selftest, глубокая/строгая подпись, прежнее signing requirement и Ed25519 подписи архива/ленты проверены сборщиком. Финальный архив исходников сравнен с проверенным текущим деревом.

Механические проверки охватывают всю записанную матрицу. Вручную просмотрены контактные листы всех семи страниц в минимум/обычный/максимум состояниях и отдельные полноразмерные проблемные/исправленные состояния. Не утверждается, что каждый из сотен снимков независимо изучен попиксельно.

## Снимки для проверки

- [Поиск до исправления](probe/light-page-3-search-apple.png) → [поиск после](probe-after/light-page-3-search-apple.png).
- [Правила после, тёмная тема](probe-after/dark-page-3-search-apple.png).
- [Обучение после](final-matrix/dark-4.png).
- [О приложении: сборка и видимое обновление](final-matrix/light-6.png).
- [Форма правила](final-matrix/light-rule-dialog.png).
- [Sparkle, русский / светлая](updates-final/ru/update-light.png), [русский / тёмная](updates-final/ru/update-dark.png).
- [Справка](probe-after/help.png), [помощник разрешений](probe-after/permission-2.png).

## Границы проверки

Не сертифицированы полноценное прохождение VoiceOver, физический ввод во всех сторонних приложениях, все поддерживаемые версии macOS, смена физических мониторов/display scaling и полный перевод/проход всех 16 локалей. Программные AppKit события и измерения не выдаются за эти проверки. Проверка Chrome/HTML/WCAG mobile reflow не подменяет нативные требования macOS. Настоящие разрешения не выдавались и не сбрасывались во время аудита.

## Вердикт

Approve для описанного русского desktop-сценария и проверенных RU/EN окон Sparkle: известные HIGH-дефекты этого прогона исправлены. Это не заявление об отсутствии любых будущих UI-багов или о полном аудите VoiceOver/всех локалей/всех macOS.


## Публикация и установленная копия

- Опубликована и запущена **0.4.0 (70)** на https://sokolovmo.ru/multiswitcher/ .
- ZIP SHA256: `a407998a704a0d0cc13e3483af2b02c6706b39ef148e883330ca1c6639832baf`.
- Публичные manifest и подписанная лента побайтово совпали с проверенным кандидатом.
- Установка выполнена прочитанным и побайтово проверенным install.sh с корректным завершением прежней сборки 68 и подтверждением запуска 70. Это **не** выдаётся за новый реальный Sparkle-прогон 68→70; готовое окно Sparkle и его действие проверялись отдельно в изолированном release QA-режиме. Предыдущий реальный прогон 67→68 описан в RELEASE-VALIDATION-2026-11-06.md.
- Установленный executable совпал с финальным архивом. Профиль сохранился побайтово, включая правила, обучение, настройки и импортированные правила ([проверка](installation-result.json)).
- После запуска: accessibility=true, inputMonitoring=true, Event tap created/enabled, Monitoring started successfully.
- Старое приложение сохранено в `/Applications/.multiswitcher-previous-53340.app`.
- Все 8 ранее проверенных маршрутов других сайтов сохранили статус/тело; счётчик доступен. Конфигурация nginx не менялась, nginx -t прошёл, перезапуска/reload не было. previous раздачи сохраняет build 69.
- Плотный (155 правил / 85 записей обучения) и полностью пустой профили: по 35 дополнительных состояний, по 8 проверок геометрии поиска без пересечений ([плотный](probe-dense/search-geometry.json), [пустой](probe-empty/search-geometry.json)).
- Аудит не изменил настоящий профиль; все не относящиеся к исправлениям исходники побайтово сохранились ([проверка](preservation-after-audit.json)).
