import AppKit
import Carbon
import MultiSwitcherCore
import QuartzCore
import UniformTypeIdentifiers

/// The menu-bar app has no main menu while it runs as an accessory. Handle the
/// standard close shortcut at the window level so it also works from text fields.
@MainActor
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let extraModifiers = modifiers.intersection([.shift, .option, .control])
        if event.type == .keyDown,
           modifiers.contains(.command),
           extraModifiers.isEmpty,
           event.keyCode == 13 {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class SettingsSidebarDivider: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height)).fill()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        onDrag?(superview.convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnded?()
    }
}

/// Нативное окно настроек с полноценной боковой навигацией.
@MainActor
final class SettingsWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTabViewDelegate, NSWindowDelegate {
    private struct NavigationItem {
        let title: String
        let symbol: String
    }

    private var window: NSWindow?
    private weak var rootView: NSView?
    private weak var sidebarView: NSView?
    private weak var sidebarSeparator: NSView?
    private weak var navigationScrollView: NSScrollView?
    private weak var paneScrollView: NSScrollView?
    private var pageAccessory: NSTitlebarAccessoryViewController?
    private var pageExpandButton: NSButton?
    private var compactModeButton: NSButton?
    private var expandedPage = false
    private var selectedPageIndex = 0
    private var minimumDocumentHeight: CGFloat = 0
    private var sidebarWidth: CGFloat = 206
    private let sidebarDividerWidth: CGFloat = 6
    private var navigationTable: NSTableView?
    private var settingsTabView: NSTabView?
    private var autoSwitchCheckbox: NSButton?
    private var launchAtLoginCheckbox: NSButton?
    private var debugLogCheckbox: NSButton?
    private var caretFlagCheckbox: NSButton?
    private var autoConvertCheckbox: NSButton?      // #4: синк тумблера меню → окно настроек
    private var remoteDesktopCheckbox: NSButton?    // #5: то же (опционален — за фичефлагом)
    private var smartConversionCheckbox: NSButton?
    private var convertByTextCheckbox: NSButton?
    private var layout1Popup: NSPopUpButton?
    private var layout2Popup: NSPopUpButton?
    private var languagePopup: NSPopUpButton?
    private var switchHotkeyPopup: NSPopUpButton?   // issue #20/#3: пере-populate при смене триггера
    private var caseHotkeyPopup: NSPopUpButton?     // issue #29
    private var exceptionEditors: [ExceptionListEditor] = []
    private var learningListEditor: LearningListEditor?
    private var ruleEditor: UserRuleEditor?
    private weak var profileRecoveryNoteLabel: NSTextField?
    private weak var restoreProfileButton: NSButton?
    private var pageTransitionGeneration = 0

    /// Callback для обновления меню
    var onAutoSwitchChanged: ((Bool) -> Void)?
    var onPerAppLayoutChanged: ((Bool) -> Void)?
    var onLanguageChanged: (() -> Void)?
    var onTriggerChanged: (() -> Void)?
    var onAutoConvertChanged: ((Bool) -> Void)?
    var onRemoteDesktopChanged: ((Bool) -> Void)?
    var onCaretFlagChanged: ((Bool) -> Void)?
    var onHideIconChanged: ((Bool) -> Void)?
    var onWindowVisibilityChanged: ((Bool) -> Void)?

    func showWindow() {
        if let window {
            exceptionEditors.forEach { $0.reloadFromStore() }
            learningListEditor?.reloadFromStore()
            ruleEditor?.reloadFromStore()
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            onWindowVisibilityChanged?(true)
            return
        }

        NSApp.setActivationPolicy(.regular)
        sidebarWidth = CGFloat(SettingsManager.shared.settingsSidebarWidth)
        let win = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.settingsTitle
        win.appearance = nil // Inherit the current macOS light/dark appearance.
        win.collectionBehavior = [.managed, .fullScreenPrimary]
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        let root = NSView(frame: win.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        root.autoresizesSubviews = true
        root.wantsLayer = true
        let separator = SettingsSidebarDivider(frame: NSRect(x: sidebarWidth, y: 0,
                                                               width: sidebarDividerWidth,
                                                               height: root.bounds.height))
        // Keep the divider beside the sidebar as the window grows. A flexible
        // left margin made it drift toward the center on wide displays.
        separator.autoresizingMask = [.height, .maxXMargin]
        separator.onDrag = { [weak self] x in self?.setSidebarWidth(x) }
        separator.setAccessibilityLabel(L10n.settingsResizeSidebar)
        separator.toolTip = L10n.settingsResizeSidebar
        separator.onDragEnded = { [weak self] in
            guard let self else { return }
            SettingsManager.shared.settingsSidebarWidth = Int(self.sidebarWidth.rounded())
        }
        root.addSubview(separator)

        let sidebar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: sidebarWidth,
                                                        height: root.bounds.height))
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .followsWindowActiveState
        sidebar.autoresizingMask = [.height, .maxXMargin]
        root.addSubview(sidebar, positioned: .below, relativeTo: separator)
        rootView = root
        sidebarView = sidebar
        sidebarSeparator = separator

        let brandMark = NSTextField(labelWithString: "AЯ")
        brandMark.frame = NSRect(x: 18, y: root.bounds.height - 40, width: 34, height: 24)
        brandMark.font = SystemTypography.font(.headline, weight: .bold)
        // Keep the AЯ signature monochrome in both appearances; system accent remains
        // reserved for interactive selection and status feedback.
        brandMark.textColor = .labelColor
        brandMark.alignment = .center
        brandMark.autoresizingMask = [.minYMargin]
        sidebar.addSubview(brandMark)
        let brand = NSTextField(labelWithString: "MultiSwitcher")
        brand.frame = NSRect(x: 58, y: root.bounds.height - 40, width: 132, height: 22)
        brand.font = SystemTypography.font(.headline, weight: .semibold)
        brand.autoresizingMask = [.minYMargin]
        sidebar.addSubview(brand)

