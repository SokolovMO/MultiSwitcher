import AppKit
import ApplicationServices
import Carbon
import MultiSwitcherCore
import QuartzCore
import UniformTypeIdentifiers

/// Secondary guidance stays available without competing with the controls.
@MainActor
private final class SettingsHelpDisclosure: NSStackView {
    private let details: NSView
    var onToggle: (() -> Void)?
    private var expanded = false
    init(title: String, details: NSView) {
        self.details = details
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = MultiInterfaceMetrics.Space.sm
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.contentTintColor = .secondaryLabelColor
        button.font = SystemTypography.font(.footnote)
        button.target = self
        button.action = #selector(toggle(_:))
        details.isHidden = true
        addArrangedSubview(button)
        addArrangedSubview(details)
        details.translatesAutoresizingMaskIntoConstraints = false
        details.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func toggle(_ sender: NSButton) {
        expanded.toggle()
        details.isHidden = !expanded
        sender.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        sender.setAccessibilityValue(expanded ? 1 : 0)
        window?.contentView?.layoutSubtreeIfNeeded()
        onToggle?()
    }
}

/// The menu-bar app has no main menu while it runs as an accessory. Handle the
/// standard close shortcut at the window level so it also works from text fields.
@MainActor
private final class SettingsWindow: MultiBoundedWindow {
    var onQuitShortcut: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let extraModifiers = modifiers.intersection([.shift, .option, .control])
        if event.type == .keyDown, modifiers.contains(.command), extraModifiers.isEmpty {
            switch event.keyCode {
            case 13: // W — close Settings, leave the menu-bar app running.
                close()
                return true
            case 12: // Q — quit the app through its normal cleanup path.
                onQuitShortcut?()
                return true
            default:
                break
            }
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

/// A quiet, adaptive selection surface matching the graphite navigation used by MultiShift.
@MainActor
private final class SettingsSidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let selection = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: MultiInterfaceMetrics.Radius.sm,
            yRadius: MultiInterfaceMetrics.Radius.sm
        )
        NSColor.labelColor.withAlphaComponent(dark ? 0.105 : 0.075).setFill()
        selection.fill()
    }
}

/// Stable native button identity; geometry and label alpha share sidebar progress.
@MainActor
private final class SettingsNavigationButton: NSButton {
    var progress: CGFloat = 1 { didSet { needsDisplay = true } }
    var selected = false { didSet { needsDisplay = true } }
    private var hovered = false
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); needsDisplay = true; return result }
    override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); needsDisplay = true; return result }
    override func draw(_ dirtyRect: NSRect) {
        if hovered && !selected {
            DesignPalette.inset.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: MultiInterfaceMetrics.Radius.sm, yRadius: MultiInterfaceMetrics.Radius.sm).fill()
        }
        let ink = selected ? DesignPalette.ink : DesignPalette.secondary
        image?.withSymbolConfiguration(.init(paletteColors: [ink]))?.draw(
            in: NSRect(x: 8, y: bounds.midY - 10, width: 20, height: 20),
            from: .zero, operation: .sourceOver, fraction: isHighlighted ? 0.65 : 1)
        let labelOpacity = min(1, max(0, (progress - 0.35) / 0.65))
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: NSRect(x: 38, y: bounds.midY - 8, width: max(0, bounds.width - 42), height: 16),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: selected ? .medium : .regular),
                             .foregroundColor: ink.withAlphaComponent(labelOpacity), .paragraphStyle: style])
        if window?.firstResponder === self {
            DesignPalette.ink.withAlphaComponent(0.45).setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: MultiInterfaceMetrics.Radius.sm, yRadius: MultiInterfaceMetrics.Radius.sm)
            focus.lineWidth = 1; focus.stroke()
        }
    }
}

/// Dynamic system-colored grouped surface for preference clusters.
@MainActor
private final class SettingsCardBackground: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: MultiInterfaceMetrics.Radius.lg, yRadius: MultiInterfaceMetrics.Radius.lg)
        DesignPalette.surface.setFill()
        path.fill()
        DesignPalette.line.setStroke()
        path.lineWidth = 0.6
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Pins each tab's content to a shared top edge even when NSTabView stretches
/// its item view to the full scroll-document height. Autoresizing masks alone
/// produced different top gaps across the settings pages on macOS 27.
@MainActor
private final class SettingsTopAlignedContainer: NSView {
    private let contentView: NSView
    var maximumContentWidth: CGFloat = MultiInterfaceMetrics.settingsMaximum
    private let fillsHeight: Bool
    private let horizontalInset: CGFloat
    private let verticalInset: CGFloat

    init(content: NSView, containerWidth: CGFloat, fillsHeight: Bool, verticalInset: CGFloat) {
        self.contentView = content
        self.fillsHeight = fillsHeight
        self.horizontalInset = 0
        self.verticalInset = max(0, verticalInset)
        super.init(frame: NSRect(x: 0, y: 0, width: containerWidth,
                                 height: content.frame.height))
        autoresizingMask = [.width, .height]
        autoresizesSubviews = false
        contentView.autoresizingMask = []
        contentView.frame.origin.x = horizontalInset
        addSubview(contentView)
        needsLayout = true
        layoutContent()
    }

    required init?(coder: NSCoder) {
        fatalError("SettingsTopAlignedContainer does not support NSCoder")
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutContent()
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    private func layoutContent() {
        var frame = contentView.frame
        frame.origin.x = bounds.minX + horizontalInset
        frame.size.width = fillsHeight ? max(1, bounds.width) : min(maximumContentWidth + 2 * MultiDesign.pageInset, max(1, bounds.width))

        if fillsHeight {
            let insetFrame = SettingsCardLayoutPolicy.insetFillFrame(
                containerHeight: Double(bounds.height),
                inset: Double(verticalInset)
            )
            frame.origin.y = bounds.minY + CGFloat(insetFrame.originY)
            frame.size.height = CGFloat(insetFrame.height)
        } else {
            let originY = SettingsCardLayoutPolicy.topAlignedOriginY(
                containerHeight: Double(bounds.height),
                contentHeight: Double(frame.height)
            )
            frame.origin.y = bounds.minY + CGFloat(originY)
        }

        if frame != contentView.frame {
            contentView.frame = frame
        }
    }
}

private enum SettingsCardMetrics {
    static let horizontalPadding: CGFloat = MultiInterfaceMetrics.Space.lg
    static let verticalPadding: CGFloat = MultiInterfaceMetrics.Space.md
    static let gutter: CGFloat = MultiInterfaceMetrics.Space.md
    static let controlSpacing: CGFloat = MultiInterfaceMetrics.Space.sm
    static let formLabelGap: CGFloat = MultiInterfaceMetrics.Space.md
}

private enum SettingsMotionMetrics {
    static let pageFadeOut: TimeInterval = 0.07
    static let pageFadeIn: TimeInterval = 0.09
    static let pageFadeOutOpacity: CGFloat = 0.84
    static let expandPage: TimeInterval = 0.22
}

/// Monochrome AЯ app signature with colors that invert naturally with macOS appearance.
@MainActor
private final class SettingsBrandMarkView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        DesignIcon.application(dark: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua, size: 64).draw(in: bounds)
    }
}

/// Нативное окно настроек с полноценной боковой навигацией.
@MainActor
final class SettingsWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTabViewDelegate, NSWindowDelegate {
    private struct PreviewLayoutChoice {
        let id: String
        let name: String
        let language: String
    }

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
    private var sidebarCollapsed = SettingsManager.interfaceDefaults.bool(forKey: "ecosystem.sidebarCollapsed")
    private var ecosystemHost: MultiSidebarHost?
    private var selectedPageIndex = 0
    private var buildingPageTitle = ""
    private var minimumDocumentHeight: CGFloat = 0
    private var baselineDocumentHeight: CGFloat = 0
    private var adaptiveLayoutUpdateGeneration = 0
    private var adaptivePageLayouts: [(outer: NSView, content: NSView, stack: NSStackView)] = []
    private var sidebarWidth: CGFloat = MultiInterfaceMetrics.sidebarExpanded
    private var sidebarProgress: CGFloat = 1
    private weak var sidebarBrandLabel: NSTextField?
    private let sidebarDividerWidth: CGFloat = 1
    private var navigationTable: NSTableView?
    private var suppressSidebarSelectionChange = false
    private var settingsTabView: NSTabView?
    private var autoSwitchCheckbox: NSButton?
    private var launchAtLoginCheckbox: NSButton?
    private var debugLogCheckbox: NSButton?
    private var caretFlagCheckbox: NSButton?
    private var autoConvertCheckbox: NSButton?      // #4: синк тумблера меню → окно настроек
    private var remoteDesktopCheckbox: NSButton?    // #5: то же (опционален — за фичефлагом)
    private weak var conversionModeHint: NSTextField?
    private weak var permissionStatusLabel: NSTextField?
    private weak var permissionStatusSymbol: NSImageView?
    private weak var exampleContextField: NSTextField?
    private weak var exampleWordField: NSTextField?
    private weak var exampleLayoutPopup: NSPopUpButton?
    private weak var exampleCorrectedLabel: NSTextField?
    private weak var exampleNextLayoutLabel: NSTextField?
    private weak var exampleReasonLabel: NSTextField?
    private var layout1Popup: NSPopUpButton?
    private var layout2Popup: NSPopUpButton?
    private weak var themePopup: NSPopUpButton?
    private var languagePopup: NSPopUpButton?
    private var switchHotkeyPopup: NSPopUpButton?   // issue #20/#3: пере-populate при смене триггера
    private var caseHotkeyPopup: NSPopUpButton?     // issue #29
    private var exceptionEditors: [ExceptionListEditor] = []
    private var learningListEditor: LearningListEditor?
    private var ruleEditor: UserRuleEditor?
    private weak var profileRecoveryNoteLabel: NSTextField?
    private weak var restoreProfileButton: NSButton?
    private var pageTransitionGeneration = 0
    private var scrollToTopGeneration = 0
    private var windowShortcutMonitor: Any?

    /// Callback для обновления меню
    var onAutoSwitchChanged: ((Bool) -> Void)?
    var onQuitRequested: (() -> Void)?
    var onPerAppLayoutChanged: ((Bool) -> Void)?
    var onLanguageChanged: (() -> Void)?
    var onTriggerChanged: (() -> Void)?
    var onAutoConvertChanged: ((Bool) -> Void)?
    var onRemoteDesktopChanged: ((Bool) -> Void)?
    var onCaretFlagChanged: ((Bool) -> Void)?
    var onHideIconChanged: ((Bool) -> Void)?
    var onWindowVisibilityChanged: ((Bool) -> Void)?
    var onPermissionsReviewRequested: (() -> Void)?

