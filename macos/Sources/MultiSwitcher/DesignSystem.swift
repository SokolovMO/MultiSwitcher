import AppKit
import MultiSwitcherCore
import QuartzCore

/// Shared, dependency-free visual vocabulary. User text never passes through this boundary.

@MainActor
enum DesignPalette {
    static func dynamic(_ name: String, light: CGFloat, dark: CGFloat, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: NSColor.Name("multiswitcher.\(name)")) { appearance in
            NSColor(white: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light,
                    alpha: alpha)
        }
    }
    static let window = dynamic("window", light: 0.972, dark: 0.075)
    static let surface = dynamic("surface", light: 0.995, dark: 0.105, alpha: 0.88)
    static let inset = dynamic("inset", light: 0.945, dark: 0.145)
    static let line = dynamic("line", light: 0.20, dark: 0.85, alpha: 0.12)
    static let ink = dynamic("ink", light: 0.10, dark: 0.94)
    static let secondary = dynamic("secondary", light: 0.43, dark: 0.62)
    static var selected: NSColor {
        SettingsManager.shared.monochromeControls
            ? dynamic("selected", light: 0.89, dark: 0.22)
            : NSColor.controlAccentColor.withAlphaComponent(0.20)
    }
    static var on: NSColor {
        SettingsManager.shared.monochromeControls
            ? dynamic("on", light: 0.12, dark: 0.90)
            : NSColor.controlAccentColor
    }
    static let thumb = dynamic("thumb", light: 1, dark: 0.16)
    static let off = dynamic("off", light: 0.79, dark: 0.30)
    static let radius: CGFloat = MultiInterfaceMetrics.Radius.lg
    static let controlRadius: CGFloat = MultiInterfaceMetrics.Radius.sm
    static let pageInset: CGFloat = 24
    static let spacing: CGFloat = 16
    static var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

enum InterfaceTheme: String, CaseIterable {
    case system, light, dark
    var title: String {
        let russian = L10n.languageCode == "ru"
        switch self {
        case .system: return russian ? "системная" : "system"
        case .light: return russian ? "светлая" : "light"
        case .dark: return russian ? "тёмная" : "dark"
        }
    }
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class DesignTheme {
    static let shared = DesignTheme()
    private var appearanceObservation: NSKeyValueObservation?
    private var windowObserver: NSObjectProtocol?
    var preference: InterfaceTheme {
        get { InterfaceTheme(rawValue: SettingsManager.shared.interfaceTheme) ?? .system }
        set { SettingsManager.shared.interfaceTheme = newValue.rawValue; apply() }
    }
    func apply() {
        NSApp.appearance = preference.appearance
        for window in NSApp.windows {
            window.appearance = preference.appearance
            if window.isOpaque { window.backgroundColor = DesignPalette.window }
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                if let content = window.contentView { DesignStyler.apply(content) }
            }
        }
        updateIcon()
        if windowObserver == nil {
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
                guard let window = note.object as? NSWindow else { return }
                Task { @MainActor [weak window] in
                    guard let window, !(window is NSSavePanel) else { return }
                    if let content = window.contentView { DesignStyler.apply(content) }
                }
            }
        }
        if appearanceObservation == nil {
            appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
                Task { @MainActor in DesignTheme.shared.updateIcon() }
            }
        }
        NotificationCenter.default.post(name: .multiswitcherThemeChanged, object: nil)
    }
    func updateIcon() {
        NSApp.applicationIconImage = MultiBrandIcon.switcher
    }
}
extension Notification.Name {
    static let multiswitcherThemeChanged = Notification.Name("multiswitcher.theme.changed")
}

@MainActor
enum DesignIcon {
    /// The application mark is independent of input language and appearance.
    static func application(dark: Bool, size: CGFloat = 512) -> NSImage {
        MultiBrandIcon.switcher
    }
}

/// Native AppKit owns title/image centering, focus, disabled states and hit testing.
@MainActor
class GraphiteButton: NSButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        controlSize = .regular
        alignment = .center
        font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular))
        contentTintColor = DesignPalette.ink
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
}