        let navigationScroll = NSScrollView(frame: NSRect(x: 8, y: 12, width: sidebarWidth - 16,
                                                           height: root.bounds.height - 58))
        navigationScroll.borderType = .noBorder
        navigationScroll.hasVerticalScroller = false
        navigationScroll.drawsBackground = false
        navigationScroll.autoresizingMask = [.width, .height]
        let navigation = NSTableView(frame: navigationScroll.bounds)
        navigation.style = .sourceList
        navigation.headerView = nil
        navigation.rowHeight = 42
        navigation.intercellSpacing = NSSize(width: 0, height: 4)
        navigation.usesAlternatingRowBackgroundColors = false
        navigation.backgroundColor = .clear
        navigation.dataSource = self
        navigation.delegate = self
        let navigationColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("settings.navigation"))
        navigationColumn.width = navigationScroll.bounds.width
        navigationColumn.resizingMask = .autoresizingMask
        navigation.addTableColumn(navigationColumn)
        navigationScroll.documentView = navigation
        sidebar.addSubview(navigationScroll)
        navigationTable = navigation
        navigationScrollView = navigationScroll

        let paneOriginX = sidebarWidth + sidebarDividerWidth
        let tabView = NSTabView(frame: NSRect(x: paneOriginX, y: 0,
                                               width: root.bounds.width - paneOriginX,
                                               height: root.bounds.height))
        tabView.tabViewType = .noTabsNoBorder
        tabView.delegate = self

        tabView.addTabViewItem(createGeneralTab())
        tabView.addTabViewItem(createAdvancedTab())     // «Расширенные» — сразу после «Основных»
        tabView.addTabViewItem(createExceptionsTab())
        tabView.addTabViewItem(createRulesTab())
        tabView.addTabViewItem(createLearningTab())
        tabView.addTabViewItem(createAboutTab())
        applyCompactMode(SettingsManager.shared.compactSettings)

        let tallest = tabView.tabViewItems.compactMap { $0.view?.frame.height }.max() ?? 700
        minimumDocumentHeight = max(root.bounds.height, tallest)
        tabView.frame.size.height = minimumDocumentHeight
        tabView.autoresizingMask = [.width, .height]
        let paneScroll = NSScrollView(frame: NSRect(x: paneOriginX, y: 0,
                                                    width: root.bounds.width - paneOriginX,
                                                    height: root.bounds.height))
        paneScroll.borderType = .noBorder
        paneScroll.hasVerticalScroller = true
        paneScroll.hasHorizontalScroller = false
        paneScroll.autohidesScrollers = true
        paneScroll.drawsBackground = false
        paneScroll.autoresizingMask = [.width, .height]
        paneScroll.documentView = tabView
        root.addSubview(paneScroll)
        paneScrollView = paneScroll
        win.contentView = root
        settingsTabView = tabView
        installPageAccessory(on: win)
        applyCompactMode(SettingsManager.shared.compactSettings)
        navigation.reloadData()
        navigation.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tabView.selectTabViewItem(at: 0)

        // Keep the comfortable initial size, while allowing the content itself to
        // grow with the window instead of leaving the right half empty.
        let visibleFrame = (win.screen ?? NSScreen.main)?.visibleFrame
        let availableHeight = max(360, (visibleFrame?.height ?? 720) - 56)
        let minimumHeight = min(480, availableHeight)
        let desiredHeight = min(max(680, tallest + 16), availableHeight)
        win.setContentSize(NSSize(width: 800, height: max(minimumHeight, desiredHeight)))
        win.minSize = NSSize(width: 800, height: minimumHeight)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = win
        setSidebarWidth(sidebarWidth)
        onWindowVisibilityChanged?(true)
        updatePagePresentation()
    }

    private func installPageAccessory(on window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 72, height: 28))
        let expandImage = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right",
                                  accessibilityDescription: "Развернуть страницу")
            ?? NSImage(size: NSSize(width: 16, height: 16))
        let button = NSButton(image: expandImage,
                              target: self, action: #selector(toggleExpandedPage))
        button.frame = NSRect(x: 38, y: 2, width: 28, height: 24)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.toolTip = L10n.settingsExpandPage
        button.setAccessibilityLabel(L10n.settingsExpandPage)
        container.addSubview(button)

        let compactButton = NSButton(image: NSImage(systemSymbolName: "line.3.horizontal.decrease.circle",
                                                      accessibilityDescription: L10n.settingsCompactMode)
                                    ?? NSImage(size: NSSize(width: 16, height: 16)),
                                    target: self, action: #selector(toggleCompactMode))
        compactButton.frame = NSRect(x: 2, y: 2, width: 28, height: 24)
        compactButton.bezelStyle = .accessoryBarAction
        compactButton.isBordered = false
        compactButton.toolTip = L10n.settingsCompactMode
        compactButton.setAccessibilityLabel(L10n.settingsCompactMode)
        container.addSubview(compactButton)

        accessory.view = container
        pageAccessory = accessory
        pageExpandButton = button
        compactModeButton = compactButton
        window.addTitlebarAccessoryViewController(accessory)
    }

    @objc private func toggleExpandedPage() {
        guard canExpandSelectedPage else { return }
        expandedPage.toggle()
        updatePagePresentation(animated: true)
    }

    private var canExpandSelectedPage: Bool {
        selectedPageIndex == 2 || selectedPageIndex == 3 || selectedPageIndex == 4
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func updatePagePresentation(animated: Bool = false) {
        let canExpand = canExpandSelectedPage
        pageExpandButton?.isHidden = !canExpand
        let isExpanded = expandedPage && canExpand
        let symbol = isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        pageExpandButton?.image = NSImage(systemSymbolName: symbol,
                                          accessibilityDescription: isExpanded ? L10n.settingsRestoreSidebar : L10n.settingsExpandPage)
        pageExpandButton?.toolTip = isExpanded ? L10n.settingsRestoreSidebar : L10n.settingsExpandPage
        pageExpandButton?.setAccessibilityLabel(pageExpandButton?.toolTip ?? "Развернуть страницу")

        guard let rootView, let paneScrollView else { return }
        let originX = isExpanded ? CGFloat.zero : sidebarWidth + sidebarDividerWidth
        let targetFrame = NSRect(x: originX, y: 0,
                                 width: max(1, rootView.bounds.width - originX),
                                 height: rootView.bounds.height)
        let shouldAnimate = animated && !reduceMotion && window?.isVisible == true

        if !shouldAnimate {
            paneScrollView.frame = targetFrame
            sidebarView?.isHidden = isExpanded
            sidebarSeparator?.isHidden = isExpanded
            sidebarView?.alphaValue = 1
            sidebarSeparator?.alphaValue = 1
            updateDocumentSize()
            return
        }

        pageTransitionGeneration += 1
        let generation = pageTransitionGeneration
        if !isExpanded {
            sidebarView?.isHidden = false
            sidebarSeparator?.isHidden = false
            sidebarView?.alphaValue = 0
            sidebarSeparator?.alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            paneScrollView.animator().frame = targetFrame
            if isExpanded {
                sidebarView?.animator().alphaValue = 0
                sidebarSeparator?.animator().alphaValue = 0
            } else {
                sidebarView?.animator().alphaValue = 1
                sidebarSeparator?.animator().alphaValue = 1
            }
            context.completionHandler = { [weak self, weak paneScrollView] in
                guard let self, let paneScrollView,
                      self.pageTransitionGeneration == generation else { return }
                if isExpanded {
                    self.sidebarView?.isHidden = true
                    self.sidebarSeparator?.isHidden = true
                }
                paneScrollView.frame = targetFrame
                self.updateDocumentSize()
            }
        }
    }

    private func updateDocumentSize() {
        guard let paneScrollView, let documentView = paneScrollView.documentView else { return }
        documentView.setFrameSize(NSSize(width: paneScrollView.contentSize.width,
                                         height: max(minimumDocumentHeight, paneScrollView.contentSize.height)))
    }

    private func setSidebarWidth(_ requested: CGFloat) {
        guard let rootView, let sidebarView, let sidebarSeparator else { return }
        let maximum = max(180, min(320, rootView.bounds.width - sidebarDividerWidth - 480))
        sidebarWidth = min(max(180, requested), maximum)
        sidebarView.frame.size.width = sidebarWidth
        sidebarSeparator.frame.origin.x = sidebarWidth
        navigationScrollView?.frame.size.width = max(120, sidebarWidth - 16)
        if let navigationTable {
            navigationTable.tableColumns.first?.width = navigationScrollView?.contentSize.width ?? sidebarWidth - 16
        }
        guard !expandedPage else { return }
        let originX = sidebarWidth + sidebarDividerWidth
        paneScrollView?.frame = NSRect(x: originX, y: 0,
                                       width: max(1, rootView.bounds.width - originX),
                                       height: rootView.bounds.height)
        updateDocumentSize()
    }

    private func applyCompactMode(_ compact: Bool) {
        navigationTable?.rowHeight = compact ? 36 : 42
        navigationTable?.intercellSpacing = NSSize(width: 0, height: compact ? 2 : 4)
        navigationTable?.reloadData()
        exceptionEditors.forEach { $0.setCompactMode(compact) }
        learningListEditor?.setCompactMode(compact)
        ruleEditor?.setCompactMode(compact)
        let title = compact ? L10n.settingsComfortableMode : L10n.settingsCompactMode
        let symbol = compact ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
        compactModeButton?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        compactModeButton?.toolTip = title
        compactModeButton?.setAccessibilityLabel(title)
    }

    @objc private func toggleCompactMode() {
        let compact = !SettingsManager.shared.compactSettings
        SettingsManager.shared.compactSettings = compact
        applyCompactMode(compact)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        pageTransitionGeneration += 1
        paneScrollView?.alphaValue = 1
        expandedPage = false
        updatePagePresentation()
        onWindowVisibilityChanged?(false)
    }

    func windowDidResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        setSidebarWidth(sidebarWidth)
        updateDocumentSize()
    }

    private var navigationItems: [NavigationItem] {
        [
            NavigationItem(title: L10n.settingsTabGeneral, symbol: "slider.horizontal.3"),
            NavigationItem(title: L10n.settingsTabAdvanced, symbol: "gearshape.2"),
            NavigationItem(title: L10n.settingsTabExceptions, symbol: "arrow.left.arrow.right"),
            NavigationItem(title: L10n.settingsTabRules, symbol: "list.bullet.rectangle"),
            NavigationItem(title: L10n.settingsTabLearning, symbol: "brain.head.profile"),
            NavigationItem(title: L10n.settingsTabAbout, symbol: "info.circle"),
        ]
    }

    func numberOfRows(in tableView: NSTableView) -> Int { navigationItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard navigationItems.indices.contains(row) else { return nil }
        let item = navigationItems[row]
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: item.title)
        label.font = SystemTypography.font(.body, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let navigationTable,
              (notification.object as? NSTableView) === navigationTable,
              navigationTable.selectedRow >= 0 else { return }
        transitionToPage(navigationTable.selectedRow, animated: true)
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let tabViewItem,
              let index = tabView.tabViewItems.firstIndex(of: tabViewItem),
              navigationTable?.selectedRow != index else { return }
        selectedPageIndex = index
        if !canExpandSelectedPage { expandedPage = false }
        navigationTable?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        updatePagePresentation(animated: true)
    }

    private func transitionToPage(_ index: Int, animated: Bool) {
        guard navigationItems.indices.contains(index) else { return }
        let willChange = selectedPageIndex != index
        selectedPageIndex = index
        if !canExpandSelectedPage { expandedPage = false }
        navigationTable?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        guard let settingsTabView, willChange, animated, !reduceMotion,
              let paneScrollView, window?.isVisible == true else {
            settingsTabView?.selectTabViewItem(at: index)
            updatePagePresentation(animated: willChange)
            return
        }

        pageTransitionGeneration += 1
        let generation = pageTransitionGeneration
        paneScrollView.alphaValue = 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            paneScrollView.animator().alphaValue = 0.72
            context.completionHandler = { [weak self, weak settingsTabView, weak paneScrollView] in
                guard let self, let settingsTabView, let paneScrollView,
                      self.pageTransitionGeneration == generation else { return }
                settingsTabView.selectTabViewItem(at: index)
                self.updatePagePresentation(animated: true)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    paneScrollView.animator().alphaValue = 1
                }
            }
        }
    }

    /// Обновить состояние чекбокса автопереключения извне
    func updateAutoSwitchState(_ enabled: Bool) {
        autoSwitchCheckbox?.state = enabled ? .on : .off
    }

    /// Обновить чекбокс «флаг у курсора» извне (когда переключили из меню)
    func updateCaretFlagState(_ enabled: Bool) {
        caretFlagCheckbox?.state = enabled ? .on : .off
    }

    /// #4/#5: синхронизировать чекбоксы с переключением из меню-бара.
    func updateAutoConvertState(_ enabled: Bool) {
        autoConvertCheckbox?.state = enabled ? .on : .off
    }
    func updateRemoteDesktopState(_ enabled: Bool) {
        remoteDesktopCheckbox?.state = enabled ? .on : .off
    }

    // MARK: - General Tab

    /// Прижимает контент вкладки к ВЕРХУ. NSTabView растягивает вид вкладки на всю высоту окна,
    /// а под-вью с абсолютными координатами (y от низа) иначе провисают к низу/центру короткой
    /// вкладки. Оборачиваем фиксированный контент в растягивающийся контейнер и пиним контент к
    /// верхнему краю (гибкий нижний отступ — .minYMargin).
    private func topAligned(_ content: NSView, fillsHeight: Bool = false) -> NSView {
        let paneWidth: CGFloat = 580
        content.frame.origin.x = max(0, (paneWidth - content.frame.width) / 2)
        let outer = NSView(frame: NSRect(x: 0, y: 0, width: paneWidth, height: content.frame.height))
        outer.autoresizingMask = [.width, .height]
        outer.autoresizesSubviews = true
        // Page view follows the scroll view's document width. Stretch controls
        // already aligned to the content edge; keep labels and compact buttons fixed.
        content.autoresizingMask = fillsHeight ? [.width, .height] : [.width, .minYMargin]
        for child in content.subviews {
            var mask: NSView.AutoresizingMask = child.frame.maxX >= content.frame.width - 46 ? [.width] : []
            if fillsHeight {
                if child.frame.height < 40 && child.frame.minY < 30 {
                    mask.insert(.maxYMargin)
                } else if child.frame.minY < content.frame.height * 0.45 {
                    mask.insert(.height)
                } else {
                    mask.insert(.minYMargin)
                }
            }
            child.autoresizingMask = mask
        }
        outer.addSubview(content)
        return outer
    }

    // MARK: - Подгонка вёрстки под длину текста

    /// Вкладки свёрстаны абсолютными фреймами, и длинные переводы обрезались: на 16 языках
    /// нашлось 113 мест (проверка: site/tools/make_shots.sh --audit). После сборки вкладки
    /// этот проход подгоняет её под фактический текст:
    ///  • строки «подпись + список» — общая колонка подписей по самой длинной; если список
    ///    при этом не влезает, подпись переносится на несколько строк;
    ///  • многострочные пояснения и длинные чекбоксы получают нужную высоту (чекбоксы переносятся);
    ///  • кнопки расширяются под текст, а ряд кнопок, который не влезает, встаёт в столбик;
    ///  • всё, что ниже выросшего элемента, сдвигается вниз, высота вкладки — по содержимому.
    private func fitToText(_ view: NSView) {
        let left: CGFloat = 20, right: CGFloat = 440, gap: CGFloat = 8
        let items = view.subviews.filter { !$0.isHidden }
        guard !items.isEmpty else { return }
        let topMargin = view.frame.height - (items.map { $0.frame.maxY }.max() ?? view.frame.height)

        // Строки — элементы, чьи рамки заметно пересекаются по вертикали (подпись и список рядом).
        func sameRow(_ a: NSRect, _ b: NSRect) -> Bool {
            min(a.maxY, b.maxY) - max(a.minY, b.minY) > 0.3 * min(a.height, b.height)
        }
        var rows: [[NSView]] = []
        for v in items.sorted(by: { $0.frame.maxY > $1.frame.maxY }) {
            if let i = rows.firstIndex(where: { $0.contains { sameRow($0.frame, v.frame) } }) {
                rows[i].append(v)
            } else {
                rows.append([v])
            }
        }
        rows.sort { ($0.map { $0.frame.maxY }.max() ?? 0) > ($1.map { $0.frame.maxY }.max() ?? 0) }

        var grow: [ObjectIdentifier: CGFloat] = [:]       // на сколько выросла высота (верх на месте)
        func setHeight(_ v: NSView, _ h: CGFloat) {
            let top = v.frame.maxY
            grow[ObjectIdentifier(v), default: 0] += h - v.frame.height
            v.frame = NSRect(x: v.frame.minX, y: top - h, width: v.frame.width, height: h)
        }
        func fitHeight(_ c: NSControl, width: CGFloat) -> CGFloat {
            ceil(c.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000)).height ?? c.frame.height)
        }
        func makeWrapping(_ c: NSControl) {
            c.cell?.wraps = true
            c.cell?.lineBreakMode = .byWordWrapping
            (c as? NSTextField)?.maximumNumberOfLines = 0
        }

        // 1. «Подпись + список»: одна колонка подписей на всю вкладку.
        var pairs: [(label: NSTextField, popup: NSPopUpButton)] = []
        for row in rows {
            let labels = row.compactMap { $0 as? NSTextField }.filter { !$0.isEditable && $0.cell?.wraps != true }
            let popups = row.compactMap { $0 as? NSPopUpButton }
            if labels.count == 1, popups.count == 1, labels[0].frame.minX < popups[0].frame.minX {
                pairs.append((labels[0], popups[0]))
            }
        }
        if !pairs.isEmpty {
            let popupNeed = min(pairs.map { ceil($0.popup.cell?.cellSize.width ?? 0) }.max() ?? 0, right - left - gap - 90)
            let labelNeed = pairs.map { ceil($0.label.cell?.cellSize.width ?? 0) + 2 }.max() ?? 0
            // Колонка не уже самого длинного слова: иначе слово рвётся по буквам («Դասավորությա / ն»).
            let longestWord = pairs.flatMap { p in
                p.label.stringValue.split(whereSeparator: \.isWhitespace).map { word in
                    ceil(NSAttributedString(string: String(word), attributes: [.font: p.label.font ?? SystemTypography.font(.body)]).size().width) + 4
                }
            }.max() ?? 0
            let column = min(labelNeed, max(90, right - left - gap - popupNeed))
            if column >= longestWord {
                for (label, popup) in pairs {
                    label.frame = NSRect(x: left, y: label.frame.minY, width: column, height: label.frame.height)
                    if ceil(label.cell?.cellSize.width ?? 0) + 2 > column {
                        makeWrapping(label)
                        setHeight(label, fitHeight(label, width: column))
                    }
                    let x = left + column + gap
                    popup.frame = NSRect(x: x, y: popup.frame.minY, width: right - x, height: popup.frame.height)
                }
            } else {
                // Подписи над списками, во всю ширину — одинаково для всей вкладки.
                for (label, popup) in pairs {
                    let top = max(label.frame.maxY, popup.frame.maxY)
                    let rowHeight = top - min(label.frame.minY, popup.frame.minY)
                    makeWrapping(label)
                    let lh = fitHeight(label, width: right - left)
                    label.frame = NSRect(x: left, y: top - lh, width: right - left, height: lh)
                    popup.frame = NSRect(x: left, y: label.frame.minY - 4 - popup.frame.height,
                                         width: right - left, height: popup.frame.height)
                    grow[ObjectIdentifier(popup), default: 0] += (lh + 4 + popup.frame.height) - rowHeight
                }
            }
        }

        // 2. Многострочные пояснения и чекбоксы (кнопки без рамки) — высота по тексту.
        for v in items {
            if let tf = v as? NSTextField, !tf.isEditable, tf.cell?.wraps == true {
                let h = fitHeight(tf, width: tf.frame.width)
                if h > tf.frame.height { setHeight(tf, h) }
            } else if let b = v as? NSButton, !(b is NSPopUpButton), !b.isBordered, !b.title.isEmpty,
                      ceil(b.cell?.cellSize.width ?? 0) > b.frame.width {
                makeWrapping(b)
                setHeight(b, max(b.frame.height, fitHeight(b, width: b.frame.width)))
            }
        }

        // 3. Кнопки с рамкой: ширина по тексту; ряд, который не влезает, — в столбик на всю ширину.
        for row in rows {
            let buttons = row.compactMap { $0 as? NSButton }.filter { !($0 is NSPopUpButton) && $0.isBordered }
                .sorted { $0.frame.minX < $1.frame.minX }
            guard !buttons.isEmpty else { continue }
            let need = buttons.map { ceil($0.cell?.cellSize.width ?? 0) + 2 }     // cellSize уже с полями кнопки
            guard zip(buttons, need).contains(where: { $0.frame.width < $1 }) else { continue }
            let start = buttons[0].frame.minX
            let rowGap: CGFloat = buttons.count > 1 ? buttons[1].frame.minX - buttons[0].frame.maxX : 10
            let gaps = rowGap * CGFloat(buttons.count - 1)
            // прежние ширины, где хватает; если ряд так не влезает — точно по тексту
            var widths = zip(buttons, need).map { max($0.frame.width, $1) }
            if start + widths.reduce(0, +) + gaps > right { widths = need }
            if start + widths.reduce(0, +) + gaps <= right {
                var x = start
                for (b, w) in zip(buttons, widths) {
                    b.frame = NSRect(x: x, y: b.frame.minY, width: w, height: b.frame.height)
                    x += w + rowGap
                }
            } else {
                // столбиком: первая кнопка на месте, остальные ниже; рост ряда — на первой кнопке
                let h = buttons[0].frame.height, step = h + 8
                for (i, b) in buttons.enumerated() {
                    b.frame = NSRect(x: start, y: buttons[0].frame.minY - CGFloat(i) * step, width: right - start, height: h)
                }
                grow[ObjectIdentifier(buttons[0]), default: 0] += step * CGFloat(buttons.count - 1)
            }
        }

        // 4. Сдвиг вниз всего, что ниже выросших элементов.
        var offset: CGFloat = 0
        for row in rows {
            var rowGrow: CGFloat = 0
            for v in row {
                v.frame.origin.y -= offset
                rowGrow = max(rowGrow, grow[ObjectIdentifier(v)] ?? 0)
            }
            offset += rowGrow
        }

        // 5. Высота вкладки — по содержимому: прежний отступ сверху, 16 снизу.
        let low = items.map { $0.frame.minY }.min() ?? 0
        let high = items.map { $0.frame.maxY }.max() ?? 0
        let height = topMargin + (high - low) + 16
        for v in items { v.frame.origin.y += 16 - low }
        view.frame = NSRect(x: view.frame.minX, y: view.frame.minY, width: view.frame.width, height: height)
    }

    private func createGeneralTab() -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = L10n.settingsTabGeneral

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 790))
        var y: CGFloat = 750

        // Автопереключение
        let autoSwitch = NSButton(checkboxWithTitle: L10n.settingsAutoSwitch, target: self, action: #selector(autoSwitchChanged))
        autoSwitch.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        autoSwitch.state = SettingsManager.shared.autoSwitchEnabled ? .on : .off
        view.addSubview(autoSwitch)
        autoSwitchCheckbox = autoSwitch
        y -= 30

        // Триггер конвертации
        let triggerLabel = NSTextField(labelWithString: L10n.settingsTrigger)
        triggerLabel.frame = NSRect(x: 20, y: y, width: 150, height: 22)
        view.addSubview(triggerLabel)

        let triggerPopup = NSPopUpButton(frame: NSRect(x: 175, y: y - 2, width: 255, height: 26))
        populateTriggerPopup(triggerPopup)
        triggerPopup.target = self
        triggerPopup.action = #selector(triggerChanged)
        view.addSubview(triggerPopup)
        y -= 34

        let rightOnlyCheckbox = NSButton(checkboxWithTitle: L10n.settingsTriggerRightOnly, target: self, action: #selector(triggerRightOnlyChanged))
        rightOnlyCheckbox.frame = NSRect(x: 40, y: y, width: 390, height: 22)
        rightOnlyCheckbox.state = SettingsManager.shared.triggerRightOnly ? .on : .off
        view.addSubview(rightOnlyCheckbox)
        y -= 26

        let doubleTapCheckbox = NSButton(checkboxWithTitle: L10n.settingsTriggerDoubleTap, target: self, action: #selector(triggerDoubleTapChanged))
        doubleTapCheckbox.frame = NSRect(x: 40, y: y, width: 390, height: 22)
        doubleTapCheckbox.state = SettingsManager.shared.triggerDoubleTap ? .on : .off
        view.addSubview(doubleTapCheckbox)
        y -= 30

        // issue #14: отдельный хоткей чистого переключения раскладки (без конверсии) —
        // в т.ч. Ctrl+Shift и другие модификаторные комбо, недоступные системным настройкам.
        let switchLabel = NSTextField(labelWithString: L10n.settingsSwitchHotkey)
        switchLabel.frame = NSRect(x: 20, y: y, width: 150, height: 22)
        view.addSubview(switchLabel)

        let switchPopup = NSPopUpButton(frame: NSRect(x: 175, y: y - 2, width: 255, height: 26))
        populateSwitchHotkeyPopup(switchPopup)
        switchPopup.target = self
        switchPopup.action = #selector(switchHotkeyChanged)
        view.addSubview(switchPopup)
        switchHotkeyPopup = switchPopup
        y -= 34   // как зазор popup→rightOnly у триггера (попап высотой 26 на y-2)

        // issue #14: только правая клавиша хоткея смены (зеркало rightOnly триггера).
        let switchRightOnlyCheckbox = NSButton(checkboxWithTitle: L10n.settingsTriggerRightOnly, target: self, action: #selector(switchRightOnlyChanged))
        switchRightOnlyCheckbox.frame = NSRect(x: 40, y: y, width: 390, height: 22)
        switchRightOnlyCheckbox.state = SettingsManager.shared.switchRightOnly ? .on : .off
        view.addSubview(switchRightOnlyCheckbox)
        y -= 26

        // issue #14: смена по двойному тапу выбранного хоткея (зеркало double-tap триггера).
        let switchDoubleTapCheckbox = NSButton(checkboxWithTitle: L10n.settingsTriggerDoubleTap, target: self, action: #selector(switchDoubleTapChanged))
        switchDoubleTapCheckbox.frame = NSRect(x: 40, y: y, width: 390, height: 22)
        switchDoubleTapCheckbox.state = SettingsManager.shared.switchDoubleTap ? .on : .off
        view.addSubview(switchDoubleTapCheckbox)
        y -= 34

        // issue #29: отдельный хоткей смены регистра (последнее слово / выделение), как Alt+Break
        // в Punto. Должен отличаться от триггера и от хоткея смены раскладки (движок игнорирует совпадения).
        let caseLabel = NSTextField(labelWithString: L10n.settingsCaseHotkey)
        caseLabel.frame = NSRect(x: 20, y: y, width: 150, height: 22)
        view.addSubview(caseLabel)

        let casePopup = NSPopUpButton(frame: NSRect(x: 175, y: y - 2, width: 255, height: 26))
        populateCaseHotkeyPopup(casePopup)
        casePopup.target = self
        casePopup.action = #selector(caseHotkeyChanged)
        view.addSubview(casePopup)
        caseHotkeyPopup = casePopup
        y -= 34

        let caseRightOnlyCheckbox = NSButton(checkboxWithTitle: L10n.settingsTriggerRightOnly, target: self, action: #selector(caseRightOnlyChanged))
        caseRightOnlyCheckbox.frame = NSRect(x: 40, y: y, width: 390, height: 22)
        caseRightOnlyCheckbox.state = SettingsManager.shared.caseRightOnly ? .on : .off
        view.addSubview(caseRightOnlyCheckbox)
        y -= 26

        let caseDoubleTapCheckbox = NSButton(checkboxWithTitle: L10n.settingsTriggerDoubleTap, target: self, action: #selector(caseDoubleTapChanged))
        caseDoubleTapCheckbox.frame = NSRect(x: 40, y: y, width: 390, height: 22)
        caseDoubleTapCheckbox.state = SettingsManager.shared.caseDoubleTap ? .on : .off
        view.addSubview(caseDoubleTapCheckbox)
        y -= 32

        let triggerHint = NSTextField(wrappingLabelWithString: L10n.settingsTriggerHint)
        triggerHint.frame = NSRect(x: 40, y: y - 22, width: 400, height: 36)
        triggerHint.font = SystemTypography.font(.footnote)
        triggerHint.textColor = .secondaryLabelColor
        view.addSubview(triggerHint)
        y -= 48

        // Запуск при логине
        let loginCheckbox = NSButton(checkboxWithTitle: L10n.settingsLaunchAtLogin, target: self, action: #selector(launchAtLoginChanged))
        loginCheckbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        loginCheckbox.state = SettingsManager.shared.launchAtLogin ? .on : .off
        view.addSubview(loginCheckbox)
        launchAtLoginCheckbox = loginCheckbox
        y -= 30

        // Запоминание раскладки по приложению
        let perAppCheckbox = NSButton(checkboxWithTitle: L10n.settingsPerAppLayout, target: self, action: #selector(perAppLayoutChanged))
        perAppCheckbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        perAppCheckbox.state = SettingsManager.shared.perAppLayout ? .on : .off
        view.addSubview(perAppCheckbox)
        y -= 30

        // Язык интерфейса
        let langLabel = NSTextField(labelWithString: L10n.settingsLanguage)
        langLabel.frame = NSRect(x: 20, y: y, width: 130, height: 22)
        view.addSubview(langLabel)

        let langPopup = NSPopUpButton(frame: NSRect(x: 155, y: y - 2, width: 275, height: 26))
        populateLanguagePopup(langPopup)
        langPopup.target = self
        langPopup.action = #selector(languageChanged)
        view.addSubview(langPopup)
        languagePopup = langPopup
        y -= 40

        // Раскладка 1
        let label1 = NSTextField(labelWithString: L10n.settingsLayout1)
        label1.frame = NSRect(x: 20, y: y, width: 100, height: 22)
        view.addSubview(label1)

        let popup1 = NSPopUpButton(frame: NSRect(x: 130, y: y - 2, width: 300, height: 26))
        populateLayoutPopup(popup1, selectedID: SettingsManager.shared.layout1ID)
        popup1.target = self
        popup1.action = #selector(layout1Changed)
        view.addSubview(popup1)
        layout1Popup = popup1
        y -= 35

        // Раскладка 2
        let label2 = NSTextField(labelWithString: L10n.settingsLayout2)
        label2.frame = NSRect(x: 20, y: y, width: 100, height: 22)
        view.addSubview(label2)

        let popup2 = NSPopUpButton(frame: NSRect(x: 130, y: y - 2, width: 300, height: 26))
        populateLayoutPopup(popup2, selectedID: SettingsManager.shared.layout2ID)
        popup2.target = self
        popup2.action = #selector(layout2Changed)
        view.addSubview(popup2)
        layout2Popup = popup2
        y -= 50

        // Описание хоткея
        let hotkeyLabel = NSTextField(wrappingLabelWithString: L10n.settingsHotkey)
        hotkeyLabel.frame = NSRect(x: 20, y: y - 40, width: 420, height: 55)
        hotkeyLabel.font = SystemTypography.font(.footnote)
        hotkeyLabel.textColor = .secondaryLabelColor
        view.addSubview(hotkeyLabel)

        fitToText(view)
        item.view = topAligned(view)
        return item
    }

    // MARK: - Exceptions Tab

    private func createExceptionsTab() -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = L10n.settingsTabExceptions

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 600))
        var y: CGFloat = 586          // y — верх следующего элемента, идём сверху вниз
        exceptionEditors.removeAll()

        // Авто-конвертация
        let autoConvert = NSButton(checkboxWithTitle: L10n.settingsAutoConvert, target: self, action: #selector(autoConvertChanged))
        autoConvert.frame = NSRect(x: 20, y: y - 22, width: 420, height: 22)
        autoConvert.state = SettingsManager.shared.autoConvert ? .on : .off
        view.addSubview(autoConvert)
        autoConvertCheckbox = autoConvert
        y -= 24
        let acHint = NSTextField(wrappingLabelWithString: L10n.settingsAutoConvertHint)
        acHint.frame = NSRect(x: 40, y: y - 32, width: 400, height: 32)
        acHint.font = SystemTypography.font(.footnote); acHint.textColor = .secondaryLabelColor
        view.addSubview(acHint)
        y -= 38

        // Флаг у курсора (issue #10)
        let caretFlag = NSButton(checkboxWithTitle: L10n.settingsCaretFlag, target: self, action: #selector(caretFlagChanged))
        caretFlag.frame = NSRect(x: 20, y: y - 22, width: 420, height: 22)
        caretFlag.state = SettingsManager.shared.caretFlag ? .on : .off
        view.addSubview(caretFlag)
        caretFlagCheckbox = caretFlag
        y -= 24
        let cfHint = NSTextField(wrappingLabelWithString: L10n.settingsCaretFlagHint)
        cfHint.frame = NSRect(x: 40, y: y - 44, width: 400, height: 44)
        cfHint.font = SystemTypography.font(.footnote); cfHint.textColor = .secondaryLabelColor
        view.addSubview(cfHint)
        y -= 52

        // Режим удалённого стола отложен в 2.5 — блок скрыт за флагом (для тестирования).
        if SettingsManager.shared.showRemoteDesktopBeta {
            let remote = NSButton(checkboxWithTitle: L10n.menuRemoteDesktop, target: self, action: #selector(remoteDesktopChanged))
            remote.frame = NSRect(x: 20, y: y - 22, width: 420, height: 22)
            remote.state = SettingsManager.shared.remoteDesktopMode ? .on : .off
            view.addSubview(remote)
            remoteDesktopCheckbox = remote
            y -= 24
            let rHint = NSTextField(wrappingLabelWithString: L10n.settingsRemoteDesktopHint)
            rHint.frame = NSRect(x: 40, y: y - 44, width: 400, height: 44)
            rHint.font = SystemTypography.font(.footnote); rHint.textColor = .secondaryLabelColor
            view.addSubview(rHint)
            y -= 52
        }

        // Секция: заголовок сверху, ниже — таблица с кнопками. Зазоры фиксированные,
        // поэтому раскладка одинаково корректна на всех языках (заголовки не переносятся).
        func addSection(_ title: String, _ editor: ExceptionListEditor) {
            let header = NSTextField(labelWithString: title)
            header.frame = NSRect(x: 20, y: y - 18, width: 420, height: 18)
            header.font = SystemTypography.font(.subheadline, weight: .bold)
            header.lineBreakMode = .byTruncatingTail
            view.addSubview(header)
            let contH: CGFloat = 96
            let cont = editor.makeContainer(frame: NSRect(x: 20, y: y - 22 - contH, width: 420, height: contH))
            view.addSubview(cont)
            exceptionEditors.append(editor)
            y -= (22 + contH + 14)   // заголовок+зазор + таблица + зазор до следующей секции
        }

        addSection(L10n.settingsExceptionsApps, ExceptionListEditor(
            kind: .apps,
            get: { SettingsManager.shared.deniedApps },
            set: { SettingsManager.shared.deniedApps = $0 },
            isProtected: { AutoSwitchPolicy.protectedApps.contains($0) }))

        addSection(L10n.settingsExceptionsAllActions, ExceptionListEditor(
            kind: .apps,
            get: { SettingsManager.shared.allActionsDeniedApps },
            set: { SettingsManager.shared.allActionsDeniedApps = $0 }))

        fitToText(view)
        item.view = topAligned(view)
        return item
    }

    // MARK: - Learning Tab

    private func createRulesTab() -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = L10n.settingsTabRules

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 670))
        let editor = UserRuleEditor()
        editor.onRulesChanged = { [weak self] in
            self?.exceptionEditors.forEach { $0.reloadFromStore() }
        }
        let container = editor.makeContainer(frame: NSRect(x: 20, y: 54, width: 540, height: 590))
        container.autoresizingMask = [.width, .height]
        view.addSubview(container)
        let importPunto = NSButton(title: L10n.settingsImportPunto, target: self, action: #selector(importPuntoProfile))
        importPunto.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        importPunto.imagePosition = .imageLeading
        importPunto.bezelStyle = .rounded
        importPunto.frame = NSRect(x: 20, y: 16, width: 320, height: 30)
        importPunto.autoresizingMask = [.maxYMargin]
        view.addSubview(importPunto)
        ruleEditor = editor

        item.view = topAligned(view, fillsHeight: true)
        return item
    }

    private func createLearningTab() -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = L10n.settingsTabLearning

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 520))
        let hint = NSTextField(wrappingLabelWithString: L10n.learningListHint)
        hint.frame = NSRect(x: 20, y: 476, width: 420, height: 38)
        hint.font = SystemTypography.font(.footnote)
        hint.textColor = .secondaryLabelColor
        view.addSubview(hint)

        let editor = LearningListEditor()
        let container = editor.makeContainer(frame: NSRect(x: 20, y: 18, width: 420, height: 440))
        view.addSubview(container)
        editor.reloadFromStore()
        learningListEditor = editor

        item.view = topAligned(view, fillsHeight: true)
        return item
    }

    // MARK: - About Tab

    private func createAboutTab() -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = L10n.settingsTabAbout

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 450))
        var y: CGFloat = 400

        // Название и версия
        let titleLabel = NSTextField(labelWithString: "MultiSwitcher")
        titleLabel.font = SystemTypography.font(.title2, weight: .bold)
        titleLabel.frame = NSRect(x: 20, y: y, width: 420, height: 28)
        view.addSubview(titleLabel)
        y -= 25

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let devTag = Bundle.main.infoDictionary?["MSDevTag"] as? String ?? ""
        let versionLabel = NSTextField(labelWithString: "v\(version)\(devTag)")
        versionLabel.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        versionLabel.font = SystemTypography.font(.subheadline)
        versionLabel.textColor = .secondaryLabelColor
        view.addSubview(versionLabel)
        y -= 22

        if UpdateChecker.isConfigured {
            let updateCheck = NSButton(checkboxWithTitle: L10n.settingsCheckUpdates,
                                       target: self, action: #selector(updateChecksChanged(_:)))
            updateCheck.frame = NSRect(x: 20, y: 312, width: 420, height: 22)
            updateCheck.state = SettingsManager.shared.checkUpdatesEnabled ? .on : .off
            view.addSubview(updateCheck)

            let checkNow = NSButton(title: L10n.menuCheckUpdates, target: self,
                                    action: #selector(checkForUpdatesNow(_:)))
            checkNow.frame = NSRect(x: 20, y: 270, width: 190, height: 30)
            view.addSubview(checkNow)
        }

        let localNotice = NSTextField(wrappingLabelWithString: L10n.settingsAboutLocalNotice)
        localNotice.frame = NSRect(x: 20, y: 174, width: 420, height: 64)
        localNotice.font = SystemTypography.font(.footnote)
        localNotice.textColor = .secondaryLabelColor
        view.addSubview(localNotice)

        if ProfileStore.shared.isInRecoveryMode {
            let recoveryNote = NSTextField(wrappingLabelWithString: L10n.profileRecoveryNotice)
            recoveryNote.frame = NSRect(x: 20, y: 92, width: 420, height: 58)
            recoveryNote.font = SystemTypography.font(.footnote)
            recoveryNote.textColor = .systemOrange
            view.addSubview(recoveryNote)
            profileRecoveryNoteLabel = recoveryNote

            let restore = NSButton(title: L10n.profileRecoveryRestore,
                                   target: self, action: #selector(restorePreviousProfile))
            restore.frame = NSRect(x: 20, y: 48, width: 240, height: 30)
            restore.isEnabled = ProfileStore.shared.canRestorePreviousProfile
            restore.setAccessibilityLabel(L10n.profileRecoveryRestore)
            view.addSubview(restore)
            restoreProfileButton = restore
        }

        fitToText(view)
        item.view = topAligned(view)
        return item
    }

    // MARK: - Advanced Tab

    private func createAdvancedTab() -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = L10n.settingsTabAdvanced

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 595))
        var y: CGFloat = 545

        // issue #22 (B): умная по-словная конверсия выделения. По умолчанию ВКЛ.
        let smartCheckbox = NSButton(checkboxWithTitle: L10n.settingsSmartConversion,
                                     target: self, action: #selector(smartConversionChanged))
        smartConversionCheckbox = smartCheckbox
        smartCheckbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        smartCheckbox.state = SettingsManager.shared.smartConversion ? .on : .off
        smartCheckbox.toolTip = L10n.settingsSmartConversionHint
        view.addSubview(smartCheckbox)
        y -= 18

        let smartHint = NSTextField(wrappingLabelWithString: L10n.settingsSmartConversionHint)
        smartHint.frame = NSRect(x: 40, y: y - 18, width: 400, height: 32)
        smartHint.font = SystemTypography.font(.footnote)
        smartHint.textColor = .secondaryLabelColor
        view.addSubview(smartHint)
        y -= 47

        // issue #22 (A): ручной триггер конвертирует ПО ТЕКСТУ (тотальный флип обеих
        // письменностей). По умолчанию ВЫКЛ; перебивает умную конверсию.
        let byTextCheckbox = NSButton(checkboxWithTitle: L10n.settingsConvertByText,
                                      target: self, action: #selector(convertByTextChanged))
        convertByTextCheckbox = byTextCheckbox
        byTextCheckbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        byTextCheckbox.state = SettingsManager.shared.convertByText ? .on : .off
        byTextCheckbox.toolTip = L10n.settingsConvertByTextHint
        view.addSubview(byTextCheckbox)
        y -= 18

        let byTextHint = NSTextField(wrappingLabelWithString: L10n.settingsConvertByTextHint)
        byTextHint.frame = NSRect(x: 40, y: y - 18, width: 400, height: 32)
        byTextHint.font = SystemTypography.font(.footnote)
        byTextHint.textColor = .secondaryLabelColor
        view.addSubview(byTextHint)
        y -= 47

        // issue #24: триггер конвертирует всю строку (не только последнее слово). По умолч. ВЫКЛ.
        let wholeLineCheckbox = NSButton(checkboxWithTitle: L10n.settingsConvertWholeLine,
                                         target: self, action: #selector(convertWholeLineChanged))
        wholeLineCheckbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        wholeLineCheckbox.state = SettingsManager.shared.convertWholeLine ? .on : .off
        wholeLineCheckbox.toolTip = L10n.settingsConvertWholeLineHint
        view.addSubview(wholeLineCheckbox)
        y -= 18

        let wholeLineHint = NSTextField(wrappingLabelWithString: L10n.settingsConvertWholeLineHint)
        wholeLineHint.frame = NSRect(x: 40, y: y - 18, width: 400, height: 32)
        wholeLineHint.font = SystemTypography.font(.footnote)
        wholeLineHint.textColor = .secondaryLabelColor
        view.addSubview(wholeLineHint)
        y -= 47

        // issue #27: показывать неактивирующую подсказку о защищённом вводе. По умолчанию ВКЛ.
        let secureNoticeCheckbox = NSButton(checkboxWithTitle: L10n.settingsSecureNotice,
                                            target: self, action: #selector(secureNoticeChanged))
        secureNoticeCheckbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        secureNoticeCheckbox.state = SettingsManager.shared.secureInputNoticeEnabled ? .on : .off
        view.addSubview(secureNoticeCheckbox)
        y -= 32

        let dictionaryHeading = NSTextField(labelWithString: L10n.settingsDictionaryPacks)
        dictionaryHeading.font = SystemTypography.font(.body, weight: .semibold)
        dictionaryHeading.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        view.addSubview(dictionaryHeading)
        y -= 27

        let themeTitles = [
            L10n.settingsDictionaryTechnology,
            L10n.settingsDictionaryDesign,
            L10n.settingsDictionaryBrands,
            L10n.settingsDictionarySlang,
        ]
        let themeIDs = ["technology", "design", "brands", "slang"]
        let enabledThemes = SettingsManager.shared.enabledDictionaryThemes
        for (index, title) in themeTitles.enumerated() {
            let checkbox = NSButton(checkboxWithTitle: title, target: self,
                                    action: #selector(dictionaryThemeChanged(_:)))
            checkbox.tag = index
            checkbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
            checkbox.state = enabledThemes.contains(themeIDs[index]) ? .on : .off
            view.addSubview(checkbox)
            y -= 24
        }
        let dictionaryHint = NSTextField(wrappingLabelWithString: L10n.settingsDictionaryPacksHint)
        dictionaryHint.frame = NSRect(x: 40, y: y - 14, width: 400, height: 34)
        dictionaryHint.font = SystemTypography.font(.footnote)
        dictionaryHint.textColor = .secondaryLabelColor
        view.addSubview(dictionaryHint)
        y -= 50

        // Скрыть иконку из меню-бара (запрос пользователя). По умолчанию ВЫКЛ.
        // При включении — подтверждающий алерт с объяснением, как вернуть (reopen).
        let hideIconCheckbox = NSButton(checkboxWithTitle: L10n.settingsHideIcon,
                                        target: self, action: #selector(hideIconChanged(_:)))
        hideIconCheckbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        hideIconCheckbox.state = SettingsManager.shared.hideMenuBarIcon ? .on : .off
        view.addSubview(hideIconCheckbox)
        y -= 18

        let hideIconHint = NSTextField(wrappingLabelWithString: L10n.settingsHideIconHint)
        hideIconHint.frame = NSRect(x: 40, y: y - 18, width: 400, height: 32)
        hideIconHint.font = SystemTypography.font(.footnote)
        hideIconHint.textColor = .secondaryLabelColor
        view.addSubview(hideIconHint)
        y -= 47

        // Debug log
        let debugCheckbox = NSButton(checkboxWithTitle: L10n.settingsDebugLog, target: self, action: #selector(debugLogChanged))
        debugCheckbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        debugCheckbox.state = SettingsManager.shared.debugLogEnabled ? .on : .off
        view.addSubview(debugCheckbox)
        debugLogCheckbox = debugCheckbox
        y -= 35

        // Показать лог
        let showLogBtn = NSButton(title: L10n.settingsShowLog, target: self, action: #selector(showLogFile))
        showLogBtn.frame = NSRect(x: 20, y: y, width: 180, height: 32)
        showLogBtn.bezelStyle = .rounded
        view.addSubview(showLogBtn)

        // Отправить лог
        let sendLogBtn = NSButton(title: L10n.settingsSendLog, target: self, action: #selector(sendLogFile))
        sendLogBtn.frame = NSRect(x: 210, y: y, width: 180, height: 32)
        sendLogBtn.bezelStyle = .rounded
        view.addSubview(sendLogBtn)
        y -= 50

        // Путь к логу
        let logPath = logFilePath()
        let pathLabel = NSTextField(wrappingLabelWithString: logPath)
        pathLabel.frame = NSRect(x: 20, y: y - 20, width: 420, height: 40)
        pathLabel.font = SystemTypography.font(.caption2)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.isSelectable = true
        view.addSubview(pathLabel)
        y -= 70

        // Завершить приложение. Обязателен при скрытой иконке: LSUIElement-приложение без
        // меню-бара не ловит Cmd-Q, и другого пути выйти при isVisible=false просто нет.
        let quitBtn = NSButton(title: L10n.settingsQuit, target: self, action: #selector(quitApp))
        quitBtn.frame = NSRect(x: 20, y: y, width: 200, height: 32)
        quitBtn.bezelStyle = .rounded
        view.addSubview(quitBtn)

        fitToText(view)
        item.view = topAligned(view)
        return item
    }

    @objc private func hideIconChanged(_ sender: NSButton) {
        let hide = sender.state == .on
        if hide {
            // Подтверждение с рецептом возврата — снимает страх «а как я его потом найду».
            let alert = NSAlert()
            alert.messageText = L10n.settingsHideIconAlertTitle
            alert.informativeText = L10n.settingsHideIconAlertText
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.settingsHideIcon)
            alert.addButton(withTitle: L10n.commonCancel)
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() != .alertFirstButtonReturn {
                sender.state = .off
                return
            }
        }
        SettingsManager.shared.hideMenuBarIcon = hide
        onHideIconChanged?(hide)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Language Popup

    private func populateLanguagePopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        popup.addItem(withTitle: "🌐 \(L10n.settingsLanguageAuto)")
        popup.menu?.items.last?.representedObject = "" as NSString

        for lang in L10n.languageNames {
            popup.addItem(withTitle: lang.name)
            popup.menu?.items.last?.representedObject = lang.code as NSString
        }

        selectItem(in: popup, matching: SettingsManager.shared.interfaceLanguage)
    }

    /// Выбирает в popup пункт, у которого representedObject == id (или первый при пустом id)
    private func selectItem(in popup: NSPopUpButton, matching id: String) {
        if id.isEmpty {
            popup.selectItem(at: 0)
            return
        }
        for (i, item) in popup.itemArray.enumerated() {
            if (item.representedObject as? String) == id {
                popup.selectItem(at: i)
                return
            }
        }
        popup.selectItem(at: 0)
    }

    // MARK: - Layout Popup

    private func populateLayoutPopup(_ popup: NSPopUpButton, selectedID: String) {
        popup.removeAllItems()
        popup.addItem(withTitle: L10n.settingsAutoDetect)
        popup.menu?.items.last?.representedObject = "" as NSString

        let layouts = LayoutSwitcher.installedLayouts()
        for layout in layouts {
            let id = LayoutSwitcher.sourceID(layout)
            let name = LayoutSwitcher.sourceName(layout)
            popup.addItem(withTitle: "\(name) (\(id.components(separatedBy: ".").last ?? id))")
            popup.menu?.items.last?.representedObject = id as NSString
        }

        selectItem(in: popup, matching: selectedID)
    }

    private func selectedLayoutID(from popup: NSPopUpButton) -> String {
        (popup.selectedItem?.representedObject as? String) ?? ""
    }

    // MARK: - Trigger Popup

    private func populateTriggerPopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        // Имена клавиш не локализуем — это стандартные обозначения Apple.
        let items: [(key: String, title: String)] = [
            ("option", "Option ⌥ (Alt)"),
            ("command", "Command ⌘"),
            ("control", "Control ⌃"),
            ("shift", "Shift ⇧"),
            // Caps Lock убран: нативный перехват нестабилен (HID-дебаунс/тоггл) — см. техдолг.
        ]
        // issue #12: комбо двух модификаторов (привычный по Windows стиль Alt+Shift).
        let comboItems: [(key: String, title: String)] = [
            ("option+shift", "⌥ + ⇧  (Option + Shift)"),   // discussion #32: виндовый дефолт
            ("command+shift", "⌘ + ⇧  (Command + Shift)"),
            ("control+shift", "⌃ + ⇧  (Control + Shift)"),
            ("command+option", "⌘ + ⌥  (Command + Option)"),
            ("control+option", "⌃ + ⌥  (Control + Option)"),
        ]
        for it in items {
            popup.addItem(withTitle: it.title)
            popup.menu?.items.last?.representedObject = it.key as NSString
        }
        popup.menu?.addItem(.separator())
        for it in comboItems {
            popup.addItem(withTitle: it.title)
            popup.menu?.items.last?.representedObject = it.key as NSString
        }
        selectItem(in: popup, matching: SettingsManager.shared.triggerKey)
    }

    // MARK: - Actions

    @objc private func autoSwitchChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        SettingsManager.shared.autoSwitchEnabled = enabled
        onAutoSwitchChanged?(enabled)
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        SettingsManager.shared.launchAtLogin = sender.state == .on
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let langCode = (sender.selectedItem?.representedObject as? String) ?? ""
        SettingsManager.shared.interfaceLanguage = langCode  // вызывает L10n.reloadLanguage()
        onLanguageChanged?()  // пересобрать меню статус-бара под новый язык
        // Пересоздаём окно для применения нового языка
        window?.close()
        window = nil
        showWindow()
    }

    @objc private func layout1Changed(_ sender: NSPopUpButton) {
        SettingsManager.shared.layout1ID = selectedLayoutID(from: sender)
        DynamicKeyMapping.clearCache()
    }

    @objc private func layout2Changed(_ sender: NSPopUpButton) {
        SettingsManager.shared.layout2ID = selectedLayoutID(from: sender)
        DynamicKeyMapping.clearCache()
    }

    @objc private func perAppLayoutChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        SettingsManager.shared.perAppLayout = enabled
        onPerAppLayoutChanged?(enabled)
    }

    @objc private func triggerChanged(_ sender: NSPopUpButton) {
        SettingsManager.shared.triggerKey = (sender.selectedItem?.representedObject as? String) ?? "option"
        onTriggerChanged?()
        // issue #3: «занят триггером» в списке хоткея смены зависит от текущего триггера —
        // пере-populate, иначе метка устареет и можно выбрать хоткей = триггеру (молча мёртвый).
        if let p = switchHotkeyPopup { populateSwitchHotkeyPopup(p) }
        if let p = caseHotkeyPopup { populateCaseHotkeyPopup(p) }   // issue #29: та же логика для хоткея регистра
    }

    /// issue #14: попап второго хоткея — «Выключен» + те же модификаторы/комбо (без Caps Lock).
    private func populateSwitchHotkeyPopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        popup.addItem(withTitle: L10n.settingsSwitchHotkeyOff)
        popup.menu?.items.last?.representedObject = "" as NSString
        popup.menu?.addItem(.separator())
        let items: [(key: String, title: String)] = [
            ("option", "Option ⌥ (Alt)"),
            ("command", "Command ⌘"),
            ("control", "Control ⌃"),
            ("shift", "Shift ⇧"),
        ]
        let comboItems: [(key: String, title: String)] = [
            ("option+shift", "⌥ + ⇧  (Option + Shift)"),   // discussion #32: виндовый дефолт
            ("command+shift", "⌘ + ⇧  (Command + Shift)"),
            ("control+shift", "⌃ + ⇧  (Control + Shift)"),
            ("command+option", "⌘ + ⌥  (Command + Option)"),
            ("control+option", "⌃ + ⌥  (Control + Option)"),
        ]
        for it in items {
            popup.addItem(withTitle: it.title)
            popup.menu?.items.last?.representedObject = it.key as NSString
        }
        popup.menu?.addItem(.separator())
        for it in comboItems {
            popup.addItem(withTitle: it.title)
            popup.menu?.items.last?.representedObject = it.key as NSString
        }
        // Пункт, совпадающий с триггером конверсии, гасим: движок его всё равно
        // игнорирует (один тап не должен делать два действия) — не даём выбрать
        // «мёртвую» настройку без индикации (ревью-находка).
        popup.autoenablesItems = false
        let triggerKey = SettingsManager.shared.triggerKey
        for item in popup.menu?.items ?? [] where (item.representedObject as? String) == triggerKey {
            item.isEnabled = false
            // issue #20: не оставлять пункт немым серым — объяснить, что он занят триггером.
            item.title += L10n.settingsSwitchHotkeyBusy
            item.toolTip = L10n.settingsSwitchHotkeyBusy
        }
        let current = SettingsManager.shared.switchHotkey
        if let idx = popup.menu?.items.firstIndex(where: { ($0.representedObject as? String) == current }) {
            popup.selectItem(at: idx)
        } else {
            popup.selectItem(at: 0)
        }
    }

    @objc private func switchHotkeyChanged(_ sender: NSPopUpButton) {
        SettingsManager.shared.switchHotkey = (sender.selectedItem?.representedObject as? String) ?? ""
        onTriggerChanged?()   // reconfigure перечитает и switchConfig
        if let p = caseHotkeyPopup { populateCaseHotkeyPopup(p) }   // issue #29: хоткей регистра не должен совпасть со сменой раскладки
    }

    /// issue #29: список хоткеев смены регистра. Гасим совпадения с триггером И с хоткеем смены
    /// раскладки — движок их всё равно игнорирует (один тап = одно действие).
    private func populateCaseHotkeyPopup(_ popup: NSPopUpButton) {
        populateSwitchHotkeyPopup(popup)   // те же пункты
        popup.autoenablesItems = false
        let taken: Set<String> = [SettingsManager.shared.triggerKey, SettingsManager.shared.switchHotkey]
        for item in popup.menu?.items ?? [] {
            let key = (item.representedObject as? String) ?? ""
            if !key.isEmpty && taken.contains(key) {
                item.isEnabled = false
                if !item.title.hasSuffix(L10n.settingsSwitchHotkeyBusy) { item.title += L10n.settingsSwitchHotkeyBusy }
            }
        }
        let current = SettingsManager.shared.caseHotkey
        if let idx = popup.menu?.items.firstIndex(where: { ($0.representedObject as? String) == current }) {
            popup.selectItem(at: idx)
        } else {
            popup.selectItem(at: 0)
        }
    }

    @objc private func caseHotkeyChanged(_ sender: NSPopUpButton) {
        SettingsManager.shared.caseHotkey = (sender.selectedItem?.representedObject as? String) ?? ""
        onTriggerChanged?()
    }

    @objc private func caseDoubleTapChanged(_ sender: NSButton) {
        SettingsManager.shared.caseDoubleTap = sender.state == .on
        onTriggerChanged?()
    }

    @objc private func caseRightOnlyChanged(_ sender: NSButton) {
        SettingsManager.shared.caseRightOnly = sender.state == .on
        onTriggerChanged?()
    }

    @objc private func switchDoubleTapChanged(_ sender: NSButton) {
        SettingsManager.shared.switchDoubleTap = sender.state == .on
        onTriggerChanged?()
    }

    @objc private func switchRightOnlyChanged(_ sender: NSButton) {
        SettingsManager.shared.switchRightOnly = sender.state == .on
        onTriggerChanged?()
    }

    @objc private func triggerRightOnlyChanged(_ sender: NSButton) {
        SettingsManager.shared.triggerRightOnly = sender.state == .on
        onTriggerChanged?()
    }

    @objc private func triggerDoubleTapChanged(_ sender: NSButton) {
        SettingsManager.shared.triggerDoubleTap = sender.state == .on
        onTriggerChanged?()
    }

    @objc private func updateChecksChanged(_ sender: NSButton) {
        SettingsManager.shared.checkUpdatesEnabled = sender.state == .on
    }

    @objc private func restorePreviousProfile() {
        do {
            _ = try ProfileStore.shared.restorePreviousProfile()
            exceptionEditors.forEach { $0.reloadFromStore() }
            learningListEditor?.reloadFromStore()
            ruleEditor?.reloadFromStore()
            profileRecoveryNoteLabel?.stringValue = L10n.profileRecoveryRestored
            restoreProfileButton?.isEnabled = false
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.profileRecoveryFailed
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L10n.commonOkay)
            alert.runModal()
        }
    }

    @objc private func checkForUpdatesNow(_ sender: NSButton) {
        UpdateChecker.checkNow()
    }

    @objc private func autoConvertChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        SettingsManager.shared.autoConvert = enabled
        onAutoConvertChanged?(enabled)
    }

    @objc private func importPuntoProfile() {
        let panel = NSOpenPanel()
        panel.title = L10n.settingsImportPunto
        panel.message = L10n.settingsImportPuntoChooseFile
        panel.allowedContentTypes = [.propertyList]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        let puntoPreferences = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/ru.yandex.punto.plist")
        if FileManager.default.fileExists(atPath: puntoPreferences.path) {
            panel.directoryURL = puntoPreferences.deletingLastPathComponent()
            panel.nameFieldStringValue = puntoPreferences.lastPathComponent
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let report = try SettingsManager.shared.importPuntoProfile(from: url)
            exceptionEditors.forEach { $0.reloadFromStore() }
            ruleEditor?.reloadFromStore()

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = L10n.settingsImportPuntoSuccess
            alert.informativeText = L10n.settingsImportPuntoAppliedDetails(
                report.rulesImported,
                report.unverifiedRules,
                report.learningImported,
                report.learningDiscardedByReview,
                report.snapshotName
            )
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.settingsImportPuntoFailure
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func remoteDesktopChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        SettingsManager.shared.remoteDesktopMode = enabled
        onRemoteDesktopChanged?(enabled)
    }

    @objc private func caretFlagChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        SettingsManager.shared.caretFlag = enabled
        onCaretFlagChanged?(enabled)
    }

    @objc private func smartConversionChanged(_ sender: NSButton) {
        SettingsManager.shared.smartConversion = sender.state == .on
        if sender.state == .on { convertByTextCheckbox?.state = .off }
    }

    @objc private func convertByTextChanged(_ sender: NSButton) {
        SettingsManager.shared.convertByText = sender.state == .on
        if sender.state == .on { smartConversionCheckbox?.state = .off }
    }

    @objc private func convertWholeLineChanged(_ sender: NSButton) {
        SettingsManager.shared.convertWholeLine = sender.state == .on
    }

    @objc private func secureNoticeChanged(_ sender: NSButton) {
        SettingsManager.shared.secureInputNoticeEnabled = sender.state == .on
    }

    @objc private func dictionaryThemeChanged(_ sender: NSButton) {
        let ids = ["technology", "design", "brands", "slang"]
        guard ids.indices.contains(sender.tag) else { return }
        var enabled = SettingsManager.shared.enabledDictionaryThemes
        let id = ids[sender.tag]
        if sender.state == .on { enabled.insert(id) } else { enabled.remove(id) }
        SettingsManager.shared.enabledDictionaryThemes = enabled
        Dict.setEnabledThemes(enabled)
    }

    @objc private func debugLogChanged(_ sender: NSButton) {
        SettingsManager.shared.debugLogEnabled = sender.state == .on
    }

    @objc private func showLogFile() {
        let path = logFilePath()
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        } else {
            let alert = NSAlert()
            alert.messageText = "Log file not found"
            alert.informativeText = "Enable debug logging first."
            alert.runModal()
        }
    }

    @objc private func sendLogFile() {
        let path = logFilePath()
        guard FileManager.default.fileExists(atPath: path) else {
            showLogFile() // покажет алерт
            return
        }

        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            showLogFile()
            return
        }
        let sanitized = DiagnosticLogRedactor.redact(raw, homeDirectory: NSHomeDirectory())
        let report = String(sanitized.suffix(100_000))

        let preview = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 260))
        preview.string = report
        preview.isEditable = false
        preview.isSelectable = true
        preview.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        preview.textContainer?.widthTracksTextView = true
        preview.isVerticallyResizable = true
        preview.isHorizontallyResizable = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 260))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = preview

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.supportReportPreviewTitle
        alert.informativeText = L10n.supportReportPreviewBody
        alert.accessoryView = scroll
        alert.addButton(withTitle: L10n.supportReportShare)
        alert.addButton(withTitle: L10n.commonCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let service = NSSharingService(named: .composeEmail) {
            service.perform(withItems: ["MultiSwitcher diagnostic report" as NSString, report as NSString])
        } else {
            let unavailable = NSAlert()
            unavailable.alertStyle = .informational
            unavailable.messageText = L10n.supportReportUnavailable
            unavailable.addButton(withTitle: L10n.commonOkay)
            unavailable.runModal()
        }
    }

    private func logFilePath() -> String {
        let logDir = NSHomeDirectory() + "/Library/Logs/MultiSwitcher"
        return logDir + "/multiswitcher.log"
    }
}
