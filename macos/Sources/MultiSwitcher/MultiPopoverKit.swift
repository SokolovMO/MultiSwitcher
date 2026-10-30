import AppKit
#if canImport(MultiSwitcherCore)
import MultiSwitcherCore
#endif
import QuartzCore

/// Identically vendored presentation for both menu-bar utilities.
struct MultiPopoverItem {
    var title: String
    var detail = ""
    var symbol = "circle"
    var shortcut = ""
    var enabled = true
    var selected = false
    var separator = false
    var fileName = false
    var id = ""
    var action: (() -> Void)?
    var identity: String { id.isEmpty ? title : id }
    var presentation: String { [title, detail, symbol, shortcut, String(enabled), String(selected), String(separator), String(fileName)].joined(separator: "\u{1f}") }
    static var divider: Self { Self(title: "", separator: true) }
}

@MainActor final class MultiPopoverRow: NSButton {
    private(set) var item: MultiPopoverItem
    var invoke: (() -> Void)?
    var navigate: ((Int) -> Void)?
    private var hovering = false
    private var tracking: NSTrackingArea?
    private let mainFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private let detailFont = NSFont.systemFont(ofSize: 10)
    init(_ item: MultiPopoverItem) {
        self.item = item
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryPushIn); target = self; action = #selector(activate)
        focusRingType = .none
        update(item)
    }
    func update(_ item: MultiPopoverItem) {
        self.item = item; invoke = item.action
        title = item.title; isEnabled = item.enabled
        toolTip = [item.title, item.detail].filter { !$0.isEmpty }.joined(separator: "\n")
        setAccessibilityLabel(toolTip); setAccessibilityValue(item.selected ? "✓" : "")
        keyEquivalent = item.shortcut
        keyEquivalentModifierMask = item.shortcut.isEmpty ? [] : .command
        needsDisplay = true
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: height(for: 312)) }
    private func measure(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping
        return ceil((text as NSString).boundingRect(with: NSSize(width: width, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: p]).height)
    }
    func height(for width: CGFloat) -> CGFloat {
        let textWidth = max(40, width - 35)
        let primary = measure(item.title, font: mainFont, width: textWidth)
        let secondary = item.fileName && !item.detail.isEmpty ? 13 : measure(item.detail, font: detailFont, width: textWidth)
        return max(31, primary + (secondary > 0 ? secondary + 2 : 0) + 12)
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area); tracking = area; super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    @objc private func activate() { invoke?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { performClick(nil); return }
        if event.keyCode == 125 { navigate?(1); return }
        if event.keyCode == 126 { navigate?(-1); return }
        super.keyDown(with: event)
    }
    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted || item.selected {
            MultiDesign.selected.withAlphaComponent(isEnabled ? 0.8 : 0.35).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1), xRadius: MultiInterfaceMetrics.Radius.sm, yRadius: MultiInterfaceMetrics.Radius.sm).fill()
        }
        let ink = isEnabled ? MultiDesign.ink : MultiDesign.secondary
        let rect = NSRect(x: 6, y: bounds.midY - 8, width: 16, height: 16)
        NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [ink]))?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 0.85 : 0.4, respectFlipped: true, hints: nil)
        let textWidth = max(40, bounds.width - 35)
        let primary = measure(item.title, font: mainFont, width: textWidth)
        let secondary: CGFloat = item.detail.isEmpty ? 0 : item.fileName ? 13 : measure(item.detail, font: detailFont, width: textWidth)
        let top = (bounds.height - primary - (secondary > 0 ? secondary + 2 : 0)) / 2
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
        (item.title as NSString).draw(in: NSRect(x: 29, y: top, width: textWidth, height: primary), withAttributes: [.font: mainFont, .foregroundColor: ink, .paragraphStyle: style])
        if secondary > 0 {
            let detailStyle = NSMutableParagraphStyle(); detailStyle.lineBreakMode = item.fileName ? .byTruncatingMiddle : .byWordWrapping
            (item.detail as NSString).draw(in: NSRect(x: 29, y: top + primary + 2, width: textWidth, height: secondary), withAttributes: [.font: detailFont, .foregroundColor: MultiDesign.secondary, .paragraphStyle: detailStyle])
        }
        if window?.firstResponder === self {
            MultiDesign.ink.withAlphaComponent(0.55).setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: MultiInterfaceMetrics.Radius.sm, yRadius: MultiInterfaceMetrics.Radius.sm)
            path.lineWidth = 1.5; path.stroke()
        }
    }
}

