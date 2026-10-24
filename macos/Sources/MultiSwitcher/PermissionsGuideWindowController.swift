import AppKit
import QuartzCore
import MultiSwitcherCore

/// A non-modal guide: macOS owns the switches; this window explains each step
/// and observes the permissions belonging to this exact app process.
@MainActor
final class PermissionsGuideWindowController: NSWindowController, NSWindowDelegate {
    struct Status: Equatable {
        var accessibility: Bool
        var inputMonitoring: Bool
        var ready: Bool { accessibility && inputMonitoring }
    }
    private final class GuideWindow: NSWindow {
        var navigate: ((Int) -> Void)?
        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                if event.keyCode == 123 { navigate?(-1); return }
                if event.keyCode == 124 { navigate?(1); return }
            }
            super.keyDown(with: event)
        }
        override func cancelOperation(_ sender: Any?) { close() }
    }
    private final class GuideCard: NSView {
        override func draw(_ dirtyRect: NSRect) {
            DesignPalette.surface.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: MultiInterfaceMetrics.Radius.lg, yRadius: MultiInterfaceMetrics.Radius.lg).fill()
        }
        override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    }
    /// Keeps the arrow on the same side as the navigation direction and exposes
    /// selection independently of hover/highlight. No bitmap assets are involved.
    private final class GuideButton: GraphiteButton {
        override var intrinsicContentSize: NSSize {
            let width = (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 12)]).width
            return NSSize(width: ceil(width) + (image == nil ? 24 : 48), height: 32)
        }
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1), xRadius: 9, yRadius: 9)
            (isHighlighted || state == .on ? DesignPalette.selected : DesignPalette.surface).setFill(); path.fill()
            DesignPalette.line.setStroke(); path.lineWidth = 0.8; path.stroke()
            let ink = isEnabled ? DesignPalette.ink : DesignPalette.secondary
            let textFont = font ?? NSFont.systemFont(ofSize: 12, weight: .medium)
            let imageWidth: CGFloat = image == nil ? 0 : 16
            let gap: CGFloat = image == nil ? 0 : 8
            let available = max(0, bounds.width - 24 - imageWidth - gap)
            let textSize = (title as NSString).size(withAttributes: [.font: textFont])
            let textWidth = min(available, textSize.width)
            let origin = bounds.midX - (textWidth + imageWidth + gap) / 2
            let trailing = imagePosition == .imageTrailing
            let textX = origin + (trailing ? 0 : imageWidth + gap)
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            (title as NSString).draw(in: NSRect(x: textX, y: bounds.midY - textSize.height / 2,
                width: textWidth, height: textSize.height), withAttributes: [.font: textFont, .foregroundColor: ink, .paragraphStyle: paragraph])
            if let image {
                let imageX = trailing ? origin + textWidth + gap : origin
                let ratio = min(16 / max(1, image.size.width), 16 / max(1, image.size.height))
                let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
                (image.withSymbolConfiguration(.init(paletteColors: [ink])) ?? image).draw(in:
                    NSRect(x: imageX + (16 - size.width) / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.5, respectFlipped: true, hints: nil)
            }
            if window?.firstResponder === self { ink.setStroke(); path.lineWidth = 1.5; path.stroke() }
        }
    }
    private let readStatus: () -> Status
    private let openSettings: (String) -> Void
    private let onStatus: (Status) -> Void
    private let onFinish: () -> Void
    private let onRestartCheck: () -> Void
    private var repairing = false
    private var status: Status
    private(set) var step = 0
    private var pollTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var themeObserver: NSObjectProtocol?
    private let page = NSView()
    private let progress = NSStackView()
    private let back = GuideButton(title: "", target: nil, action: nil)
    private let next = GuideButton(title: "", target: nil, action: nil)
    private let trouble = GuideButton(title: "", target: nil, action: nil)
    private let liveStatus = NSTextField(wrappingLabelWithString: "")
    private var ru: Bool { L10n.languageCode == "ru" }
    private func text(_ russian: String, _ english: String) -> String { ru ? russian : english }

    init(readStatus: @escaping () -> Status, openSettings: @escaping (String) -> Void,
         onStatus: @escaping (Status) -> Void, onFinish: @escaping () -> Void, onRestartCheck: @escaping () -> Void = {}) {
        self.readStatus = readStatus; self.openSettings = openSettings
        self.onStatus = onStatus; self.onFinish = onFinish; self.onRestartCheck = onRestartCheck
        status = readStatus()
        let window = GuideWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "multiswitcher"
        window.isReleasedWhenClosed = false
        window.backgroundColor = DesignPalette.window
        window.delegate = self
        window.navigate = { [weak self] delta in self?.select((self?.step ?? 0) + delta) }
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        status = readStatus()
        repairing = false
        step = status.ready ? 2 : (status.accessibility ? 1 : 0)
        render(animated: false, direction: 1)
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        startObserving()
        onStatus(status)
    }

    private func build() {
        guard let root = window?.contentView else { return }
        let title = label(text("поможем включить автоконверсию", "let’s enable automatic conversion"), size: 21, weight: .semibold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let subtitle = label("multiswitcher \(version) (\(build)) · \(Bundle.main.bundlePath)", size: 12, secondary: true)
        progress.orientation = .horizontal; progress.distribution = .fillEqually; progress.spacing = 8
        page.wantsLayer = true
        back.target = self; back.action = #selector(goBack)
        next.target = self; next.action = #selector(goNext); next.keyEquivalent = "\r"
        back.image = symbol("arrow.left", size: 12); back.imagePosition = .imageLeading
        next.imagePosition = .imageTrailing
        liveStatus.font = .systemFont(ofSize: 12)
        liveStatus.textColor = .secondaryLabelColor
        liveStatus.maximumNumberOfLines = 0
        trouble.title = text("не видит доступ?", "access not detected?")
        trouble.target = self; trouble.action = #selector(openTroubleshooting)
        let footer = NSStackView(views: [back, NSView(), trouble, next])
        footer.orientation = .horizontal; footer.spacing = 12
        let header = NSStackView(views: [title, subtitle, progress])
        header.orientation = .vertical; header.alignment = .leading; header.spacing = 12
        for view in [header, page, liveStatus, footer] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            progress.widthAnchor.constraint(equalTo: header.widthAnchor),
            progress.heightAnchor.constraint(equalToConstant: 32),
            page.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            page.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            page.bottomAnchor.constraint(equalTo: liveStatus.topAnchor, constant: -16),
            liveStatus.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            liveStatus.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            liveStatus.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            liveStatus.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            footer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            footer.heightAnchor.constraint(equalToConstant: 32),
            back.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            next.widthAnchor.constraint(greaterThanOrEqualToConstant: 132),
        ])
    }

    private func label(_ value: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.maximumNumberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }
    private func symbol(_ name: String, size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
    }
    private func button(_ title: String, symbol name: String, action: Selector) -> GuideButton {
        let button = GuideButton(title: title, target: self, action: action)
        button.image = symbol(name, size: 13); button.imagePosition = .imageTrailing
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        return button
    }
    private func iconRow(_ name: String, _ title: String, secondary: Bool = false) -> NSView {
        let icon = NSImageView(image: symbol(name, size: 17) ?? NSImage())
        icon.contentTintColor = secondary ? .secondaryLabelColor : .labelColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let row = NSStackView(views: [icon, label(title, secondary: secondary)])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 12
        return row
    }
    private func card(_ views: [NSView]) -> NSView {
        let card = GuideCard()
        let content = NSStackView(views: views)
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        for view in views where view is NSTextField { view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        return card
    }

    private func render(animated: Bool, direction: Int) {
        if animated {
            let transition = CATransition()
            transition.type = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .fade : .push
            transition.subtype = direction > 0 ? .fromRight : .fromLeft
            transition.duration = 0.2; transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            page.layer?.add(transition, forKey: "permission-page")
        }
        for view in progress.arrangedSubviews { progress.removeArrangedSubview(view); view.removeFromSuperview() }
        let names = [text("текст", "text"), text("клавиатура", "keyboard"), text("проверка", "check")]
        for index in 0..<3 {
            let granted = index == 0 ? status.accessibility : (index == 1 ? status.inputMonitoring : status.ready)
            let b = button("\(index + 1) · \(names[index])", symbol: granted ? "checkmark.circle" : "chevron.right", action: #selector(selectStep(_:)))
            b.tag = index; b.state = index == step ? .on : .off
            b.setAccessibilityLabel(names[index] + (granted ? text(", разрешено", ", granted") : ""))
            progress.addArrangedSubview(b)
        }
        page.subviews.forEach { $0.removeFromSuperview() }
        let content: NSView
        if repairing {
            content = card([
                iconRow("arrow.triangle.2.circlepath", text("переключатель включён, но доступа нет?", "switch on, but access is missing?")),
                label(text("macos может помнить прежнюю копию приложения. попробуйте по порядку:", "macos may remember a previous copy of the app. try these steps in order:"), secondary: true),
                label(text("1. выключите доступ multiswitcher и включите снова.", "1. switch multiswitcher off, then on again.")),
                label(text("2. если не помогло: удалите старую запись кнопкой − и добавьте текущую копию из «программы» кнопкой +.", "2. if needed, remove the old entry with − and add the current app from applications with +.")),
                button(text("запросить доступ в macos", "request access in macos"), symbol: "arrow.up.right", action: #selector(openCurrentPane)),
                button(text("показать текущую копию", "show current app"), symbol: "folder", action: #selector(revealApp)),
                button(text("перезапустить для проверки", "restart to check"), symbol: "arrow.clockwise", action: #selector(restartToCheck)),
            ])
            liveStatus.stringValue = text("после перезапуска помощник откроется снова и проверит доступ.", "after restarting, this guide reopens and checks access again.")
        } else if step < 2 {
            let access = step == 0
            let granted = access ? status.accessibility : status.inputMonitoring
            let paneName = access ? L10n.permissionAccessibilityName : L10n.permissionInputMonitoringName
            let title = access ? text("разрешите заменять текст", "allow text replacement") : text("разрешите видеть нажатия клавиш", "allow keyboard events")
            let detail = access ? text("чтобы исправлять слово в активном приложении.", "to correct a word in the active app.") : text("чтобы замечать неверную раскладку во время набора.", "to detect a wrong layout while you type.")
            content = card([
                iconRow(access ? "hand.point.up.left" : "keyboard", title),
                label(detail, secondary: true),
                iconRow("gearshape", text("системные настройки", "system settings")),
                iconRow("arrow.down", text("конфиденциальность и безопасность", "privacy & security"), secondary: true),
                iconRow("arrow.turn.down.right", paneName),
                label(text("найдите multiswitcher и включите переключатель. нет в списке? добавьте приложение кнопкой +.", "find multiswitcher and turn its switch on. not listed? add the app with the + button.")),
                button(text("запросить доступ в macos", "request access in macos"), symbol: "arrow.up.right", action: #selector(openCurrentPane)),
                button(text("показать приложение в finder", "show app in finder"), symbol: "folder", action: #selector(revealApp)),
            ])
            liveStatus.stringValue = granted ? text("разрешение получено ✓ можно перейти дальше.", "permission granted ✓ you can continue.") : text("нажмите «запросить доступ», подтвердите запрос macos и вернитесь сюда.", "click “request access”, confirm the macos prompt and return here.")
        } else {
            let access = button(L10n.permissionAccessibilityName, symbol: status.accessibility ? "checkmark.circle" : "arrow.up.right", action: #selector(openAccessPane))
            let input = button(L10n.permissionInputMonitoringName, symbol: status.inputMonitoring ? "checkmark.circle" : "arrow.up.right", action: #selector(openInputPane))
            content = card([
                iconRow(status.ready ? "checkmark.seal" : "checklist", status.ready ? text("всё готово", "all set") : text("проверим разрешения", "check permissions")),
                label(status.ready ? text("оба доступа получены. включите автоконверсию и перезапустите multiswitcher.", "both permissions are granted. enable automatic conversion and restart multiswitcher.") : text("нажмите на нужный пункт, чтобы открыть его в macos.", "click a permission to open its macos settings."), secondary: true),
                access, input,
                label(text("после перезапуска наберите ghbdtn в английской раскладке и нажмите пробел → привет.", "after restarting, type ghbdtn in the english layout and press space → привет.")),
            ])
            liveStatus.stringValue = status.ready ? text("разрешения готовы. осталось включить автоконверсию.", "permissions ready. enable automatic conversion to finish.") : text("галочка появится только после разрешения macos.", "a checkmark appears only after macos grants access.")
        }
        content.translatesAutoresizingMaskIntoConstraints = false; page.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: page.leadingAnchor), content.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            content.topAnchor.constraint(equalTo: page.topAnchor), content.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor),
        ])
        trouble.isHidden = status.ready || repairing
        back.title = text("назад", "back"); back.isEnabled = step > 0 || repairing
        next.title = step < 2 ? text("далее", "next") : (status.ready ? text("включить и перезапустить", "enable & restart") : text("проверить снова", "check again"))
        if repairing { next.title = text("к шагу", "back to step") }
        next.image = symbol(step < 2 ? "arrow.right" : (status.ready ? "arrow.clockwise" : "checkmark"), size: 12)
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    func select(_ index: Int) {
        let target = min(2, max(0, index)); guard target != step else { return }
        let direction = target > step ? 1 : -1; step = target; repairing = false
        render(animated: true, direction: direction)
    }
    @objc private func selectStep(_ sender: NSButton) { select(sender.tag) }
    @objc private func goBack() {
        if repairing { repairing = false; render(animated: true, direction: -1) }
        else { select(step - 1) }
    }
    @objc private func openTroubleshooting() { showTroubleshooting() }
    func showTroubleshooting() {
        if step == 2 { step = status.accessibility ? 1 : 0 }
        repairing = true; render(animated: true, direction: 1)
    }
    @objc private func restartToCheck() { onRestartCheck() }
    @objc private func goNext() { advance() }
    func advance() {
        if repairing { repairing = false; render(animated: true, direction: -1); return }
        let previousStep = step
        refresh()
        if previousStep != step { return }
        if step < 2 { select(step + 1) }
        else if status.ready { onFinish() }
        else { liveStatus.stringValue = text("macos пока не выдала оба разрешения. откройте пункты выше и включите multiswitcher.", "macos has not granted both permissions yet. open the items above and enable multiswitcher.") }
    }
    @objc private func openCurrentPane() { openSettings(step == 0 ? "Privacy_Accessibility" : "Privacy_ListenEvent") }
    @objc private func openAccessPane() { select(0); openSettings("Privacy_Accessibility") }
    @objc private func openInputPane() { select(1); openSettings("Privacy_ListenEvent") }
    @objc private func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }

    func refresh() {
        let fresh = readStatus(); guard fresh != status else { return }
        let previous = status; status = fresh; onStatus(fresh)
        if status.ready && !previous.ready { step = 2; repairing = false }
        else if step == 0 && !previous.accessibility && status.accessibility { step = 1 }
        render(animated: true, direction: 1)
    }
    private func startObserving() {
        if themeObserver == nil {
            themeObserver = NotificationCenter.default.addObserver(forName: .multiswitcherThemeChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.render(animated: false, direction: 1) }
            }
        }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }
    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate(); pollTimer = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
        themeObserver = nil
    }
}
