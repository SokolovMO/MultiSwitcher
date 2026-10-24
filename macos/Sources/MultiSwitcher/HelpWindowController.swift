import AppKit
import SwiftUI
import MultiSwitcherCore

@MainActor final class HelpWindowController: NSWindowController {
    private let openSettings: () -> Void
    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        let window = MultiBoundedWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = L10n.languageCode == "ru" ? "справка multiswitcher" : "multiswitcher help"
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false; window.collectionBehavior = [.managed, .fullScreenNone]
        let host = NSHostingView(rootView: HelpView(openSettings: openSettings, close: { [weak window] in window?.close() }))
        host.sizingOptions = []; window.contentView = host
        MultiWindowPolicy.configure(window, minimum: NSSize(width: 600, height: 420), maximum: NSSize(width: 800, height: 500))
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    func present() {
        if let window, let host = window.contentView as? NSHostingView<HelpView> {
            host.rootView = HelpView(openSettings: openSettings, close: { [weak window] in window?.close() })
        }
        window?.appearance = NSApp.appearance
        showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

private struct HelpView: View {
    let openSettings: () -> Void
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var ru: Bool { L10n.languageCode == "ru" }
    private func text(_ ru: String, _ en: String) -> String { self.ru ? ru : en }
    private func shortcut(_ key: String, right: Bool, twice: Bool) -> String {
        let names = ["option": "option", "command": "command", "control": "control", "shift": "shift", "capsLock": "caps lock"]
        let label = names[key] ?? key.replacingOccurrences(of: "+", with: " + ")
        return (right ? text("правая ", "right ") : "") + label + (twice ? text(" · двойное нажатие", " · double tap") : "")
    }
    var body: some View {
        let settings = SettingsManager.shared
        let convert = shortcut(settings.triggerKey, right: settings.triggerRightOnly, twice: settings.triggerDoubleTap)
        let layout = settings.switchHotkey.isEmpty
            ? text("переключайте раскладку через меню в трее или системной клавишей.", "choose a layout in the menu bar or use your system shortcut.")
            : shortcut(settings.switchHotkey, right: settings.switchRightOnly, twice: settings.switchDoubleTap)
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(nsImage: MultiBrandIcon.switcher).resizable().frame(width: 52, height: 52).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(text("справка multiswitcher", "multiswitcher help")).font(.system(size: 22, weight: .semibold))
                    Text(text("правильная раскладка без лишних действий", "the right layout with fewer steps")).font(.system(size: 12)).foregroundStyle(Color(nsColor: MultiDesign.secondary))
                }
            }
            ScrollView {
                HStack(alignment: .top, spacing: 12) {
                    MultiInstructionCard(number: "1", title: text("исправить текст", "correct text"),
                        detail: text("нажмите ", "press ") + convert + text(" для конверсии. автоматическое исправление включается в настройках.", " to convert. enable automatic correction in settings."),
                        symbol: "keyboard", reduceMotion: reduceMotion)
                    MultiInstructionCard(number: "2", title: text("управлять раскладкой", "choose a layout"),
                        detail: layout, symbol: "globe", reduceMotion: reduceMotion)
                    MultiInstructionCard(number: "3", title: text("настроить работу", "make it yours"),
                        detail: text("проверьте разрешения macos. исключения, правила и обучение доступны в настройках; пауза — в трее.", "check macos permissions. find exceptions, rules and learning in settings; pause from the menu bar."),
                        symbol: "slider.horizontal.3", reduceMotion: reduceMotion)
                }.frame(minHeight: 205)
                if !settings.caseHotkey.isEmpty {
                    Text(text("смена регистра: ", "change case: ") + shortcut(settings.caseHotkey, right: settings.caseRightOnly, twice: settings.caseDoubleTap))
                        .font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                }
            }
            Text(text("⌘, открывает настройки, когда окно приложения активно. закрытие окна оставляет multiswitcher работать в фоне.", "⌘, opens settings while the app window is active. closing the window keeps multiswitcher running in the background."))
                .font(.system(size: 11)).foregroundStyle(Color(nsColor: MultiDesign.secondary))
            HStack {
                Button(text("настройки", "settings"), action: openSettings).buttonStyle(MultiActionButtonStyle()).keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button(text("закрыть", "close"), action: close).buttonStyle(MultiActionButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(24).foregroundStyle(Color(nsColor: MultiDesign.ink)).background(Color(nsColor: MultiDesign.canvas))
            .onExitCommand(perform: close)
    }
}