@MainActor
final class GraphitePopUpButton: NSPopUpButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var intrinsicContentSize: NSSize {
        NSSize(width: max(80, super.intrinsicContentSize.width), height: 28)
    }
    override func draw(_ dirtyRect: NSRect) {
        DesignPalette.inset.withAlphaComponent(0.8).setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1), xRadius: MultiInterfaceMetrics.Radius.sm, yRadius: MultiInterfaceMetrics.Radius.sm)
        path.fill(); DesignPalette.line.setStroke(); path.lineWidth = 0.7; path.stroke()
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: NSRect(x: 10, y: bounds.midY - 8, width: max(0, bounds.width - 33), height: 18),
                                withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 12),
                                                 .foregroundColor: DesignPalette.ink, .paragraphStyle: paragraph])
        NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .medium))?
            .withSymbolConfiguration(.init(paletteColors: [DesignPalette.ink]))?
            .draw(in: NSRect(x: bounds.maxX - 19, y: bounds.midY - 7, width: 10, height: 14))
        if window?.firstResponder === self {
            DesignPalette.ink.withAlphaComponent(0.45).setStroke(); path.lineWidth = 1; path.stroke()
        }
    }
}

@MainActor
class GraphiteTableView: NSTableView {
    var onDeleteSelection: (() -> Void)?
    override func rightMouseDown(with event: NSEvent) {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0 else { return }
        selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        super.rightMouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            if !event.isARepeat { onDeleteSelection?() }
            return
        }
        super.keyDown(with: event)
    }

    private var hoveredRow = -1
    private var hoverTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        hoverTracking = tracking
        super.updateTrackingAreas()
    }
    override func mouseMoved(with event: NSEvent) {
        let next = row(at: convert(event.locationInWindow, from: nil))
        guard next != hoveredRow else { return }
        if hoveredRow >= 0, hoveredRow < numberOfRows { setNeedsDisplay(rect(ofRow: hoveredRow)) }
        hoveredRow = next
        if next >= 0 { setNeedsDisplay(rect(ofRow: next)) }
    }
    override func mouseExited(with event: NSEvent) {
        if hoveredRow >= 0, hoveredRow < numberOfRows { setNeedsDisplay(rect(ofRow: hoveredRow)) }
        hoveredRow = -1
    }
    override func drawBackground(inClipRect clipRect: NSRect) {
        super.drawBackground(inClipRect: clipRect)
        if hoveredRow >= 0, hoveredRow < numberOfRows, !selectedRowIndexes.contains(hoveredRow) {
            DesignPalette.inset.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: rect(ofRow: hoveredRow).insetBy(dx: 3, dy: 1), xRadius: MultiInterfaceMetrics.Radius.xs, yRadius: MultiInterfaceMetrics.Radius.xs).fill()
        }
        DesignPalette.selected.setFill()
        for row in selectedRowIndexes {
            let rect = rect(ofRow: row).insetBy(dx: 3, dy: 1)
            if rect.intersects(clipRect) { NSBezierPath(roundedRect: rect, xRadius: MultiInterfaceMetrics.Radius.xs, yRadius: MultiInterfaceMetrics.Radius.xs).fill() }
        }
    }
}

@MainActor
enum DesignStyler {
    static func apply(_ view: NSView) {
        // SwiftUI owns the native switch subtree. Applying AppKit bezel/tint
        // overrides to its private controls changes the system rendering style.
        if let toggle = view as? GraphiteToggleButton {
            toggle.refreshAppearance()
            return
        }
        if let visual = view as? NSVisualEffectView {
            if visual.material == .popover, !visual.subviews.contains(where: { $0 is GraphiteMaterialTint }) {
                let tint = GraphiteMaterialTint(frame: visual.bounds)
                tint.autoresizingMask = [.width, .height]
                visual.addSubview(tint, positioned: .below, relativeTo: visual.subviews.first)
            }
            visual.state = .active
            visual.blendingMode = .withinWindow
            if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                visual.material = .windowBackground
            }
        }
        if let button = view as? NSButton {
            // Titles were localized before user data was interpolated. Never case-fold
            // popup values here: input-source names and user content retain their case.
            button.contentTintColor = DesignPalette.ink
            if !(button is GraphiteButton), !(button is GraphiteToggleButton), !(button is NSPopUpButton) {
                button.bezelColor = DesignPalette.inset
            }
            if button is GraphiteButton || button is GraphiteToggleButton || button is GraphitePopUpButton {
                button.focusRingType = .default
            }
        }
        if let table = view as? NSTableView {
            table.selectionHighlightStyle = .none
            table.backgroundColor = .clear
            table.gridStyleMask = []
            table.usesAlternatingRowBackgroundColors = false
            if let header = table.headerView, !(header is GraphiteTableHeaderView) {
                table.headerView = GraphiteTableHeaderView(frame: NSRect(x: 0, y: 0, width: header.frame.width, height: 26))
            }
            table.headerView?.needsDisplay = true
            for column in table.tableColumns {
                column.title = InterfaceText.chrome(column.title)
                column.headerCell.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            }
        }
        if let scroll = view as? NSScrollView, scroll.documentView is NSTableView {
            scroll.wantsLayer = true
            scroll.layer?.cornerRadius = scroll.borderType == .noBorder ? MultiInterfaceMetrics.Radius.md : 0
            scroll.layer?.masksToBounds = scroll.borderType == .noBorder
        }
        if let text = view as? NSTextView {
            text.insertionPointColor = DesignPalette.ink
            text.selectedTextAttributes = [.backgroundColor: DesignPalette.selected, .foregroundColor: DesignPalette.ink]
        }
        if let field = view as? NSTextField {
            if field.isEditable {
                field.textColor = DesignPalette.ink
                field.backgroundColor = DesignPalette.inset
            }
        }
        view.subviews.forEach(apply)
        view.needsDisplay = true
    }
}