@MainActor private final class MultiPopoverToggle: NSButton {
    var changed: (() -> Void)?
    init() { super.init(frame: .zero); setButtonType(.switch); isBordered = false; title = ""; focusRingType = .none; target = self; action = #selector(toggle) }
    required init?(coder: NSCoder) { fatalError("not supported") }
    override var acceptsFirstResponder: Bool { true }
    @objc private func toggle() { changed?(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: bounds.midX - 15, y: bounds.midY - 8, width: 30, height: 16)
        (state == .on ? MultiDesign.ink : MultiDesign.secondary.withAlphaComponent(0.5)).setFill()
        NSBezierPath(roundedRect: track, xRadius: 8, yRadius: 8).fill()
        let thumb = state == .on ? MultiDesign.canvas : NSColor.white
        thumb.setFill(); NSBezierPath(ovalIn: NSRect(x: state == .on ? track.maxX - 14 : track.minX + 2, y: track.minY + 2, width: 12, height: 12)).fill()
        if window?.firstResponder === self { MultiDesign.ink.setStroke(); let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6); p.lineWidth = 1; p.stroke() }
    }
}

@MainActor private final class MultiPopoverHeader: NSView {
    let icon = NSImageView()
    let name = NSTextField(labelWithString: "")
    let status = NSTextField(labelWithString: "")
    let toggle = MultiPopoverToggle()
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        status.font = .systemFont(ofSize: 10); status.textColor = MultiDesign.secondary
        [icon, name, status, toggle].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        icon.frame = NSRect(x: 0, y: 6, width: 34, height: 34)
        name.frame = NSRect(x: 42, y: 7, width: max(0, bounds.width - 84), height: 17)
        status.frame = NSRect(x: 42, y: 25, width: max(0, bounds.width - 84), height: 14)
        toggle.frame = NSRect(x: bounds.width - 34, y: 8, width: 34, height: 30)
    }
}
@MainActor private final class MultiPopoverDocument: NSView { override var isFlipped: Bool { true } }