    func showWindow() {
        refreshPermissionStatus()
        if let window {
            exceptionEditors.forEach { $0.reloadFromStore() }
            learningListEditor?.reloadFromStore()
            ruleEditor?.reloadFromStore()
            NSApp.setActivationPolicy(.regular)
            updateWindowTitle()
            installWindowShortcutMonitor(for: window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            onWindowVisibilityChanged?(true)
            return
        }

        NSApp.setActivationPolicy(.regular)
        sidebarWidth = MultiInterfaceMetrics.sidebarExpanded
        sidebarCollapsed = SettingsManager.interfaceDefaults.bool(forKey: "ecosystem.sidebarCollapsed")
        sidebarProgress = sidebarCollapsed ? 0 : 1
        selectedPageIndex = 0
        let win = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: MultiInterfaceMetrics.switcherDefault.width, height: MultiInterfaceMetrics.switcherDefault.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.onQuitShortcut = { [weak self] in self?.onQuitRequested?() }
        win.title = navigationItems[0].title
        win.appearance = nil
        win.titlebarAppearsTransparent = true
        win.backgroundColor = DesignPalette.window
        win.collectionBehavior = [.managed, .fullScreenNone]
        win.isReleasedWhenClosed = false
        win.delegate = self

        let root = NSView(frame: win.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        root.autoresizesSubviews = true
        root.wantsLayer = true
        rootView = root
        let paneOriginX: CGFloat = 0
        let tabView = NSTabView(frame: root.bounds)
        tabView.tabViewType = .noTabsNoBorder
        tabView.delegate = self

        tabView.addTabViewItem(createGeneralTab())
        tabView.addTabViewItem(createAdvancedTab())     // «Расширенные» — сразу после «Основных»
        tabView.addTabViewItem(createExceptionsTab())
        tabView.addTabViewItem(createRulesTab())
        tabView.addTabViewItem(createLearningTab())
        tabView.addTabViewItem(createAboutTab())
        tabView.addTabViewItem(createAppearanceTab())
        for (index, item) in tabView.tabViewItems.enumerated() {
            (item.view as? SettingsTopAlignedContainer)?.maximumContentWidth = index >= 5
                ? MultiInterfaceMetrics.formMaximum
                : index == 1 || index == 2 ? MultiInterfaceMetrics.complexMaximum : MultiInterfaceMetrics.settingsMaximum
        }
        applyCompactMode(SettingsManager.shared.compactSettings)

        let tallest = tabView.tabViewItems.compactMap { $0.view?.frame.height }.max() ?? 700
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
        let host = MultiSidebarHost(detail: paneScroll)
        host.frame = root.bounds
        host.configure(appName: "multiswitcher", items: ecosystemItems, selected: "0")
        host.onSelect = { [weak self] id in
            guard let index = Int(id) else { return }
            self?.transitionToPage(index, animated: true)
        }
        host.onGeometry = { [weak self] in self?.updateDocumentSize() }
        root.addSubview(host)
        ecosystemHost = host
        host.setCollapsed(sidebarCollapsed, animated: false)
        paneScrollView = paneScroll
        win.contentView = root
        settingsTabView = tabView
        installPageAccessory(on: win)
        applyCompactMode(SettingsManager.shared.compactSettings)
        refreshNavigationSelectionAppearance()
        tabView.selectTabViewItem(at: 0)

        baselineDocumentHeight = tallest
        minimumDocumentHeight = max(baselineDocumentHeight, MultiInterfaceMetrics.switcherDefault.height)
        tabView.frame.size.height = minimumDocumentHeight
        win.setContentSize(MultiWindowPolicy.adjusted(MultiInterfaceMetrics.switcherDefault, in: win))
        let autosaveName = (ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] == nil ? "MultiSwitcher.SettingsWindow" : "MultiSwitcher.SettingsWindow.review")
        win.setFrameAutosaveName(autosaveName)
        let restoredFrame = win.setFrameUsingName(autosaveName)
        if !restoredFrame { win.center() }
        MultiWindowPolicy.configure(win, minimum: MultiInterfaceMetrics.switcherMinimum, maximum: MultiInterfaceMetrics.switcherMaximum)
        DesignStyler.apply(root)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = win
        updateWindowTitle()
        installWindowShortcutMonitor(for: win)
        setSidebarWidth(sidebarWidth)
        onWindowVisibilityChanged?(true)
        updatePagePresentation()
        scrollPaneToTopAfterLayout()
    }

    func closeSettingsWindow() {
        window?.close()
    }

    /// A menu-bar app's menu key equivalents can be skipped by some AppKit
    /// configurations while its settings window is the only regular window. A local
    /// monitor runs before responder dispatch and makes ⌘W reliable even in text fields.
    /// It is active only while this app's Settings window is visible; it never sees keys
    /// typed in other applications.
    private func installWindowShortcutMonitor(for window: NSWindow) {
        guard windowShortcutMonitor == nil else { return }
        windowShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            guard let window, window.isVisible, NSApp.isActive else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.contains(.command),
                  modifiers.intersection([.shift, .option, .control]).isEmpty else { return event }

            // Hardware key codes are stable across ABC/Russian input sources. Keep the
            // character fallback as well for synthetic keyboard events from accessibility
            // tools and remote sessions, which may report a translated character instead.
            let key = event.charactersIgnoringModifiers?.lowercased()
            guard event.keyCode == 13 || key == "w" || key == "ц" else { return event }
            window.close()
            return nil
        }
    }

    private func removeWindowShortcutMonitor() {
        guard let windowShortcutMonitor else { return }
        NSEvent.removeMonitor(windowShortcutMonitor)
        self.windowShortcutMonitor = nil
    }

