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
    static let window = MultiDesign.canvas
    static let surface = MultiDesign.card
    static let inset = MultiDesign.inset
    static let line = MultiDesign.line
    static let ink = MultiDesign.ink
    static let secondary = MultiDesign.secondary
    static let selected = MultiDesign.selected
    static let on = MultiDesign.accent
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
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                if window is MultiBoundedWindow, let content = window.contentView { DesignStyler.apply(content) }
            }
        }
        updateIcon()
        if windowObserver == nil {
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
                guard let window = note.object as? NSWindow else { return }
                Task { @MainActor [weak window] in
                    guard let window, window is MultiBoundedWindow else { return }
                    if window is MultiBoundedWindow, let content = window.contentView { DesignStyler.apply(content) }
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
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
}

@MainActor
final class GraphitePopUpButton: MultiNativePopUpButton {
    override init(frame: NSRect, pullsDown: Bool = false) { super.init(frame: frame, pullsDown: pullsDown) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
}

@MainActor
class GraphiteTableView: NSTableView {
    var onDeleteSelection: (() -> Void)?
    override func rightMouseDown(with event: NSEvent) {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0 else { return }
        if !selectedRowIndexes.contains(index) {
            selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
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
        // System materials, alert controls and Sparkle windows retain their
        // native rendering. Never insert a tint view or recolor their bezels.
        if let button = view as? GraphiteButton {
            button.contentTintColor = nil
            button.bezelColor = nil
            button.focusRingType = .default
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
            if text.isFieldEditor { text.backgroundColor = .textBackgroundColor }
            text.selectedTextAttributes = [.backgroundColor: DesignPalette.selected, .foregroundColor: DesignPalette.ink]
        }
        if let field = view as? NSTextField {
            if field.isEditable {
                field.textColor = DesignPalette.ink
                field.backgroundColor = .textBackgroundColor
            } else if field.textColor == NSColor.secondaryLabelColor || field.textColor == NSColor.tertiaryLabelColor {
                field.textColor = DesignPalette.secondary
            }
            if let placeholder = field.placeholderString {
                field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
                    .foregroundColor: DesignPalette.secondary,
                    .font: field.font ?? .systemFont(ofSize: 12)
                ])
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
        // The native search cell keeps drawing and field-editor geometry in sync.
        // Replacing only searchTextRect left the editor at (0, 0), over the icon.
        controlSize = .regular
        font = .systemFont(ofSize: 12)
        focusRingType = .default
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 28) }
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

/// NSAlert supplies native presentation, action routing, keyboard equivalents and layout.
@MainActor
final class GraphiteAlert: NSAlert {
    override init() {
        super.init()
        // The in-app mark omits the Dock icon's baked shadow and outline.
        // Reusing that external artwork here produces a gray square halo.
        icon = MultiBrandIcon.embeddedSwitcher
    }

    // NSAlert owns its material, button cells, default action and layout.
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