/// Common measured page. The header is stable across navigation; only the body fades.
@MainActor final class MultiPopoverView: NSView {
    private let header = MultiPopoverHeader(frame: .zero)
    private let scroll = NSScrollView()
    private let document = MultiPopoverDocument()
    private let footer = MultiPopoverDocument()
    private let line = NSBox()
    private var resizeTimer: Timer?
    private var targetHeight: CGFloat = 0
    private var bodySignature: [String] = []
    private var footerSignature: [String] = []
    private var footerHeight: CGFloat = 0
    private var lastSize: NSSize = .zero
    var reduceMotionOverride = false
    var isResizing: Bool { resizeTimer != nil }
    private(set) var bodyHeight: CGFloat = 0
    private(set) var rowViews: [MultiPopoverRow] = []
    private var bodyRows: [NSView] = []
    private var footerRows: [NSView] = []
    private var preferredBodyMaximum: CGFloat = 360
    var onSize: ((NSSize) -> Void)?
    var onEscape: (() -> Void)?
    override var isFlipped: Bool { true }
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 300))
        wantsLayer = true
        scroll.borderType = .noBorder; scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.documentView = document
        line.boxType = .separator
        [header, scroll, line, footer].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    override func draw(_ dirtyRect: NSRect) { MultiDesign.canvas.setFill(); bounds.fill() }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    func configure(name: String, status: String, icon: NSImage, enabled: Bool, toggle: @escaping () -> Void) {
        header.name.stringValue = name; header.status.stringValue = status; header.icon.image = icon
        header.toggle.state = enabled ? .on : .off; header.toggle.setAccessibilityLabel(name)
        header.toggle.changed = toggle; needsDisplay = true
    }
    func setItems(_ items: [MultiPopoverItem], footer footerItems: [MultiPopoverItem], animated: Bool = false,
                  minimumBodyHeight: CGFloat = 0, maximumBodyHeight: CGFloat = 360) {
        let animate = animated && !MultiMotion.keyboard && !reduceMotionOverride && !MultiMotion.reduced && window?.isVisible == true
        let focused = window?.firstResponder as? MultiPopoverRow
        let previousOffset = scroll.contentView.bounds.origin
        let nextBody = items.map { $0.identity + $0.presentation }
        let nextFooter = footerItems.map { $0.identity + $0.presentation }
        let changed = nextBody != bodySignature || nextFooter != footerSignature
        func reconcile(_ items: [MultiPopoverItem], old: [NSView], parent: NSView) -> [NSView] {
            var pool: [String: [MultiPopoverRow]] = [:]
            for row in old.compactMap({ $0 as? MultiPopoverRow }) { pool[row.item.identity, default: []].append(row) }
            let rows: [NSView] = items.map { item in
                if item.separator { let line = NSBox(); line.boxType = .separator; return line }
                let row: MultiPopoverRow
                if let first = pool[item.identity]?.first {
                    row = first; pool[item.identity]?.removeFirst(); row.update(item)
                } else { row = MultiPopoverRow(item) }
                return row
            }
            for view in old where !rows.contains(where: { $0 === view }) { view.removeFromSuperview() }
            for view in rows where view.superview !== parent { parent.addSubview(view) }
            return rows
        }
        bodyRows = reconcile(items, old: bodyRows, parent: document)
        footerRows = reconcile(footerItems, old: footerRows, parent: footer)
        rowViews = (bodyRows + footerRows).compactMap { $0 as? MultiPopoverRow }
        bodySignature = nextBody; footerSignature = nextFooter
        let inner = MultiDesign.popoverWidth - 28
        func position(_ rows: [NSView], in view: NSView) -> CGFloat {
            var y: CGFloat = 0
            for row in rows {
                let height = (row as? MultiPopoverRow)?.height(for: inner) ?? 9
                row.frame = NSRect(x: 0, y: y + (row is NSBox ? 4 : 0), width: inner, height: row is NSBox ? 1 : height)
                y += height + 4
            }
            let height = max(0, y - 4); view.setFrameSize(NSSize(width: inner, height: height)); return height
        }
        let total = position(bodyRows, in: document)
        footerHeight = position(footerRows, in: footer)
        let screenMaximum = max(80, ((window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 760) - 190 - footerHeight)
        let nextHeight = min(max(total, minimumBodyHeight), min(maximumBodyHeight, screenMaximum))
        if nextHeight != targetHeight || resizeTimer == nil {
            resizeTimer?.invalidate(); resizeTimer = nil
            targetHeight = nextHeight
            if animate && abs(nextHeight - bodyHeight) > 0.5 {
                let start = bodyHeight, startTime = ProcessInfo.processInfo.systemUptime
                let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
                    guard let self else { timer.invalidate(); return }
                    MainActor.assumeIsolated {
                        let t = min(1, (ProcessInfo.processInfo.systemUptime - startTime) / MultiInterfaceMetrics.popoverResizeDuration)
                        let phase = 1 - pow(1 - t, 3)
                        self.layoutPage(height: start + (self.targetHeight - start) * phase)
                        if t >= 1 { self.resizeTimer?.invalidate(); self.resizeTimer = nil }
                    }
                }
                resizeTimer = timer; RunLoop.main.add(timer, forMode: .common)
            } else { layoutPage(height: nextHeight) }
        }
        // Existing rows remain alive; unrelated model updates neither reset scroll nor cancel motion.
        let offset = NSPoint(x: 0, y: min(previousOffset.y, max(0, total - bodyHeight)))
        scroll.contentView.scroll(to: offset); scroll.reflectScrolledClipView(scroll.contentView)
        for row in rowViews {
            row.navigate = { [weak self, weak row] delta in
                guard let self, let row, let index = self.rowViews.firstIndex(where: { $0 === row }) else { return }
                let candidates = delta > 0 ? Array(self.rowViews.dropFirst(index + 1)) : Array(self.rowViews.prefix(index).reversed())
                if let next = candidates.first(where: \.isEnabled) { self.window?.makeFirstResponder(next) }
            }
        }
        if let focused, rowViews.contains(where: { $0 === focused }) { window?.makeFirstResponder(focused) }
        else if focused != nil { window?.makeFirstResponder(rowViews.first(where: \.isEnabled)) }
        if animate && changed {
            scroll.layer?.removeAnimation(forKey: "opacity")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = scroll.layer?.presentation()?.opacity ?? 0.84; fade.toValue = 1
            fade.duration = MultiInterfaceMetrics.navigationDuration; fade.timingFunction = MultiMotion.timing
            scroll.wantsLayer = true; scroll.layer?.add(fade, forKey: "opacity")
        }
    }
    private func layoutPage(height: CGFloat) {
        bodyHeight = height
        let inner = MultiDesign.popoverWidth - 28
        header.frame = NSRect(x: 14, y: 14, width: inner, height: 46)
        scroll.frame = NSRect(x: 14, y: 70, width: inner, height: bodyHeight)
        line.frame = NSRect(x: 14, y: scroll.frame.maxY + 9, width: inner, height: 1)
        footer.frame = NSRect(x: 14, y: line.frame.maxY + 4, width: inner, height: footerHeight)
        let size = NSSize(width: MultiDesign.popoverWidth, height: footer.frame.maxY + 14)
        if window == nil { setFrameSize(size) }
        if size != lastSize { lastSize = size; onSize?(size) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { resizeTimer?.invalidate(); resizeTimer = nil }
    }
    var reviewGeometry: [String: Any] { ["width": bounds.width, "height": bounds.height, "headerTop": header.frame.minY, "iconTop": header.frame.minY + header.icon.frame.minY, "bodyTop": scroll.frame.minY, "rowCount": rowViews.count, "rowWidthsValid": rowViews.allSatisfy { abs($0.frame.width - 312) < 0.5 }] }
}