    private func installPageAccessory(on window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .left
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 72, height: 28))
        let expandImage = NSImage(systemSymbolName: "sidebar.left",
                                  accessibilityDescription: "развернуть страницу")
            ?? NSImage(size: NSSize(width: 16, height: 16))
        let button = NSButton(image: expandImage,
                              target: self, action: #selector(toggleExpandedPage))
        button.frame = NSRect(x: 2, y: 2, width: 28, height: 24)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.toolTip = L10n.settingsExpandPage
        button.setAccessibilityLabel(L10n.settingsExpandPage)
        container.addSubview(button)

        let compactButton = NSButton(image: NSImage(systemSymbolName: "line.3.horizontal.decrease.circle",
                                                      accessibilityDescription: L10n.settingsCompactMode)
                                    ?? NSImage(size: NSSize(width: 16, height: 16)),
                                    target: self, action: #selector(toggleCompactMode))
        compactButton.frame = NSRect(x: 38, y: 2, width: 28, height: 24)
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
        sidebarCollapsed.toggle()
        SettingsManager.interfaceDefaults.set(sidebarCollapsed, forKey: "ecosystem.sidebarCollapsed")
        updatePagePresentation(animated: true)
    }

    private var canExpandSelectedPage: Bool { true }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func updatePagePresentation(animated: Bool = false) {
        let title = L10n.languageCode == "ru"
            ? (sidebarCollapsed ? "раскрыть боковую панель" : "свернуть боковую панель")
            : (sidebarCollapsed ? "expand sidebar" : "collapse sidebar")
        pageExpandButton?.isHidden = false
        pageExpandButton?.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: title)
        pageExpandButton?.toolTip = title
        pageExpandButton?.setAccessibilityLabel(title)
        if ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] == nil {
            ecosystemHost?.setCollapsed(sidebarCollapsed, animated: animated)
        }
        updateDocumentSize()
    }

    private func layoutSidebar() {
        ecosystemHost?.frame = rootView?.bounds ?? .zero
    }

    private func updateDocumentSize() {
        guard let paneScrollView, let documentView = paneScrollView.documentView else { return }
        let clipView = paneScrollView.contentView

        // Propagate a new viewport width through the scroll document and tab view
        // before asking wrapping labels for their fitting height. Measuring first
        // can use the previous, wider width and leave the next card over the text.
        paneScrollView.layoutSubtreeIfNeeded()
        documentView.setFrameSize(NSSize(
            width: paneScrollView.contentSize.width,
            height: max(documentView.frame.height, paneScrollView.contentSize.height)
        ))
        documentView.layoutSubtreeIfNeeded()

        let oldDocumentHeight = documentView.bounds.height
        let oldTopOffset = documentView.isFlipped
            ? clipView.bounds.minY
            : oldDocumentHeight - clipView.bounds.maxY
        let wasNearTop = oldTopOffset <= 48

        // Width changes can wrap localized labels and grow a card. Re-measure the
        // constraint-based pages before sizing the scroll document; a fixed initial
        // height clips the first/last controls after resizing or changing the sidebar.
        for layout in adaptivePageLayouts {
            layout.outer.layoutSubtreeIfNeeded()
            layout.content.layoutSubtreeIfNeeded()
            layout.stack.layoutSubtreeIfNeeded()
            let measuredHeight = ceil(layout.stack.fittingSize.height) + 32
            guard measuredHeight.isFinite, measuredHeight > 32 else { continue }
            layout.content.setFrameSize(NSSize(width: layout.content.frame.width, height: measuredHeight))
            layout.outer.setFrameSize(NSSize(width: layout.outer.frame.width, height: measuredHeight))
            layout.outer.layoutSubtreeIfNeeded()
#if DEBUG
            let cardFrames = layout.stack.arrangedSubviews.map {
                $0.convert($0.bounds, to: layout.stack)
            }
            for first in cardFrames.indices {
                for second in cardFrames.indices where second > first {
                    if NSIntersectsRect(cardFrames[first], cardFrames[second]) {
                        rslog("Settings adaptive card overlap: first=\(first) second=\(second) stack=\(layout.stack.frame) a=\(cardFrames[first]) b=\(cardFrames[second])")
                    }
                }
            }
#endif
        }
        // Each page owns its scroll height. A long advanced page must not push
        // the rules toolbar below the viewport or stretch every empty list.
        let selectedView = settingsTabView?.selectedTabViewItem?.view
        let selectedLayout = adaptivePageLayouts.first { $0.outer === selectedView }
        let selectedHeight = selectedLayout?.content.frame.height ?? paneScrollView.contentSize.height
        minimumDocumentHeight = max(paneScrollView.contentSize.height, selectedHeight)
        documentView.setFrameSize(NSSize(width: paneScrollView.contentSize.width,
                                         height: max(minimumDocumentHeight, paneScrollView.contentSize.height)))
        paneScrollView.layoutSubtreeIfNeeded()

        // Preserve the user's place in long pages. If they were already at the top,
        // keep the top edge anchored when the document grows or the viewport changes.
        var origin = clipView.bounds.origin
        let topOffset = wasNearTop ? 0 : max(0, oldTopOffset)
        origin.y = documentView.isFlipped
            ? topOffset
            : max(0, documentView.bounds.height - clipView.bounds.height - topOffset)
        clipView.scroll(to: origin)
        paneScrollView.reflectScrolledClipView(clipView)
    }

    /// AppKit clip views use a bottom-left origin unless the document is flipped.
    /// Explicitly reveal the document's first row when a page is opened so restored
    /// window sizes never leave the first card underneath the title bar.
    /// A restored/resized NSWindow can finish autoresizing its document view after
    /// `makeKeyAndOrderFront`. Scrolling before that pass uses the old clip-view
    /// height and can leave the first row underneath the title bar. Defer one run-loop
    /// turn, lay out the selected page, then calculate the top offset from final bounds.
    private func scrollPaneToTopAfterLayout() {
        scrollToTopGeneration += 1
        let generation = scrollToTopGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.scrollToTopGeneration == generation,
                  let window = self.window,
                  window.isVisible else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            self.settingsTabView?.selectedTabViewItem?.view?.layoutSubtreeIfNeeded()
            self.updateDocumentSize()
            self.scrollPaneToTop()
        }
    }

    private func scrollPaneToTop() {
        guard let paneScrollView, let documentView = paneScrollView.documentView else { return }
        paneScrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()
        settingsTabView?.selectedTabViewItem?.view?.layoutSubtreeIfNeeded()
        let clipView = paneScrollView.contentView
        var origin = clipView.bounds.origin
        origin.y = documentView.isFlipped
            ? 0
            : max(0, documentView.bounds.height - clipView.bounds.height)
        clipView.scroll(to: origin)
        paneScrollView.reflectScrolledClipView(clipView)
    }

    private func setSidebarWidth(_ requested: CGFloat) {
        sidebarWidth = MultiInterfaceMetrics.sidebarExpanded
        layoutSidebar()
        updateDocumentSize()
    }

    private func applyCompactMode(_ compact: Bool) {
        navigationTable?.rowHeight = MultiInterfaceMetrics.navigationRow
        navigationTable?.intercellSpacing = NSSize(width: 0, height: 4)
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
        removeWindowShortcutMonitor()
        pageTransitionGeneration += 1
        scrollToTopGeneration += 1
        paneScrollView?.alphaValue = 1
        updatePagePresentation()
        onWindowVisibilityChanged?(false)
    }

    func windowDidResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        layoutSidebar()
        updateDocumentSize()
        guard ecosystemHost?.isResizingWindow != true else { return }
        window?.saveFrame(usingName: (ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] == nil ? "MultiSwitcher.SettingsWindow" : "MultiSwitcher.SettingsWindow.review"))
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        layoutSidebar()
        updateDocumentSize()
        window?.contentView?.needsDisplay = true
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        let useful = [3, 4].contains(selectedPageIndex) ? MultiInterfaceMetrics.switcherMaximum : MultiInterfaceMetrics.switcherDefault
        return MultiWindowPolicy.zoomFrame(window, ideal: useful)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let window, (notification.object as? NSWindow) === window else { return }
        MultiWindowPolicy.configure(window, minimum: MultiInterfaceMetrics.switcherMinimum, maximum: MultiInterfaceMetrics.switcherMaximum)
        // AppKit supplies logical points for the new display; reflow without
        // changing the user's explicit expanded/collapsed preference.
        layoutSidebar()
        updateDocumentSize()
    }

    func windowDidMove(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window?.saveFrame(usingName: (ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] == nil ? "MultiSwitcher.SettingsWindow" : "MultiSwitcher.SettingsWindow.review"))
    }

    private var ecosystemItems: [MultiNavigationItem] {
        navigationItems.enumerated().map { MultiNavigationItem(id: String($0.offset), title: $0.element.title, symbol: $0.element.symbol) }
    }

    private var navigationItems: [NavigationItem] {
        [
            NavigationItem(title: L10n.settingsTabGeneral, symbol: "slider.horizontal.3"),
            NavigationItem(title: L10n.settingsTabAdvanced, symbol: "gearshape.2"),
            NavigationItem(title: L10n.settingsTabExceptions, symbol: "arrow.left.arrow.right"),
            NavigationItem(title: L10n.settingsTabRules, symbol: "list.bullet.rectangle"),
            NavigationItem(title: L10n.settingsTabLearning, symbol: "brain.head.profile"),
            NavigationItem(title: L10n.settingsTabAbout, symbol: "info.circle"),
            NavigationItem(title: L10n.languageCode == "ru" ? "внешний вид" : "appearance", symbol: "circle.lefthalf.filled"),
        ]
    }

    private func updateWindowTitle() {
        guard navigationItems.indices.contains(selectedPageIndex) else { return }
        window?.title = navigationItems[selectedPageIndex].title
        window?.titleVisibility = selectedPageIndex == 3 ? .visible : .hidden
    }

    func numberOfRows(in tableView: NSTableView) -> Int { navigationItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard navigationItems.indices.contains(row) else { return nil }
        let item = navigationItems[row]
        let cell = NSTableCellView()
        let button = SettingsNavigationButton(title: item.title, target: self,
                              action: #selector(navigationButtonPressed(_:)))
        button.tag = row
        button.progress = sidebarProgress
        button.selected = tableView.selectedRow == row
        button.focusRingType = .none
        button.isBordered = false
        button.bezelStyle = .inline
        button.alignment = .left
        button.imagePosition = .imageLeading
        button.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        button.contentTintColor = tableView.selectedRow == row ? .labelColor : .secondaryLabelColor
        button.font = NSFont.systemFont(ofSize: 12, weight: tableView.selectedRow == row ? .semibold : .regular)
        button.lineBreakMode = .byTruncatingTail
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setAccessibilityLabel(item.title)
        button.toolTip = item.title
        cell.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            button.topAnchor.constraint(equalTo: cell.topAnchor),
            button.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
        ])
        return cell
    }

    @objc private func navigationButtonPressed(_ sender: NSButton) {
        guard navigationItems.indices.contains(sender.tag) else { return }
        transitionToPage(sender.tag, animated: true)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SettingsSidebarRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let navigationTable,
              (notification.object as? NSTableView) === navigationTable,
              navigationTable.selectedRow >= 0,
              !suppressSidebarSelectionChange else { return }
        // Keep the selection index intact. A full reloadData() here can clear
        // NSTableView's selection before transitionToPage reads selectedRow,
        // leaving the sidebar visible but every navigation item inert.
        let selectedIndex = navigationTable.selectedRow
        transitionToPage(selectedIndex, animated: true)
        refreshNavigationSelectionAppearance()
    }

    private func refreshNavigationSelectionAppearance() {
        guard let navigationTable else { return }
        let selectedRow = navigationTable.selectedRow
        for row in 0..<navigationItems.count {
            guard let cell = navigationTable.view(atColumn: 0, row: row,
                                                   makeIfNecessary: false) as? NSTableCellView else {
                navigationTable.rowView(atRow: row, makeIfNecessary: false)?.needsDisplay = true
                continue
            }
            for subview in cell.subviews {
                if let button = subview as? NSButton {
                    let selected = row == selectedRow
                    (button as? SettingsNavigationButton)?.selected = selected
                    button.contentTintColor = selected ? .labelColor : .secondaryLabelColor
                    button.font = NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
                }
            }
            navigationTable.rowView(atRow: row, makeIfNecessary: false)?.needsDisplay = true
        }
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let tabViewItem,
              let index = tabView.tabViewItems.firstIndex(of: tabViewItem),
              navigationTable?.selectedRow != index else { return }
        selectedPageIndex = index
        updateWindowTitle()
        if !canExpandSelectedPage { sidebarCollapsed = false }
        selectSidebarRow(index)
        updatePagePresentation(animated: true)
    }

    private func transitionToPage(_ index: Int, animated: Bool) {
        guard navigationItems.indices.contains(index) else { return }
        let willChange = selectedPageIndex != index
        selectedPageIndex = index
        updateWindowTitle()
        if !canExpandSelectedPage { sidebarCollapsed = false }
        selectSidebarRow(index)
        guard let settingsTabView, willChange, animated, !reduceMotion, !MultiMotion.keyboard,
              let paneScrollView, window?.isVisible == true else {
            settingsTabView?.selectTabViewItem(at: index)
            updatePagePresentation(animated: willChange)
            if willChange { scrollPaneToTopAfterLayout() }
            return
        }

        pageTransitionGeneration += 1
        let generation = pageTransitionGeneration
        paneScrollView.alphaValue = 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SettingsMotionMetrics.pageFadeOut
            context.timingFunction = MultiMotion.timing
            paneScrollView.animator().alphaValue = SettingsMotionMetrics.pageFadeOutOpacity
            context.completionHandler = { [weak self, weak settingsTabView, weak paneScrollView] in
                guard let self, let settingsTabView, let paneScrollView,
                      self.pageTransitionGeneration == generation else { return }
                settingsTabView.selectTabViewItem(at: index)
                self.updatePagePresentation(animated: true)
                self.scrollPaneToTopAfterLayout()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = SettingsMotionMetrics.pageFadeIn
                    context.timingFunction = MultiMotion.timing
                    paneScrollView.animator().alphaValue = 1
                }
            }
        }
    }

    private func selectSidebarRow(_ index: Int) {
        ecosystemHost?.configure(appName: "multiswitcher", items: ecosystemItems, selected: String(index))
        guard let navigationTable else { return }
        suppressSidebarSelectionChange = true
        navigationTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        suppressSidebarSelectionChange = false
        refreshNavigationSelectionAppearance()
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

    /// Adds a restrained, system-adaptive group surface behind related controls.
    /// It is added after text fitting so the layout pass only measures real controls.
    private func addSettingsCard(to container: NSView,
                                 around views: [NSView],
                                 horizontalPadding: CGFloat = SettingsCardMetrics.horizontalPadding,
                                 verticalPadding: CGFloat = SettingsCardMetrics.verticalPadding,
                                 stretchesVertically: Bool = false) {
        let visible = views.filter { !$0.isHidden }
        guard var frame = visible.first?.frame else { return }
        func expandedFrame() -> NSRect {
            var result = visible[0].frame
            for view in visible.dropFirst() { result = result.union(view.frame) }
            return result.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        }
        frame = expandedFrame()
        let topOverflow = CGFloat(SettingsCardLayoutPolicy.downwardShiftToFitTop(
            containerHeight: Double(container.bounds.height),
            contentMaxY: Double(frame.maxY)
        ))
        if topOverflow > 0 {
            for view in visible { view.frame.origin.y -= topOverflow }
            frame = expandedFrame()
        }
        let existingCards = container.subviews.compactMap { $0 as? SettingsCardBackground }
        let groupIDs = Set(visible.map(ObjectIdentifier.init))
        let followingControls = container.subviews.filter { subview in
            !subview.isHidden && !(subview is SettingsCardBackground) &&
            !groupIDs.contains(ObjectIdentifier(subview)) && subview.frame.maxY <= frame.minY
        }
        let movingControls = visible + followingControls

        // Text fitting can make localized labels taller after the original y positions
        // were assigned. Place this group below the lowest existing card that shares its
        // horizontal span. Moving below the bottom-most card in one step avoids leaving
        // unresolved intersections when a localized row grows after its initial placement.
        let layoutFrame = SettingsCardFrame(
            x: Double(frame.origin.x), y: Double(frame.origin.y),
            width: Double(frame.size.width), height: Double(frame.size.height)
        )
        let existingFrames = existingCards.map { card in
            SettingsCardFrame(
                x: Double(card.frame.origin.x), y: Double(card.frame.origin.y),
                width: Double(card.frame.size.width), height: Double(card.frame.size.height)
            )
        }
        let shift = CGFloat(SettingsCardLayoutPolicy.downwardShift(
            for: layoutFrame,
            existingFrames: existingFrames,
            gutter: Double(SettingsCardMetrics.gutter)
        ))
        if shift > 0 {
            for view in movingControls { view.frame.origin.y -= shift }
            frame = expandedFrame()
        }

        // Keep a non-fatal diagnostic for unusual geometry. Settings must remain usable
        // even if a future localization introduces a layout collision.
#if DEBUG
        if existingCards.contains(where: { $0.frame.intersects(frame) }) {
            rslog("Settings card layout overlap after fallback: new=\(frame), previous=\(existingCards.map(\.frame))")
        }
#endif
        let card = SettingsCardBackground(frame: frame)
        card.autoresizingMask = stretchesVertically ? [.width, .height] : [.width]
        if let firstSubview = container.subviews.first {
            container.addSubview(card, positioned: .below, relativeTo: firstSubview)
        } else {
            container.addSubview(card)
        }
        let minimumContentBottom: CGFloat = 16
        let lowestSubview = container.subviews.filter { !$0.isHidden }
            .map { $0.frame.minY }.min() ?? minimumContentBottom
        let rebase = max(0, minimumContentBottom - lowestSubview)
        if rebase > 0 {
            for subview in container.subviews { subview.frame.origin.y += rebase }
            container.frame.size.height += rebase
        }
    }

    /// Gives every tab the same top anchor. The explicit wrapper layout is needed
    /// because NSTabView's item resizing differs between fixed and adaptive pages.
    private func topAligned(_ content: NSView,
                            fillsHeight: Bool = false,
                            verticalInset: CGFloat = 0) -> NSView {
        let paneWidth: CGFloat = 580
        for child in content.subviews {
            if child is SettingsCardBackground { continue }
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
        return SettingsTopAlignedContainer(content: content, containerWidth: paneWidth,
                                           fillsHeight: fillsHeight, verticalInset: verticalInset)
    }

    /// Constraint-based form primitives for preference pages that need to reflow
    /// predictably as the window, localization, or text size changes.
    private func settingsVerticalStack(
        _ views: [NSView],
        spacing: CGFloat = SettingsCardMetrics.controlSpacing
    ) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = spacing
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    /// Reflows legacy controls as a real Auto Layout stack instead of carrying their
    /// original, fixed x/y coordinates into every window size and localization.
    private func adaptiveControlsStack(
        _ views: [NSView],
        spacing: CGFloat = SettingsCardMetrics.controlSpacing
    ) -> NSStackView {
        views.forEach { $0.removeFromSuperview() }
        for view in views {
            if let label = view as? NSTextField, !label.isEditable {
                label.cell?.wraps = true
                label.cell?.lineBreakMode = .byWordWrapping
                label.maximumNumberOfLines = 0
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            } else if let button = view as? NSButton, !(button is NSPopUpButton) {
                button.cell?.wraps = true
                button.cell?.lineBreakMode = .byWordWrapping
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
        }
        return settingsVerticalStack(views, spacing: spacing)
    }

    private func adaptiveButtonRow(
        _ views: [NSView],
        spacing: CGFloat = SettingsCardMetrics.controlSpacing
    ) -> NSStackView {
        views.forEach { $0.removeFromSuperview() }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.setContentHuggingPriority(.defaultLow, for: .horizontal)
            $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return row
    }

    private func settingsHelp(_ details: NSView) -> NSView {
        let help = SettingsHelpDisclosure(title: L10n.settingsHelpDetails, details: details)
        help.onToggle = { [weak self] in self?.scheduleAdaptiveDocumentLayoutUpdate() }
        return help
    }

    private func settingsCard(containing content: NSView) -> SettingsCardBackground {
        let card = SettingsCardBackground(frame: .zero)
        card.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor,
                                             constant: SettingsCardMetrics.horizontalPadding),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor,
                                              constant: -SettingsCardMetrics.horizontalPadding),
            content.topAnchor.constraint(equalTo: card.topAnchor,
                                         constant: SettingsCardMetrics.verticalPadding),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor,
                                            constant: -SettingsCardMetrics.verticalPadding),
        ])
        return card
    }

    private func settingsFormRow(_ title: String, control: NSView) -> NSStackView {
        let label = NSTextField(wrappingLabelWithString: title)
        label.font = SystemTypography.font(.body)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 0
        label.cell?.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = SettingsCardMetrics.formLabelGap
        row.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        return row
    }

    private func settingsCardPage(_ cards: [NSView], maxContentWidth: CGFloat = MultiInterfaceMetrics.complexMaximum) -> NSView {
        let pageWidth: CGFloat = 540
        let page = NSView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 800))
        let heading = NSTextField(labelWithString: buildingPageTitle)
        heading.font = NSFont.systemFont(ofSize: 19, weight: .semibold)
        heading.textColor = DesignPalette.ink
        let stack = settingsVerticalStack(buildingPageTitle.isEmpty ? cards : [heading] + cards,
                                          spacing: SettingsCardMetrics.gutter)
        // A settings pane can become shorter during window resize or localization.
        // Keep each card at its measured content height instead of letting NSStackView
        // compress neighboring cards into one another.
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        for card in cards {
            card.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        page.addSubview(stack)
        let availableWidth = stack.widthAnchor.constraint(equalTo: page.widthAnchor, constant: -48)
        availableWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: maxContentWidth),
            availableWidth,
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: 24),
        ])
        page.layoutSubtreeIfNeeded()
        let contentHeight = ceil(stack.fittingSize.height)
        page.setFrameSize(NSSize(width: pageWidth, height: contentHeight + 32))
        page.layoutSubtreeIfNeeded()
        let outer = topAligned(page)
        adaptivePageLayouts.append((outer: outer, content: page, stack: stack))
        return outer
    }

    private func createAppearanceTab() -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = L10n.languageCode == "ru" ? "внешний вид" : "appearance"
        buildingPageTitle = ""
        let title = NSTextField(labelWithString: item.label)
        title.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        let hint = NSTextField(wrappingLabelWithString: L10n.languageCode == "ru"
            ? "свет, графит и ничего лишнего. системная тема меняется вместе с macos."
            : "light, graphite, and quiet surfaces. system appearance follows macos.")
        hint.font = NSFont.systemFont(ofSize: 12)
        hint.textColor = DesignPalette.secondary
        let picker = GraphitePopUpButton(frame: .zero)
        picker.addItems(withTitles: InterfaceTheme.allCases.map(\.title))
        picker.selectItem(at: InterfaceTheme.allCases.firstIndex(of: DesignTheme.shared.preference) ?? 0)
        picker.target = self; picker.action = #selector(appearanceChanged(_:))
        themePopup = picker
        let label = L10n.languageCode == "ru" ? "тема" : "theme"
        let row = settingsFormRow(label, control: picker)
        let preview = GraphiteToggleButton(checkboxWithTitle: L10n.languageCode == "ru" ? "монохромные элементы" : "monochrome controls", target: nil, action: nil)
        preview.state = .on; preview.isEnabled = false
        let note = NSTextField(wrappingLabelWithString: L10n.languageCode == "ru"
            ? "анимации учитывают reduce motion, прозрачность — настройки доступности macos. никаких постоянных эффектов в фоне."
            : "motion and transparency respect macos accessibility settings. no continuous effects run in the background.")
        note.font = NSFont.systemFont(ofSize: 11); note.textColor = DesignPalette.secondary
        item.view = settingsCardPage([settingsVerticalStack([title, hint]),
                                      settingsCard(containing: settingsVerticalStack([row, preview])),
                                      settingsCard(containing: note)])
        return item
    }

    @objc private func appearanceChanged(_ sender: NSPopUpButton) {
        guard InterfaceTheme.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        DesignTheme.shared.preference = InterfaceTheme.allCases[sender.indexOfSelectedItem]
        window?.contentView?.needsDisplay = true
    }

    private func createGeneralTab() -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = L10n.settingsTabGeneral
        buildingPageTitle = item.label

        let autoSwitch = GraphiteToggleButton(checkboxWithTitle: L10n.settingsAutoSwitch,
                                  target: self, action: #selector(autoSwitchChanged))
        autoSwitch.state = SettingsManager.shared.autoSwitchEnabled ? .on : .off
        autoSwitchCheckbox = autoSwitch

        let emptySymbol = NSImage(size: NSSize(width: 16, height: 16))
        let permissionSymbol = NSImageView(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: L10n.settingsPermissionsStatus) ?? emptySymbol)
        permissionSymbol.contentTintColor = .secondaryLabelColor
        permissionSymbol.setContentHuggingPriority(.required, for: .horizontal)
        permissionSymbol.setAccessibilityLabel(L10n.settingsPermissionsStatus)
        permissionStatusSymbol = permissionSymbol

        let permissionLabel = NSTextField(wrappingLabelWithString: "")
        permissionLabel.font = SystemTypography.font(.footnote)
        permissionLabel.textColor = .secondaryLabelColor
        permissionLabel.maximumNumberOfLines = 0
        permissionLabel.cell?.lineBreakMode = .byWordWrapping
        permissionStatusLabel = permissionLabel

        let permissionReview = GraphiteButton(title: L10n.settingsPermissionsReview,
                                        target: self, action: #selector(reviewPermissions))
        permissionReview.bezelStyle = .rounded
        permissionReview.setAccessibilityLabel(L10n.settingsPermissionsReview)

        let permissionRow = NSStackView(views: [permissionSymbol, permissionLabel, permissionReview])
        permissionRow.orientation = .horizontal
        permissionRow.alignment = .centerY
        permissionRow.distribution = .fill
        permissionRow.spacing = 8
        permissionRow.translatesAutoresizingMaskIntoConstraints = false
        permissionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        permissionReview.setContentHuggingPriority(.required, for: .horizontal)
        permissionRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true

        let triggerPopup = GraphitePopUpButton(frame: .zero)
        populateTriggerPopup(triggerPopup)
        triggerPopup.target = self
        triggerPopup.action = #selector(triggerChanged)

        let rightOnlyCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.settingsTriggerRightOnly,
                                         target: self, action: #selector(triggerRightOnlyChanged))
        rightOnlyCheckbox.state = SettingsManager.shared.triggerRightOnly ? .on : .off
        let doubleTapCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.settingsTriggerDoubleTap,
                                         target: self, action: #selector(triggerDoubleTapChanged))
        doubleTapCheckbox.state = SettingsManager.shared.triggerDoubleTap ? .on : .off

        let hotkeyLabel = NSTextField(wrappingLabelWithString: L10n.settingsHotkey)
        hotkeyLabel.font = SystemTypography.font(.footnote)
        hotkeyLabel.textColor = .secondaryLabelColor
        hotkeyLabel.maximumNumberOfLines = 0
        hotkeyLabel.cell?.lineBreakMode = .byWordWrapping

        let triggerControls = settingsVerticalStack([
            autoSwitch,
            permissionRow,
            settingsFormRow(L10n.settingsTrigger, control: triggerPopup),
            rightOnlyCheckbox,
            doubleTapCheckbox,
            hotkeyLabel,
        ], spacing: 8)

        let switchPopup = GraphitePopUpButton(frame: .zero)
        populateSwitchHotkeyPopup(switchPopup)
        switchPopup.target = self
        switchPopup.action = #selector(switchHotkeyChanged)
        switchHotkeyPopup = switchPopup

        let switchRightOnlyCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.settingsTriggerRightOnly,
                                               target: self, action: #selector(switchRightOnlyChanged))
        switchRightOnlyCheckbox.state = SettingsManager.shared.switchRightOnly ? .on : .off
        let switchDoubleTapCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.settingsTriggerDoubleTap,
                                               target: self, action: #selector(switchDoubleTapChanged))
        switchDoubleTapCheckbox.state = SettingsManager.shared.switchDoubleTap ? .on : .off

        let casePopup = GraphitePopUpButton(frame: .zero)
        populateCaseHotkeyPopup(casePopup)
        casePopup.target = self
        casePopup.action = #selector(caseHotkeyChanged)
        caseHotkeyPopup = casePopup
        let caseRightOnlyCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.settingsTriggerRightOnly,
                                             target: self, action: #selector(caseRightOnlyChanged))
        caseRightOnlyCheckbox.state = SettingsManager.shared.caseRightOnly ? .on : .off
        let caseDoubleTapCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.settingsTriggerDoubleTap,
                                             target: self, action: #selector(caseDoubleTapChanged))
        caseDoubleTapCheckbox.state = SettingsManager.shared.caseDoubleTap ? .on : .off

        let hotkeyControls = settingsVerticalStack([
            settingsFormRow(L10n.settingsSwitchHotkey, control: switchPopup),
            switchRightOnlyCheckbox,
            switchDoubleTapCheckbox,
            settingsFormRow(L10n.settingsCaseHotkey, control: casePopup),
            caseRightOnlyCheckbox,
            caseDoubleTapCheckbox,
        ], spacing: 8)

        let loginCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.settingsLaunchAtLogin,
                                     target: self, action: #selector(launchAtLoginChanged))
        loginCheckbox.state = SettingsManager.shared.launchAtLogin ? .on : .off
        launchAtLoginCheckbox = loginCheckbox
        let perAppCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.settingsPerAppLayout,
                                      target: self, action: #selector(perAppLayoutChanged))
        perAppCheckbox.state = SettingsManager.shared.perAppLayout ? .on : .off

        let langPopup = GraphitePopUpButton(frame: .zero)
        populateLanguagePopup(langPopup)
        langPopup.target = self
        langPopup.action = #selector(languageChanged)
        languagePopup = langPopup

        let popup1 = GraphitePopUpButton(frame: .zero)
        populateLayoutPopup(popup1, selectedID: SettingsManager.shared.layout1ID)
        popup1.target = self
        popup1.action = #selector(layout1Changed)
        layout1Popup = popup1

        let popup2 = GraphitePopUpButton(frame: .zero)
        populateLayoutPopup(popup2, selectedID: SettingsManager.shared.layout2ID)
        popup2.target = self
        popup2.action = #selector(layout2Changed)
        layout2Popup = popup2

        let preferences = settingsVerticalStack([
            loginCheckbox,
            perAppCheckbox,
            settingsFormRow(L10n.settingsLanguage, control: langPopup),
            settingsFormRow(L10n.settingsLayout1, control: popup1),
            settingsFormRow(L10n.settingsLayout2, control: popup2),
        ], spacing: 10)

        item.view = settingsCardPage([
            settingsCard(containing: triggerControls),
            settingsCard(containing: hotkeyControls),
            settingsCard(containing: preferences),
        ])
        refreshPermissionStatus()
        return item
    }

    private func refreshPermissionStatus() {
        updatePermissionStatus(accessibility: AXIsProcessTrusted(),
                               inputMonitoring: CGPreflightListenEventAccess())
    }

    func updatePermissionStatus(accessibility: Bool, inputMonitoring: Bool) {
        let previousStatus = permissionStatusLabel?.stringValue
        if accessibility && inputMonitoring {
            permissionStatusLabel?.stringValue = L10n.settingsPermissionsReady
            permissionStatusSymbol?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: L10n.settingsPermissionsReady)
        } else {
            let missing = [
                accessibility ? nil : L10n.permissionAccessibilityName,
                inputMonitoring ? nil : L10n.permissionInputMonitoringName,
            ].compactMap { $0 }.joined(separator: ", ")
            permissionStatusLabel?.stringValue = L10n.settingsPermissionsMissing(missing)
            permissionStatusSymbol?.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: L10n.settingsPermissionsStatus)
        }
        permissionStatusSymbol?.contentTintColor = .secondaryLabelColor
        permissionStatusLabel?.superview?.layoutSubtreeIfNeeded()
        if previousStatus != permissionStatusLabel?.stringValue {
            scheduleAdaptiveDocumentLayoutUpdate()
        }
    }

    /// Re-measures wrapped preference rows after their text changes. Deferring one
    /// main-loop turn lets AppKit invalidate intrinsic text sizes before fitting the
    /// surrounding card stack.
    private func scheduleAdaptiveDocumentLayoutUpdate() {
        guard paneScrollView != nil else { return }
        adaptiveLayoutUpdateGeneration += 1
        let generation = adaptiveLayoutUpdateGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.adaptiveLayoutUpdateGeneration == generation,
                  let window = self.window,
                  window.isVisible else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            self.settingsTabView?.layoutSubtreeIfNeeded()
            self.settingsTabView?.selectedTabViewItem?.view?.layoutSubtreeIfNeeded()
            self.updateDocumentSize()
        }
    }

    @objc private func reviewPermissions() {
        onPermissionsReviewRequested?()
    }

    // MARK: - Exceptions Tab

    private func createExceptionsTab() -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = L10n.settingsTabExceptions
        buildingPageTitle = item.label

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 600))
        var y: CGFloat = 586          // y — верх следующего элемента, идём сверху вниз
        exceptionEditors.removeAll()

        // Авто-конвертация
        let autoConvert = GraphiteToggleButton(checkboxWithTitle: L10n.settingsAutoConvert, target: self, action: #selector(autoConvertChanged))
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
        let caretFlag = GraphiteToggleButton(checkboxWithTitle: L10n.settingsCaretFlag, target: self, action: #selector(caretFlagChanged))
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

        var preferenceControls: [NSView] = [autoConvert, acHint, caretFlag, cfHint]

        // Leave room for both neighboring card insets before the application lists.
        y -= 36

        // Режим удалённого стола отложен в 2.5 — блок скрыт за флагом (для тестирования).
        if SettingsManager.shared.showRemoteDesktopBeta {
            let remote = GraphiteToggleButton(checkboxWithTitle: L10n.menuRemoteDesktop, target: self, action: #selector(remoteDesktopChanged))
            remote.frame = NSRect(x: 20, y: y - 22, width: 420, height: 22)
            remote.state = SettingsManager.shared.remoteDesktopMode ? .on : .off
            view.addSubview(remote)
            remoteDesktopCheckbox = remote
            y -= 24
            let rHint = NSTextField(wrappingLabelWithString: L10n.settingsRemoteDesktopHint)
            rHint.frame = NSRect(x: 40, y: y - 44, width: 400, height: 44)
            rHint.font = SystemTypography.font(.footnote); rHint.textColor = .secondaryLabelColor
            view.addSubview(rHint)
            preferenceControls += [remote, rHint]
            y -= 52
        }

        // Секция: заголовок сверху, ниже — таблица с кнопками. Зазоры фиксированные,
        // поэтому раскладка одинаково корректна на всех языках (заголовки не переносятся).
        var sectionCards: [[NSView]] = []
        func addSection(_ title: String, hint: String, _ editor: ExceptionListEditor) {
            let header = NSTextField(labelWithString: title)
            header.frame = NSRect(x: 20, y: y - 18, width: 420, height: 18)
            header.font = SystemTypography.font(.subheadline, weight: .bold)
            header.lineBreakMode = .byTruncatingTail
            view.addSubview(header)
            let hintLabel = NSTextField(wrappingLabelWithString: hint)
            hintLabel.frame = NSRect(x: 20, y: y - 43, width: 420, height: 22)
            hintLabel.font = SystemTypography.font(.footnote)
            hintLabel.textColor = .secondaryLabelColor
            view.addSubview(hintLabel)
            let contH: CGFloat = 96
            let cont = editor.makeContainer(frame: NSRect(x: 20, y: y - 47 - contH, width: 420, height: contH))
            cont.heightAnchor.constraint(equalToConstant: contH).isActive = true
            cont.setContentCompressionResistancePriority(.required, for: .vertical)
            view.addSubview(cont)
            sectionCards.append([header, hintLabel, cont])
            exceptionEditors.append(editor)
            // Keep the purpose of both adjacent lists visible without relying on a tooltip.
            y -= (47 + contH + 28)
        }

        addSection(L10n.settingsExceptionsApps, hint: L10n.settingsExceptionsAppsHint, ExceptionListEditor(
            kind: .apps,
            get: { SettingsManager.shared.deniedApps },
            set: { SettingsManager.shared.deniedApps = $0 },
            isProtected: { AutoSwitchPolicy.protectedApps.contains($0) }))

        addSection(L10n.settingsExceptionsAllActions, hint: L10n.settingsExceptionsAllActionsHint, ExceptionListEditor(
            kind: .apps,
            get: { SettingsManager.shared.allActionsDeniedApps },
            set: { SettingsManager.shared.allActionsDeniedApps = $0 }))

        var cards = [settingsCard(containing: adaptiveControlsStack(preferenceControls))]
        cards += sectionCards.map { section in
            settingsCard(containing: adaptiveControlsStack(section))
        }
        item.view = settingsCardPage(cards)
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
        let container = editor.makeContainer(frame: NSRect(x: 36, y: 18, width: 508, height: 626))
        container.autoresizingMask = [.width, .height]
        view.addSubview(container)
        ruleEditor = editor

        addSettingsCard(to: view, around: [container], horizontalPadding: 12, verticalPadding: 12,
                        stretchesVertically: true)

        item.view = topAligned(view, fillsHeight: true, verticalInset: 12)
        return item
    }

    private func createLearningTab() -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = L10n.settingsTabLearning

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 520))
        let hint = NSTextField(wrappingLabelWithString: L10n.learningListHint)
        // Leave room for both the card's 12 pt inner padding and its 16 pt page
        // gutter. The old hint extended six points past the page and clipped the
        // rounded top edge when the tab filled a tall window.
        hint.frame = NSRect(x: 20, y: 454, width: 420, height: 38)
        hint.font = SystemTypography.font(.footnote)
        hint.textColor = .secondaryLabelColor
        view.addSubview(hint)

        let editor = LearningListEditor()
        let container = editor.makeContainer(frame: NSRect(x: 20, y: 28, width: 420, height: 418))
        view.addSubview(container)
        editor.reloadFromStore()
        learningListEditor = editor

        buildingPageTitle = item.label
        container.heightAnchor.constraint(equalToConstant: 310).isActive = true
        item.view = settingsCardPage([
            settingsCard(containing: adaptiveControlsStack([settingsHelp(hint), container]))
        ])
        return item
    }

    // MARK: - About Tab

    private func createAboutTab() -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = L10n.settingsTabAbout
        buildingPageTitle = item.label

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 450))
        var y: CGFloat = 400

        // Название и версия
        let titleLabel = NSTextField(labelWithString: "multiswitcher")
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
            let channelLabel = NSTextField(labelWithString: L10n.settingsUpdateChannel)
            channelLabel.frame = NSRect(x: 20, y: 355, width: 420, height: 20)
            channelLabel.font = SystemTypography.font(.footnote, weight: .semibold)
            view.addSubview(channelLabel)

            let channelPopup = GraphitePopUpButton(frame: NSRect(x: 20, y: 324, width: 220, height: 26),
                                             pullsDown: false)
            channelPopup.addItem(withTitle: L10n.settingsUpdateStable)
            channelPopup.lastItem?.representedObject = UpdateChannel.stable.rawValue
            channelPopup.addItem(withTitle: L10n.settingsUpdateBeta)
            channelPopup.lastItem?.representedObject = UpdateChannel.beta.rawValue
            channelPopup.selectItem(at: SettingsManager.shared.updateChannel == .beta ? 1 : 0)
            channelPopup.target = self
            channelPopup.action = #selector(updateChannelChanged(_:))
            view.addSubview(channelPopup)

            let updateCheck = GraphiteToggleButton(checkboxWithTitle: L10n.settingsCheckUpdates,
                                       target: self, action: #selector(updateChecksChanged(_:)))
            updateCheck.frame = NSRect(x: 20, y: 290, width: 420, height: 22)
            updateCheck.state = SettingsManager.shared.checkUpdatesEnabled ? .on : .off
            view.addSubview(updateCheck)

            let checkNow = GraphiteButton(title: L10n.menuCheckUpdates, target: self,
                                    action: #selector(checkForUpdatesNow(_:)))
            checkNow.frame = NSRect(x: 20, y: 250, width: 190, height: 30)
            view.addSubview(checkNow)
        }

        if CrashReporter.isAvailable {
            let crashReports = GraphiteToggleButton(checkboxWithTitle: L10n.settingsCrashReports,
                                        target: self, action: #selector(crashReportsChanged(_:)))
            crashReports.frame = NSRect(x: 20, y: 211, width: 420, height: 22)
            crashReports.state = CrashReporter.isEnabled ? .on : .off
            view.addSubview(crashReports)

            let crashReportsHint = NSTextField(wrappingLabelWithString: L10n.settingsCrashReportsHint)
            crashReportsHint.frame = NSRect(x: 20, y: 161, width: 420, height: 48)
            crashReportsHint.font = SystemTypography.font(.footnote)
            crashReportsHint.textColor = .secondaryLabelColor
            view.addSubview(crashReportsHint)
        } else {
            let unavailable = NSTextField(wrappingLabelWithString: L10n.settingsCrashReportsUnavailable)
            unavailable.frame = NSRect(x: 20, y: 190, width: 420, height: 38)
            unavailable.font = SystemTypography.font(.footnote)
            unavailable.textColor = .secondaryLabelColor
            view.addSubview(unavailable)
        }

        let localNotice = NSTextField(wrappingLabelWithString: L10n.settingsAboutLocalNotice)
        localNotice.frame = NSRect(x: 20, y: 99, width: 420, height: 54)
        localNotice.font = SystemTypography.font(.footnote)
        localNotice.textColor = .secondaryLabelColor
        view.addSubview(localNotice)

        if ProfileStore.shared.isInRecoveryMode {
            let recoveryNote = NSTextField(wrappingLabelWithString: L10n.profileRecoveryNotice)
            recoveryNote.frame = NSRect(x: 20, y: 38, width: 420, height: 52)
            recoveryNote.font = SystemTypography.font(.footnote)
            recoveryNote.textColor = .labelColor
            view.addSubview(recoveryNote)
            profileRecoveryNoteLabel = recoveryNote

            let restore = GraphiteButton(title: L10n.profileRecoveryRestore,
                                   target: self, action: #selector(restorePreviousProfile))
            restore.frame = NSRect(x: 20, y: 5, width: 240, height: 30)
            restore.isEnabled = ProfileStore.shared.canRestorePreviousProfile
            restore.setAccessibilityLabel(L10n.profileRecoveryRestore)
            view.addSubview(restore)
            restoreProfileButton = restore
        }

        let aboutControls = view.subviews
        let identity = [titleLabel, versionLabel]
        let icon = NSImageView(image: DesignIcon.application(dark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua, size: 64))
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 48), icon.heightAnchor.constraint(equalToConstant: 48)])
        let identityLabels = adaptiveControlsStack(identity)
        titleLabel.cell?.wraps = false
        titleLabel.maximumNumberOfLines = 1
        identityLabels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let identityRow = NSStackView(views: [icon, identityLabels])
        identityRow.orientation = .horizontal
        identityRow.alignment = .centerY
        identityRow.distribution = .fill
        identityRow.spacing = 12
        identityRow.translatesAutoresizingMaskIntoConstraints = false
        identityLabels.widthAnchor.constraint(equalTo: identityRow.widthAnchor, constant: -60).isActive = true
        item.view = settingsCardPage([
            settingsCard(containing: identityRow),
            settingsCard(containing: adaptiveControlsStack(aboutControls.filter { candidate in
                !identity.contains(where: { $0 === candidate })
            }))
        ])
        return item
    }

    // MARK: - Advanced Tab

    private func createAdvancedTab() -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = L10n.settingsTabAdvanced
        buildingPageTitle = item.label

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 595))
        var y: CGFloat = 545
        var conversionControls: [NSView] = []
        var dictionaryControls: [NSView] = []
        var behaviorControls: [NSView] = []

        let conversionModeTitle = NSTextField(labelWithString: L10n.settingsConversionMode)
        conversionModeTitle.font = SystemTypography.font(.body, weight: .semibold)
        conversionModeTitle.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        view.addSubview(conversionModeTitle)
        conversionControls.append(conversionModeTitle)
        y -= 31

        let modePopup = GraphitePopUpButton(frame: NSRect(x: 20, y: y, width: 420, height: 28), pullsDown: false)
        modePopup.addItems(withTitles: [L10n.settingsSmartConversion,
                                       L10n.settingsConvertByText,
                                       L10n.settingsOneWayConversion])
        if SettingsManager.shared.smartConversion {
            modePopup.selectItem(at: 0)
        } else if SettingsManager.shared.convertByText {
            modePopup.selectItem(at: 1)
        } else {
            modePopup.selectItem(at: 2)
        }
        modePopup.target = self
        modePopup.action = #selector(conversionModeChanged(_:))
        modePopup.setAccessibilityLabel(L10n.settingsConversionMode)
        view.addSubview(modePopup)
        conversionControls.append(modePopup)
        y -= 34

        let modeHint = NSTextField(wrappingLabelWithString: conversionModeDescription(for: modePopup.indexOfSelectedItem))
        modeHint.frame = NSRect(x: 20, y: y - 18, width: 420, height: 34)
        modeHint.font = SystemTypography.font(.footnote)
        modeHint.textColor = .secondaryLabelColor
        modeHint.maximumNumberOfLines = 0
        conversionModeHint = modeHint
        view.addSubview(modeHint)
        conversionControls.append(modeHint)
        y -= 48

        let languageSwitchTitle = NSTextField(labelWithString: L10n.settingsLanguageSwitchThreshold)
        languageSwitchTitle.font = SystemTypography.font(.body, weight: .semibold)
        languageSwitchTitle.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        view.addSubview(languageSwitchTitle)
        conversionControls.append(languageSwitchTitle)
        y -= 30

        let languageSwitchPopup = GraphitePopUpButton(frame: NSRect(x: 20, y: y, width: 420, height: 28), pullsDown: false)
        languageSwitchPopup.addItems(withTitles: [L10n.settingsLanguageSwitchAfterTwo,
                                                  L10n.settingsLanguageSwitchAfterOne])
        languageSwitchPopup.selectItem(at: SettingsManager.shared.languageSwitchWordThreshold == 1 ? 1 : 0)
        languageSwitchPopup.target = self
        languageSwitchPopup.action = #selector(languageSwitchThresholdChanged(_:))
        languageSwitchPopup.setAccessibilityLabel(L10n.settingsLanguageSwitchThreshold)
        view.addSubview(languageSwitchPopup)
        conversionControls.append(languageSwitchPopup)
        y -= 30

        let languageSwitchHint = NSTextField(wrappingLabelWithString: L10n.settingsLanguageSwitchThresholdHint)
        languageSwitchHint.frame = NSRect(x: 20, y: y - 12, width: 420, height: 34)
        languageSwitchHint.font = SystemTypography.font(.footnote)
        languageSwitchHint.textColor = .secondaryLabelColor
        languageSwitchHint.maximumNumberOfLines = 0
        view.addSubview(languageSwitchHint)
        conversionControls.append(languageSwitchHint)
        y -= 48

        // issue #24: триггер конвертирует всю строку (не только последнее слово). По умолч. ВЫКЛ.
        let wholeLineCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.settingsConvertWholeLine,
                                         target: self, action: #selector(convertWholeLineChanged))
        wholeLineCheckbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        wholeLineCheckbox.state = SettingsManager.shared.convertWholeLine ? .on : .off
        wholeLineCheckbox.toolTip = L10n.settingsConvertWholeLineHint
        view.addSubview(wholeLineCheckbox)
        conversionControls.append(wholeLineCheckbox)
        y -= 18

        let wholeLineHint = NSTextField(wrappingLabelWithString: L10n.settingsConvertWholeLineHint)
        wholeLineHint.frame = NSRect(x: 40, y: y - 18, width: 400, height: 32)
        wholeLineHint.font = SystemTypography.font(.footnote)
        wholeLineHint.textColor = .secondaryLabelColor
        view.addSubview(wholeLineHint)
        conversionControls.append(wholeLineHint)
        // Leave a modest natural gap; card layout adds more only when localization needs it.
        y -= 56

        // issue #27: показывать неактивирующую подсказку о защищённом вводе. По умолчанию ВКЛ.
        let secureNoticeCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.settingsSecureNotice,
                                            target: self, action: #selector(secureNoticeChanged))
        secureNoticeCheckbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        secureNoticeCheckbox.state = SettingsManager.shared.secureInputNoticeEnabled ? .on : .off
        view.addSubview(secureNoticeCheckbox)
        dictionaryControls.append(secureNoticeCheckbox)
        y -= 32

        let dictionaryHeading = NSTextField(labelWithString: L10n.settingsDictionaryPacks)
        dictionaryHeading.font = SystemTypography.font(.body, weight: .semibold)
        dictionaryHeading.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        view.addSubview(dictionaryHeading)
        dictionaryControls.append(dictionaryHeading)
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
            let checkbox = GraphiteToggleButton(checkboxWithTitle: title, target: self,
                                    action: #selector(dictionaryThemeChanged(_:)))
            checkbox.tag = index
            checkbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
            checkbox.state = enabledThemes.contains(themeIDs[index]) ? .on : .off
            view.addSubview(checkbox)
            dictionaryControls.append(checkbox)
            y -= 24
        }
        let dictionaryHint = NSTextField(wrappingLabelWithString: L10n.settingsDictionaryPacksHint)
        dictionaryHint.frame = NSRect(x: 40, y: y - 14, width: 400, height: 34)
        dictionaryHint.font = SystemTypography.font(.footnote)
        dictionaryHint.textColor = .secondaryLabelColor
        view.addSubview(dictionaryHint)
        dictionaryControls.append(dictionaryHint)
        // Leave an 8 pt gutter between the dictionary and behavior cards.
        y -= 52

        // Скрыть иконку из меню-бара (запрос пользователя). По умолчанию ВЫКЛ.
        // При включении — подтверждающий алерт с объяснением, как вернуть (reopen).
        let hideIconCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.settingsHideIcon,
                                        target: self, action: #selector(hideIconChanged(_:)))
        hideIconCheckbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        hideIconCheckbox.state = SettingsManager.shared.hideMenuBarIcon ? .on : .off
        view.addSubview(hideIconCheckbox)
        behaviorControls.append(hideIconCheckbox)
        y -= 18

        let hideIconHint = NSTextField(wrappingLabelWithString: L10n.settingsHideIconHint)
        hideIconHint.frame = NSRect(x: 40, y: y - 18, width: 400, height: 32)
        hideIconHint.font = SystemTypography.font(.footnote)
        hideIconHint.textColor = .secondaryLabelColor
        view.addSubview(hideIconHint)
        behaviorControls.append(hideIconHint)
        // Keep diagnostics in its own card with a clear 8 pt gutter.
        y -= 56

        // Debug log
        let debugCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.settingsDebugLog, target: self, action: #selector(debugLogChanged))
        debugCheckbox.frame = NSRect(x: 20, y: y, width: 420, height: 22)
        debugCheckbox.state = SettingsManager.shared.debugLogEnabled ? .on : .off
        view.addSubview(debugCheckbox)
        debugLogCheckbox = debugCheckbox
        y -= 35

        // Показать лог
        let showLogBtn = GraphiteButton(title: L10n.settingsShowLog, target: self, action: #selector(showLogFile))
        showLogBtn.frame = NSRect(x: 20, y: y, width: 180, height: 32)
        showLogBtn.bezelStyle = .rounded
        view.addSubview(showLogBtn)

        // Отправить лог
        let sendLogBtn = GraphiteButton(title: L10n.settingsSendLog, target: self, action: #selector(sendLogFile))
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
        let quitBtn = GraphiteButton(title: L10n.settingsQuit, target: self, action: #selector(quitApp))
        quitBtn.frame = NSRect(x: 20, y: y, width: 200, height: 32)
        quitBtn.bezelStyle = .rounded
        view.addSubview(quitBtn)

        let diagnosticsButtons = adaptiveButtonRow([showLogBtn, sendLogBtn])
        let debugHint = NSTextField(wrappingLabelWithString: L10n.settingsDebugLogHint)
        debugHint.frame = NSRect(x: 40, y: y, width: 400, height: 34)
        debugHint.font = SystemTypography.font(.footnote)
        debugHint.textColor = .secondaryLabelColor
        debugHint.maximumNumberOfLines = 0
        view.addSubview(debugHint)

        let diagnostics = [debugCheckbox, debugHint, diagnosticsButtons, pathLabel, quitBtn] as [NSView]
        item.view = settingsCardPage([
            settingsCard(containing: adaptiveControlsStack(conversionControls)),
            makeAutomaticExamplePreviewCard(),
            settingsCard(containing: adaptiveControlsStack(dictionaryControls)),
            settingsCard(containing: adaptiveControlsStack(behaviorControls)),
            settingsCard(containing: adaptiveControlsStack(diagnostics)),
        ])
        return item
    }

    /// A local, non-persistent preview of the automatic word path. It deliberately
    /// calls LayoutDetector rather than the separate smart-selection converter.
    private func makeAutomaticExamplePreviewCard() -> SettingsCardBackground {
        let title = NSTextField(labelWithString: L10n.settingsExampleTitle)
        title.font = SystemTypography.font(.body, weight: .semibold)

        let hint = NSTextField(wrappingLabelWithString: L10n.settingsExampleHint)
        hint.font = SystemTypography.font(.footnote)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 0

        let runtimeCaveat = NSTextField(wrappingLabelWithString: L10n.settingsExampleRuntimeCaveat)
        runtimeCaveat.font = SystemTypography.font(.caption2)
        runtimeCaveat.textColor = .tertiaryLabelColor
        runtimeCaveat.maximumNumberOfLines = 0

        let context = GraphiteTextField(string: "")
        context.placeholderString = "want вот "
        context.setAccessibilityLabel(L10n.settingsExampleContext)
        exampleContextField = context

        let word = GraphiteTextField(string: "")
        word.placeholderString = "ctqxfc"
        word.setAccessibilityLabel(L10n.settingsExampleWord)
        exampleWordField = word

        let layoutPopup = GraphitePopUpButton(frame: .zero, pullsDown: false)
        layoutPopup.setAccessibilityLabel(L10n.settingsExampleLayout)
        let choices = configuredPreviewLayouts()
        for choice in choices {
            layoutPopup.addItem(withTitle: choice.name)
            layoutPopup.lastItem?.representedObject = choice.id as NSString
        }
        let activeID = LayoutSwitcher.currentLayoutID()
        if let index = choices.firstIndex(where: { $0.id == activeID }) {
            layoutPopup.selectItem(at: index)
        } else if !choices.isEmpty {
            layoutPopup.selectItem(at: 0)
        }
        layoutPopup.isEnabled = choices.count == 2
        exampleLayoutPopup = layoutPopup

        let checkButton = GraphiteButton(title: L10n.settingsExampleCheck,
                                   target: self, action: #selector(checkAutomaticExample(_:)))
        checkButton.bezelStyle = .rounded

        let corrected = NSTextField(wrappingLabelWithString: "")
        corrected.font = SystemTypography.font(.footnote, weight: .medium)
        corrected.textColor = .labelColor
        corrected.maximumNumberOfLines = 0
        corrected.isHidden = true
        exampleCorrectedLabel = corrected

        let nextLayout = NSTextField(wrappingLabelWithString: "")
        nextLayout.font = SystemTypography.font(.footnote, weight: .medium)
        nextLayout.textColor = .labelColor
        nextLayout.maximumNumberOfLines = 0
        nextLayout.isHidden = true
        exampleNextLayoutLabel = nextLayout

        let reason = NSTextField(wrappingLabelWithString: choices.count == 2 ? "" : L10n.settingsExampleNoPair)
        reason.font = SystemTypography.font(.footnote)
        reason.textColor = .secondaryLabelColor
        reason.maximumNumberOfLines = 0
        reason.isHidden = choices.count == 2
        exampleReasonLabel = reason

        let contextRow = settingsFormRow(L10n.settingsExampleContext, control: context)
        let wordRow = settingsFormRow(L10n.settingsExampleWord, control: word)
        let layoutRow = settingsFormRow(L10n.settingsExampleLayout, control: layoutPopup)
        let content = settingsVerticalStack([
            title, contextRow, wordRow, layoutRow, checkButton,
            corrected, nextLayout, reason,
            settingsHelp(settingsVerticalStack([hint, runtimeCaveat], spacing: SettingsCardMetrics.controlSpacing)),
        ], spacing: SettingsCardMetrics.controlSpacing)
        checkButton.isEnabled = choices.count == 2
        return settingsCard(containing: content)
    }

    private func configuredPreviewLayouts() -> [PreviewLayoutChoice] {
        let sources = LayoutSwitcher.installedLayouts()
        let settings = SettingsManager.shared
        let firstID = settings.layout1ID.isEmpty
            ? LayoutSwitcher.autoDetectID1(from: sources) : settings.layout1ID
        let secondID = settings.layout2ID.isEmpty
            ? LayoutSwitcher.autoDetectID2(from: sources) : settings.layout2ID
        guard !firstID.isEmpty, !secondID.isEmpty, firstID != secondID else { return [] }
        return [firstID, secondID].compactMap { id in
            guard let source = sources.first(where: { LayoutSwitcher.sourceID($0) == id }),
                  let language = LayoutSwitcher.languageCode(source) else { return nil }
            return PreviewLayoutChoice(id: id, name: LayoutSwitcher.sourceName(source), language: language)
        }
    }

    @objc private func hideIconChanged(_ sender: NSButton) {
        let hide = sender.state == .on
        if hide {
            // Подтверждение с рецептом возврата — снимает страх «а как я его потом найду».
            let alert = GraphiteAlert()
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
        popup.addItem(withTitle: L10n.settingsLanguageAuto)
        popup.menu?.items.last?.representedObject = "" as NSString

        for lang in L10n.languageNames {
            popup.addItem(withTitle: InterfaceText.chrome(lang.name))
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
        let enabled = sender.state == .on
        SettingsManager.shared.checkUpdatesEnabled = enabled
        UpdateChecker.automaticChecksDidChange(enabled)
    }

    @objc private func updateChannelChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let channel = UpdateChannel(rawValue: rawValue) else { return }
        SettingsManager.shared.updateChannel = channel
        UpdateChecker.channelDidChange()
    }

    @objc private func crashReportsChanged(_ sender: NSButton) {
        CrashReporter.setConsent(sender.state == .on)
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
            let alert = GraphiteAlert()
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

    private func conversionModeDescription(for index: Int) -> String {
        switch index {
        case 0: return L10n.settingsSmartConversionHint
        case 1: return L10n.settingsConvertByTextHint
        default: return L10n.settingsOneWayConversionHint
        }
    }

    @objc private func conversionModeChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 0:
            SettingsManager.shared.smartConversion = true
        case 1:
            SettingsManager.shared.convertByText = true
        default:
            SettingsManager.shared.smartConversion = false
            SettingsManager.shared.convertByText = false
        }
        conversionModeHint?.stringValue = conversionModeDescription(for: sender.indexOfSelectedItem)
    }

    @objc private func languageSwitchThresholdChanged(_ sender: NSPopUpButton) {
        SettingsManager.shared.languageSwitchWordThreshold = sender.indexOfSelectedItem == 1 ? 1 : 2
    }

    @objc private func checkAutomaticExample(_ sender: NSButton) {
        guard let wordField = exampleWordField,
              let contextField = exampleContextField,
              let layoutPopup = exampleLayoutPopup else { return }

        let typed = wordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            showAutomaticExampleResult(text: "", layout: "", reason: L10n.settingsExampleEnterWord)
            return
        }
        guard !typed.contains(where: \.isWhitespace) else {
            showAutomaticExampleResult(text: typed,
                                       layout: selectedPreviewLayoutName(in: layoutPopup) ?? "",
                                       reason: L10n.settingsExampleOneWordOnly)
            return
        }
        let punctuation = LayoutDetector.splitTrailingPunctuation(typed)
        let typedCharacters = Array(typed)
        let token = String(typedCharacters.prefix(punctuation.coreLength))
        let suffix = punctuation.suffix
        guard !token.isEmpty else {
            showAutomaticExampleResult(text: typed,
                                       layout: selectedPreviewLayoutName(in: layoutPopup) ?? "",
                                       reason: L10n.settingsExampleOneWordOnly)
            return
        }

        let choices = configuredPreviewLayouts()
        guard choices.count == 2,
              let sourceID = layoutPopup.selectedItem?.representedObject as? String,
              let sourceIndex = choices.firstIndex(where: { $0.id == sourceID }) else {
            showAutomaticExampleResult(text: typed, layout: "", reason: L10n.settingsExampleNoPair)
            return
        }
        let source = choices[sourceIndex]
        let target = choices[1 - sourceIndex]
        let currentLanguage = String(source.language.prefix(2)).lowercased()
        let targetLanguage = String(target.language.prefix(2)).lowercased()
        let converted = DynamicKeyMapping.convertBidirectional(token)
        let settings = SettingsManager.shared

        var corrected = token
        var changesLayout = false
        var hasMixedCandidate = false
        var reason = L10n.settingsExampleReasonUncertain
        let initialRule = settings.automaticRuleDecision(typed: token, converted: converted)

        switch initialRule {
        case .neverConvert:
            reason = L10n.settingsExampleReasonException
        case .alwaysConvert:
            corrected = converted
            changesLayout = true
            reason = L10n.settingsExampleReasonForced
        case .replace(let replacement):
            corrected = replacement
            reason = L10n.settingsExampleReasonReplacement
        case .none:
            let mixedCandidate: LayoutCorrectionEngine.Candidate?
            if LayoutCorrectionEngine.isMixedScript(token),
               Dict.isAvailable(currentLanguage), Dict.isAvailable(targetLanguage),
               let currentCandidate = DynamicKeyMapping.convertMixedScript(token, towardLang: currentLanguage),
               let targetCandidate = DynamicKeyMapping.convertMixedScript(token, towardLang: targetLanguage) {
                mixedCandidate = LayoutCorrectionEngine.uniqueMixedCandidate(
                    typed: token,
                    currentLanguage: currentLanguage,
                    oppositeLanguage: targetLanguage,
                    currentCandidate: currentCandidate,
                    oppositeCandidate: targetCandidate,
                    isValidWord: { candidate, language in
                        let letters = candidate.filter(\.isLetter).lowercased()
                        return letters.count >= 2 && Dict.isValidWordForAutomaticPath(letters, lang: language)
                    }
                )
            } else {
                mixedCandidate = nil
            }

            if let mixedCandidate {
                hasMixedCandidate = true
                let mixedRule = settings.automaticRuleDecision(typed: token, converted: mixedCandidate.text)
                switch mixedRule {
                case .neverConvert:
                    reason = L10n.settingsExampleReasonException
                case .replace(let replacement):
                    corrected = replacement
                    reason = L10n.settingsExampleReasonReplacement
                case .alwaysConvert, .none:
                    corrected = mixedCandidate.text
                    changesLayout = mixedCandidate.changesLayout
                    reason = mixedCandidate.changesLayout
                        ? L10n.settingsExampleReasonConverted
                        : L10n.settingsExampleReasonValidSource
                }
            } else {
                let verdict = LayoutDetector.decide(
                    typed: token,
                    converted: converted,
                    currentLang: currentLanguage,
                    otherLang: targetLanguage,
                    capsLock: false,
                    rulesAlreadyEvaluated: true,
                    logDiagnostics: false
                )
                switch verdict {
                case .switchToConverted:
                    corrected = converted
                    changesLayout = true
                    reason = L10n.settingsExampleReasonConverted
                case .keep:
                    if Dict.isAvailable(currentLanguage),
                       Dict.isValidWordForAutomaticPath(typed.lowercased(), lang: currentLanguage) {
                        reason = L10n.settingsExampleReasonValidSource
                    } else {
                        reason = L10n.settingsExampleReasonCandidateRejected
                    }
                case .undecided:
                    reason = Dict.isAvailable(targetLanguage)
                        ? L10n.settingsExampleReasonUncertain
                        : L10n.settingsExampleReasonDictionaryUnavailable
                }
            }
        }

        if !suffix.isEmpty, !hasMixedCandidate, !LayoutDetector.isHebrew(targetLanguage),
           Dict.isAvailable(targetLanguage) {
            let fullConverted = DynamicKeyMapping.convertBidirectional(typed)
            let convertedCharacters = Array(fullConverted)
            var suffixCandidate = String(convertedCharacters.prefix(punctuation.coreLength))
            for character in convertedCharacters.dropFirst(punctuation.coreLength) {
                guard character.isLetter else { break }
                suffixCandidate.append(character)
                if Dict.isValidWordForAutomaticPath(suffixCandidate.lowercased(), lang: targetLanguage) {
                    corrected = token
                    changesLayout = false
                    reason = L10n.settingsExampleReasonAmbiguousPunctuation
                    break
                }
            }
        }

        let context = String(contextField.stringValue.suffix(256))
        if changesLayout {
            let targetIsConfirmed = LayoutCorrectionEngine.canonicalTrustedTerm(for: corrected) != nil
                || Dict.isValidWordForAutomaticPath(corrected.lowercased(), lang: targetLanguage)
            if LayoutCorrectionEngine.shouldPreserveInputLanguageForContextualWord(
                corrected: corrected,
                prefix: context,
                currentLanguage: currentLanguage,
                targetLanguage: targetLanguage,
                targetIsConfirmedWord: targetIsConfirmed,
                requiredConsecutiveTargetWords: settings.languageSwitchWordThreshold,
                isKnownTargetWord: { word, language in
                    LayoutCorrectionEngine.canonicalTrustedTerm(for: word) != nil
                        || Dict.isValidWordForAutomaticPath(word.lowercased(), lang: language)
                }
            ) {
                changesLayout = false
                reason = L10n.settingsExampleReasonContext
            }
        }

        let automaticEnabled = settings.autoSwitchEnabled && settings.autoConvert
        let resultingLayout = changesLayout && automaticEnabled ? target.name : source.name
        if !automaticEnabled {
            reason += " " + L10n.settingsExampleReasonDisabled
        }
        showAutomaticExampleResult(text: corrected + suffix, layout: resultingLayout, reason: reason)
    }

    private func selectedPreviewLayoutName(in popup: NSPopUpButton) -> String? {
        guard let id = popup.selectedItem?.representedObject as? String else { return nil }
        return configuredPreviewLayouts().first(where: { $0.id == id })?.name
    }

    private func showAutomaticExampleResult(text: String, layout: String, reason: String) {
        exampleCorrectedLabel?.stringValue = L10n.settingsExampleCorrected(text)
        exampleNextLayoutLabel?.stringValue = L10n.settingsExampleNextLayout(layout)
        exampleReasonLabel?.stringValue = L10n.settingsExampleReason(reason)
        exampleCorrectedLabel?.isHidden = false
        exampleNextLayoutLabel?.isHidden = false
        exampleReasonLabel?.isHidden = false
        scheduleAdaptiveDocumentLayoutUpdate()
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
            let alert = GraphiteAlert()
            alert.messageText = "log file not found"
            alert.informativeText = "enable debug logging first."
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
        preview.isEditable = true
        preview.isSelectable = true
        preview.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        preview.textContainer?.widthTracksTextView = true
        preview.isVerticallyResizable = true
        preview.isHorizontallyResizable = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 260))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = preview

        let alert = GraphiteAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.supportReportPreviewTitle
        alert.informativeText = L10n.supportReportPreviewBody
        alert.accessoryView = scroll
        alert.addButton(withTitle: L10n.supportReportShare)
        alert.addButton(withTitle: L10n.commonCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let issueURL = URL(string: "https://github.com/SokolovMO/MultiSwitcher/issues/new?template=bug_report.yml")!
        guard NSWorkspace.shared.open(issueURL) else {
            let unavailable = GraphiteAlert()
            unavailable.alertStyle = .informational
            unavailable.messageText = L10n.supportReportUnavailable
            unavailable.addButton(withTitle: L10n.commonOkay)
            unavailable.runModal()
            return
        }

        // Share only after explicit confirmation. Re-redact edits made in the preview.
        let finalReport = DiagnosticLogRedactor.redact(preview.string, homeDirectory: NSHomeDirectory())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(finalReport, forType: .string)
        let copied = GraphiteAlert()
        copied.alertStyle = .informational
        copied.messageText = L10n.supportReportCopied
        copied.addButton(withTitle: L10n.commonOkay)
        copied.runModal()
    }

    private func logFilePath() -> String {
        let logDir = NSHomeDirectory() + "/Library/Logs/MultiSwitcher"
        return logDir + "/multiswitcher.log"
    }
}