/// Native search semantics (clear button, responder editing, accessibility) in a quiet surface.
@MainActor
final class GraphiteSearchField: NSSearchField {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = GraphiteSearchFieldCell(textCell: "")
        isBezeled = false
        drawsBackground = false
        font = .systemFont(ofSize: 12)
        focusRingType = .none
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 28) }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: MultiInterfaceMetrics.Radius.sm, yRadius: MultiInterfaceMetrics.Radius.sm)
        DesignPalette.inset.setFill(); path.fill()
        let focused = currentEditor() != nil
        (focused ? DesignPalette.ink.withAlphaComponent(0.55) : DesignPalette.line).setStroke()
        path.lineWidth = focused ? 1.2 : 0.7
        path.stroke()
        super.draw(dirtyRect)
    }
}

/// The bar presents the existing confirmation count; it does not invent learning events.
@MainActor
final class GraphiteProgressView: NSView {
    let fraction: Double
    init(fraction: Double, description: String) {
        self.fraction = min(1, max(0, fraction))
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityLabel(description)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityValue(self.fraction)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: bounds.midY - 2, width: bounds.width, height: 4)
        DesignPalette.off.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        DesignPalette.on.setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY,
            width: track.width * fraction, height: 4), xRadius: 2, yRadius: 2).fill()
    }
}

@MainActor
final class GraphiteTableHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        DesignPalette.inset.setFill()
        bounds.fill()
        guard let tableView else { return }
        for (index, column) in tableView.tableColumns.enumerated() {
            let rect = headerRect(ofColumn: index).insetBy(dx: 8, dy: 5)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            (column.title as NSString).draw(in: rect, withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: DesignPalette.secondary, .paragraphStyle: paragraph
            ])
        }
    }
}

/// Native text editing with graphite focus and selection, preserving the entered string.
@MainActor
final class GraphiteTextField: NSTextField {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBezeled = true
        bezelStyle = .roundedBezel
        drawsBackground = true
        controlSize = .regular
        font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular))
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
}

/// Uses NSAlert's real action routing, keyboard equivalents and modal lifecycle,
/// with the same neutral controls as settings. The default cell is the only part replaced.
@MainActor
final class GraphiteAlert: NSAlert {
    override func runModal() -> NSApplication.ModalResponse {
        window.appearance = NSApp.appearance
        window.backgroundColor = DesignPalette.window
        window.isOpaque = true
        for button in buttons where !(button.cell is GraphiteAlertButtonCell) {
            let title = button.title
            let target = button.target
            let action = button.action
            let equivalent = button.keyEquivalent
            let modifiers = button.keyEquivalentModifierMask
            let enabled = button.isEnabled
            let tag = button.tag
            let cell = GraphiteAlertButtonCell(textCell: title)
            cell.font = .systemFont(ofSize: 12, weight: .medium)
            cell.keyEquivalent = equivalent
            cell.keyEquivalentModifierMask = modifiers
            button.cell = cell
            button.target = target
            button.action = action
            button.isEnabled = enabled
            button.tag = tag
            button.focusRingType = .default
            button.setAccessibilityLabel(title)
        }
        if let content = window.contentView { DesignStyler.apply(content) }
        return super.runModal()
    }
}

