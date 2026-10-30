import AppKit
import ApplicationServices
import CoreGraphics

@MainActor final class StatusPopoverController: NSViewController {
    var menuProvider: (() -> NSMenu?)?
    var toggleEnabled: (() -> Void)?
    private var rootMenu: NSMenu?
    private var currentMenu: NSMenu?
    private var parents: [NSMenu] = []
    private var menuPath: [Int] = []
    private let popover = NSPopover()
    private let page = MultiPopoverView()
    private var rootBodyHeight: CGFloat = 0
    init(behavior: NSPopover.Behavior = .transient) {
        super.init(nibName: nil, bundle: nil)
        popover.behavior = behavior; popover.contentViewController = self
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .multiswitcherThemeChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    override func loadView() {
        view = page
        page.onSize = { [weak self] size in self?.popover.animates = false; self?.preferredContentSize = size; self?.popover.contentSize = size }
        page.onEscape = { [weak self] in self?.close() }
    }
    func toggle(near button: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil); return }
        parents.removeAll(); menuPath.removeAll(); rootMenu = menuProvider?(); currentMenu = rootMenu
        render()
        popover.animates = !DesignPalette.reducedMotion
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        view.window?.appearance = NSApp.appearance
    }
    @objc private func themeChanged() { popover.appearance = NSApp.appearance; page.appearance = NSApp.appearance; if popover.isShown { render() } }
    func close() { popover.performClose(nil) }
    var reviewWindow: NSWindow? { view.window }
    func refresh() {
        guard popover.isShown else { return }
        rootMenu = menuProvider?(); currentMenu = rootMenu; parents.removeAll()
        var validPath: [Int] = []
        for tag in menuPath {
            guard let parent = currentMenu, let next = parent.items.first(where: { $0.tag == tag })?.submenu else { break }
            parents.append(parent); currentMenu = next; validPath.append(tag)
        }
        menuPath = validPath
        render()
    }
    private func item(_ menuItem: NSMenuItem) -> MultiPopoverItem {
        if menuItem.isSeparatorItem { return .divider }
        var title = menuItem.title
        var detail = ""
        // State belongs below the action, never appended to a single truncating label.
        if menuItem.action == Selector(("toggleAutoConvert:")), let range = title.range(of: " — ") {
            detail = String(title[range.upperBound...]).replacingOccurrences(of: " — ", with: " · ")
            title = String(title[..<range.lowerBound])
        }
        let symbol: String
        if menuItem.submenu != nil { symbol = menuItem.title.contains("—") ? "app" : "chevron.right" }
        else if menuItem.action == Selector(("openSettings")) { symbol = "slider.horizontal.3" }
        else if menuItem.action == Selector(("quit")) { symbol = "power" }
        else if menuItem.action == Selector(("showHelp")) { symbol = "questionmark.circle" }
        else if menuItem.state == .on { symbol = "checkmark.circle.fill" }
        else { symbol = "circle" }
        return MultiPopoverItem(title: title, detail: detail, symbol: symbol, shortcut: menuItem.keyEquivalent,
            enabled: menuItem.isEnabled, selected: menuItem.state == .on, id: "menu:\(menuItem.tag):\(menuItem.representedObject as? String ?? NSStringFromSelector(menuItem.action ?? Selector(("submenu"))))",
            action: { [weak self] in
                guard let self else { return }
                if let submenu = menuItem.submenu {
                    if let currentMenu = self.currentMenu { self.parents.append(currentMenu) }
                    self.menuPath.append(menuItem.tag)
                    self.currentMenu = submenu; self.render(animated: true)
                } else if let action = menuItem.action {
                    self.popover.performClose(nil); NSApp.sendAction(action, to: menuItem.target, from: menuItem)
                }
            })
    }
    private func render(animated: Bool = false) {
        loadViewIfNeeded()
        popover.appearance = NSApp.appearance; page.appearance = NSApp.appearance
        let russian = L10n.languageCode == "ru"
        let enabled = SettingsManager.shared.autoSwitchEnabled
        let ready = AXIsProcessTrusted() && CGPreflightListenEventAccess()
        page.configure(name: "multiswitcher", status: russian ? (enabled && ready ? "работает" : "приостановлен") : (enabled && ready ? "running" : "paused"),
            icon: DesignIcon.application(dark: (NSApp.appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.darkAqua, .aqua]) == .darkAqua, size: 64),
            enabled: enabled, toggle: { [weak self] in self?.toggleEnabled?(); self?.refresh() })
        let rootItems = rootMenu?.items ?? []
        let divider = rootItems.firstIndex(where: \.isSeparatorItem) ?? rootItems.count
        let footer = rootItems.dropFirst(min(rootItems.count, divider + 1)).map(item)
        var body: [MultiPopoverItem]
        if parents.isEmpty { body = rootItems.prefix(divider).map(item) }
        else {
            body = [MultiPopoverItem(title: russian ? "назад" : "back", symbol: "chevron.left", action: { [weak self] in self?.goBack() })]
            body += (currentMenu?.items ?? []).map(item)
        }
        page.setItems(body, footer: footer, animated: animated, minimumBodyHeight: parents.isEmpty ? 0 : rootBodyHeight)
        if parents.isEmpty { rootBodyHeight = page.bodyHeight }
    }
    private func goBack() { currentMenu = parents.popLast(); if !menuPath.isEmpty { menuPath.removeLast() }; render(animated: true) }
    func openFirstSubmenuForReview() {
        guard let menuItem = currentMenu?.items.first(where: { $0.submenu != nil }) else { return }
        item(menuItem).action?()
    }
    func reviewRapidNavigation() {
        for _ in 0..<20 { openFirstSubmenuForReview(); goBack() }
    }
    var reviewGeometry: [String: Any] { page.reviewGeometry }
    var reviewRows: [MultiPopoverItem] { page.rowViews.map(\.item) }
    var reviewShown: Bool { popover.isShown }
}