// Explicit, read-only visual review mode: no keyboard monitor, updater or permission wizard.
// Captures live AppKit windows; never substitutes a drawn design mockup.
extension SettingsWindowController {
    func captureReview(to directory: String, completion: @escaping @MainActor () -> Void) {
        if ProcessInfo.processInfo.environment["MULTI_POPOVER_ONLY"] == "1" { completion(); return }
        guard ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] != nil else {
            captureLegacyReview(to: directory, completion: completion); return
        }
        showWindow()
        guard let window else { completion(); return }
        if let phase = ProcessInfo.processInfo.environment["MULTI_WINDOW_RESTORE_CHECK"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MultiEcosystemProbe.checkRelaunch(window: window, directory: directory, phase: phase, ideal: MultiInterfaceMetrics.switcherDefault)
            }
            return
        }
        MultiEcosystemProbe.run(window: window, app: "multiswitcher", directory: directory,
            normal: MultiInterfaceMetrics.switcherDefault, minimum: MultiInterfaceMetrics.switcherMinimum,
            theme: { mode in
                if let picker = self.themePopup { picker.selectItem(at: mode == "dark" ? 2 : 1); self.appearanceChanged(picker) }
            }, completion: {
                self.captureWindowBehaviour(to: directory)
                self.captureLegacyReview(to: directory, completion: completion)
            })
    }

    private func captureWindowBehaviour(to directory: String) {
        guard let window else { return }
        let before = window.frame
        let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        window.setFrame(MultiWindowPolicy.zoomFrame(window, ideal: window.contentMaxSize), display: true)
        MultiEcosystemProbe.capture(window, path: directory + "/maximum-window.png")
        let maximumFits = screen.insetBy(dx: -1, dy: -1).contains(window.frame)
        window.setFrame(before, display: true)
        window.zoom(nil)
        let zoomFits = screen.insetBy(dx: -1, dy: -1).contains(window.frame)
        MultiEcosystemProbe.capture(window, path: directory + "/zoom-window.png")
        window.zoom(nil)
        let zoomRestores = abs(window.frame.width - before.width) < 1 && abs(window.frame.height - before.height) < 1
        window.setFrame(before, display: true)
        let result: [String: Any] = ["maximumFits": maximumFits, "zoomFits": zoomFits, "zoomRestores": zoomRestores,
            "autosaveEnabled": !window.frameAutosaveName.isEmpty, "fullscreenDisabled": window.collectionBehavior.contains(.fullScreenNone)]
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: directory + "/window-results.json"))
    }

    private func captureLegacyReview(to directory: String, completion: @escaping @MainActor () -> Void) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        showWindow()
        window?.setContentSize(NSSize(width: 820, height: 650))
        window?.center()
        @MainActor func step(_ number: Int) {
            guard number < 14 else { completion(); return }
            if let themePopup {
                themePopup.selectItem(at: number < 7 ? 1 : 2)
                appearanceChanged(themePopup)
            }
            transitionToPage(number % 7, animated: false)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let content = window?.contentView { DesignStyler.apply(content) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
                updateDocumentSize()
                scrollPaneToTop()
                if number % 7 == 3 {
                    let passed = ruleEditor?.exerciseForReview() ?? false
                    NSLog("UI review rules search/selection/keyboard: %@", passed ? "PASS" : "FAIL")
                }
                window?.displayIfNeeded()
                if let window {
                    let theme = number < 7 ? "light" : "dark"
                    Self.captureWindow(window, to: directory + "/\(theme)-\(number % 7).png")
                }
                @MainActor func finishPage() {
                    if number % 7 == 6 { ruleEditor?.captureDialogForReview() }
                    step(number + 1)
                }
                if let paneScrollView, let document = paneScrollView.documentView,
                   document.frame.height > paneScrollView.contentSize.height + 2,
                   let window {
                    var origin = paneScrollView.contentView.bounds.origin
                    origin.y = document.isFlipped
                        ? max(document.bounds.minY, document.bounds.maxY - paneScrollView.contentSize.height)
                        : document.bounds.minY
                    paneScrollView.contentView.scroll(to: origin)
                    paneScrollView.reflectScrolledClipView(paneScrollView.contentView)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
                        window.displayIfNeeded()
                        let theme = number < 7 ? "light" : "dark"
                        Self.captureWindow(window, to: directory + "/\(theme)-\(number % 7)-bottom.png")
                        scrollPaneToTop()
                        finishPage()
                    }
                } else {
                    finishPage()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { step(0) }
    }
    static func captureScreenRegion(_ rect: NSRect, to path: String) {
        let top = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        let region = "\(Int(rect.minX)),\(Int(top - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", region, path]
        do { try process.run(); process.waitUntilExit() }
        catch { NSLog("UI review menu bar capture failed") }
    }
    static func captureView(_ view: NSView, to path: String) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    static func captureWindow(_ window: NSWindow, to path: String) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        do { try process.run(); process.waitUntilExit() }
        catch { NSLog("UI review screenshot failed: %@", String(describing: error)) }
    }
}