@MainActor
final class GraphiteAlertButtonCell: NSButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let primary = keyEquivalent == "\r"
        let rect = cellFrame.insetBy(dx: 1, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: MultiInterfaceMetrics.Radius.sm, yRadius: MultiInterfaceMetrics.Radius.sm)
        (isHighlighted ? DesignPalette.selected : (primary ? DesignPalette.on : DesignPalette.inset)).setFill()
        path.fill()
        DesignPalette.line.setStroke(); path.lineWidth = 0.7; path.stroke()
        let textFont = font ?? .systemFont(ofSize: 12, weight: .medium)
        let color = primary && !isHighlighted ? DesignPalette.thumb : DesignPalette.ink
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (title as NSString).draw(in: NSRect(x: rect.minX + 6, y: rect.midY - textFont.pointSize * 0.65,
            width: rect.width - 12, height: textFont.pointSize + 4), withAttributes: [
                .font: textFont, .foregroundColor: isEnabled ? color : DesignPalette.secondary, .paragraphStyle: style
            ])
        if controlView.window?.firstResponder === controlView {
            DesignPalette.ink.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 1.5; path.stroke()
        }
    }
}

@MainActor
final class GraphiteSearchFieldCell: NSSearchFieldCell {
    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        NSRect(x: rect.minX + 28, y: rect.midY - 8, width: max(0, rect.width - 54), height: 17)
    }
    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        NSRect(x: rect.minX + 8, y: rect.midY - 8, width: 16, height: 16)
    }
    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        NSRect(x: rect.maxX - 22, y: rect.midY - 8, width: 16, height: 16)
    }
}

/// A compact native modal for the existing rule form. AppKit owns focus, editing and keys.
@MainActor
final class GraphiteDialogPanel: NSPanel {
    private var cancelButton: GraphiteButton!
    init(title: String, message: String, accessory: NSView, confirm: String, cancel: String) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 568, height: 430),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.title = title
        collectionBehavior = [.managed, .fullScreenNone]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        appearance = NSApp.appearance
        backgroundColor = DesignPalette.window
        isReleasedWhenClosed = false
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 19, weight: .semibold)
        let hint = NSTextField(wrappingLabelWithString: message)
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = DesignPalette.secondary
        let cancelControl = GraphiteButton(title: cancel, target: self, action: #selector(finish(_:)))
        cancelControl.tag = 1001
        cancelControl.keyEquivalent = "\u{1b}"
        cancelButton = cancelControl
        let save = GraphiteButton(title: confirm, target: self, action: #selector(finish(_:)))
        save.tag = 1000
        save.keyEquivalent = "\r"
        let footer = NSStackView(views: [NSView(), cancelControl, save])
        footer.orientation = .horizontal
        footer.distribution = .fill
        footer.spacing = 8
        for button in [cancelControl, save] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 104).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }
        let stack = NSStackView(views: [heading, hint, accessory, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = contentView!
        root.addSubview(stack)
        for view in stack.arrangedSubviews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            accessory.heightAnchor.constraint(equalToConstant: 240),
            footer.heightAnchor.constraint(equalToConstant: 30)
        ])
        root.layoutSubtreeIfNeeded()
        setContentSize(NSSize(width: 568, height: max(410, ceil(stack.fittingSize.height) + 48)))
        minSize = NSSize(width: 568, height: frame.height)
        defaultButtonCell = save.cell as? NSButtonCell
        center()
        DesignStyler.apply(root)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    func runDialog() -> NSApplication.ModalResponse {
        defer { orderOut(nil) }
        return NSApp.runModal(for: self)
    }
    func cancelForReview() { cancelButton.performClick(nil) }
    @objc private func finish(_ sender: NSButton) {
        NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: sender.tag))
    }
    override func cancelOperation(_ sender: Any?) {
        NSApp.stopModal(withCode: .alertSecondButtonReturn)
    }
    override func close() {
        if NSApp.modalWindow === self { NSApp.stopModal(withCode: .alertSecondButtonReturn) }
        super.close()
    }
}

/// Limits wallpaper bleed while leaving a restrained native material underneath.
@MainActor
final class GraphiteMaterialTint: NSView {
    override func draw(_ dirtyRect: NSRect) {
        DesignPalette.window.withAlphaComponent(0.94).setFill()
        bounds.fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
