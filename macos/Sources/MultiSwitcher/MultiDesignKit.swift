import AppKit
import SwiftUI
import QuartzCore
#if canImport(MultiSwitcherCore)
import MultiSwitcherCore
#endif

/// Canonical permanent application artwork. Never reads input-source or theme state.
@MainActor enum MultiBrandIcon {
    static let switcher = render(externalEffects: true)
    static let embeddedSwitcher = render(externalEffects: false)
    private static func render(externalEffects: Bool) -> NSImage { NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
        NSColor.clear.setFill(); rect.fill(using: .copy)
        let size = rect.width
        // Keep the white rounded tile for the in-app identity, but omit its
        // shadow and outline so they cannot form a gray square at sidebar scale.
        let tile = rect.insetBy(dx: size * 0.075, dy: size * 0.075)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = size * 0.045; shadow.shadowOffset = NSSize(width: 0, height: -size * 0.015)
        let path = NSBezierPath(roundedRect: tile, xRadius: size * 0.19, yRadius: size * 0.19)
        if externalEffects { NSGraphicsContext.saveGraphicsState(); shadow.set() }
        NSColor(white: 0.985, alpha: 1).setFill(); path.fill()
        if externalEffects {
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.08).setStroke(); path.lineWidth = max(1, size / 512); path.stroke()
        }
        let markSize = size * 0.77
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: markSize * 0.68, weight: .semibold),
            .foregroundColor: NSColor(white: 0.09, alpha: 1), .kern: -markSize * 0.035]
        let text = "AЯ" as NSString; let measured = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2), withAttributes: attributes)
        return true
    } }
}

@MainActor enum MultiMotion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var keyboard: Bool { NSApp.currentEvent?.type == .keyDown }
    static var timing: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) }
    static var navigation: Animation? {
        reduced || keyboard ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: MultiInterfaceMetrics.navigationDuration)
    }
}

// Vendored identically in both products. No business models or cross-repository dependency.
enum MultiDesign {
    static let expanded = MultiInterfaceMetrics.sidebarExpanded
    static let collapsed = MultiInterfaceMetrics.sidebarCollapsed
    static let pageInset = MultiInterfaceMetrics.pageInset
    static let formWidth = MultiInterfaceMetrics.formMaximum + 2 * MultiInterfaceMetrics.pageInset
    static let rowHeight = MultiInterfaceMetrics.navigationRow
    static let sidebarDuration = MultiInterfaceMetrics.sidebarDuration
    static let popoverWidth = MultiInterfaceMetrics.popoverWidth
    static func neutral(_ light: CGFloat, _ dark: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light, alpha: 1) }
    }
    static let canvas = neutral(0.972, 0.075)
    static let rail = neutral(0.94, 0.12)
    static let card = neutral(0.99, 0.105)
    static let ink = neutral(0.10, 0.94)
    static let secondary = neutral(0.43, 0.65)
    static var selected: NSColor {
        SettingsManager.shared.monochromeControls
            ? neutral(0.88, 0.22)
            : NSColor.controlAccentColor.withAlphaComponent(0.20)
    }
    /// Keep SF Symbols at their native aspect ratio in a fixed optical slot.
    static func symbolRect(size: NSSize, center: NSPoint, extent: CGFloat = 18) -> NSRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = extent / max(size.width, size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: center.x - fitted.width / 2, y: center.y - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
    static func visibleFrame(_ frame: NSRect, screens: [NSRect]) -> NSRect {
        MultiInterfaceMetrics.visibleWindowFrame(frame, screens: screens, minimum: .zero)
    }
}

/// Window sizing belongs to this native window, including after SwiftUI installs
/// hosting preferences. System chrome and resize interactions remain AppKit-owned.
@MainActor class MultiBoundedWindow: NSWindow {
    var onDeleteSelection: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 51 || event.keyCode == 117), let onDeleteSelection,
           !(firstResponder is NSTextView), attachedSheet == nil {
            if !event.isARepeat { onDeleteSelection() }
            return
        }
        super.keyDown(with: event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
           attachedSheet == nil {
            if let text = firstResponder as? NSTextView {
                if text.hasMarkedText() { return super.performKeyEquivalent(with: event) }
                // End native field editing before the next Escape closes the window.
                endEditing(for: nil)
                makeFirstResponder(nil)
            } else {
                performClose(nil)
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        guard attachedSheet == nil else { return }
        performClose(sender)
    }
    weak var sidebarHost: MultiSidebarHost?
    var expandedMinimum: NSSize?
    var expandedMaximum: NSSize?
    private(set) var usefulMinimum: NSSize?
    private(set) var usefulMaximum: NSSize?
    func setUsefulLimits(minimum: NSSize, maximum: NSSize) {
        guard usefulMinimum != minimum || usefulMaximum != maximum else { return }
        usefulMinimum = minimum; usefulMaximum = maximum
        super.contentMinSize = minimum
        super.contentMaxSize = maximum
    }
    override var contentMinSize: NSSize {
        get { usefulMinimum ?? super.contentMinSize }
        set { super.contentMinSize = usefulMinimum ?? newValue }
    }
    override var contentMaxSize: NSSize {
        get { usefulMaximum ?? super.contentMaxSize }
        set { super.contentMaxSize = usefulMaximum ?? newValue }
    }
    override var minSize: NSSize {
        get { usefulMinimum.map { frameRect(forContentRect: NSRect(origin: .zero, size: $0)).size } ?? super.minSize }
        set { super.minSize = usefulMinimum.map { frameRect(forContentRect: NSRect(origin: .zero, size: $0)).size } ?? newValue }
    }
    override var maxSize: NSSize {
        get { usefulMaximum.map { frameRect(forContentRect: NSRect(origin: .zero, size: $0)).size } ?? super.maxSize }
        set { super.maxSize = usefulMaximum.map { frameRect(forContentRect: NSRect(origin: .zero, size: $0)).size } ?? newValue }
    }
}

/// AppKit owns window dimensions; content owns reflow. All dimensions are logical points.
@MainActor enum MultiWindowPolicy {
    static func adjusted(_ size: NSSize, in window: NSWindow) -> NSSize {
        MultiInterfaceMetrics.settingsSize(size, progress: (window as? MultiBoundedWindow)?.sidebarHost?.windowProgress ?? 1)
    }
    static func configure(_ window: NSWindow, minimum: NSSize, maximum: NSSize) {
        if let bounded = window as? MultiBoundedWindow {
            bounded.expandedMinimum = minimum; bounded.expandedMaximum = maximum
            if bounded.sidebarHost?.isResizingWindow == true { return }
        }
        let minimum = adjusted(minimum, in: window), maximum = adjusted(maximum, in: window)
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let chrome = max(0, window.frame.height - window.contentRect(forFrameRect: window.frame).height)
        let available = NSSize(width: screen.width, height: max(1, screen.height - chrome))
        let minSize = MultiInterfaceMetrics.boundedSize(minimum, minimum: .zero, maximum: minimum, available: available)
        let maxSize = MultiInterfaceMetrics.boundedSize(maximum, minimum: minSize, maximum: maximum, available: available)
        if let bounded = window as? MultiBoundedWindow {
            bounded.setUsefulLimits(minimum: minSize, maximum: maxSize)
        } else {
            if window.contentMinSize != minSize { window.contentMinSize = minSize }
            if window.contentMaxSize != maxSize { window.contentMaxSize = maxSize }
        }
        let current = window.contentRect(forFrameRect: window.frame).size
        let size = MultiInterfaceMetrics.boundedSize(current, minimum: window.contentMinSize, maximum: window.contentMaxSize, available: available)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        frame = MultiDesign.visibleFrame(frame, screens: NSScreen.screens.map(\.visibleFrame))
        if frame != window.frame {
            if let host = (window as? MultiBoundedWindow)?.sidebarHost { host.constrainWindow(to: frame) }
            else { window.setFrame(frame, display: window.isVisible) }
        }
    }
    static func resizeFrameSize(_ window: NSWindow, proposed: NSSize, minimum: NSSize, maximum: NSSize) -> NSSize {
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let chrome = max(0, window.frame.height - window.contentRect(forFrameRect: window.frame).height)
        let content = window.contentRect(forFrameRect: NSRect(origin: .zero, size: proposed)).size
        let size = MultiInterfaceMetrics.boundedSize(content, minimum: adjusted(minimum, in: window), maximum: adjusted(maximum, in: window),
            available: NSSize(width: screen.width, height: max(1, screen.height - chrome)))
        return window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
    }
    static func zoomFrame(_ window: NSWindow, ideal: NSSize) -> NSRect {
        let size = MultiInterfaceMetrics.boundedSize(adjusted(ideal, in: window), minimum: window.contentMinSize,
            maximum: window.contentMaxSize, available: window.contentMaxSize)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        return MultiDesign.visibleFrame(frame, screens: NSScreen.screens.map(\.visibleFrame))
    }
}

struct MultiInstructionCard: View {
    let number: String
    let title: String
    let detail: String
    let symbol: String
    var iconOpacity: Double = 1
    var reduceMotion: Bool = false
    var keyLabel: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 0)
                Group {
                    if let keyLabel {
                        Text(keyLabel)
                            .font(.system(size: 24, weight: .medium))
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 24, weight: .regular))
                    }
                }
                .foregroundStyle(Color(nsColor: MultiDesign.ink))
                .frame(width: 36, height: 36)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.sm, style: .continuous))
                Spacer(minLength: 0)
            }
            .opacity(iconOpacity)
            .animation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: MultiInterfaceMetrics.navigationDuration), value: iconOpacity)

            VStack(alignment: .leading, spacing: 5) {
                Text(number)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(nsColor: MultiDesign.secondary))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(nsColor: MultiDesign.ink))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: MultiDesign.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(nsColor: MultiDesign.card), in: RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.lg).strokeBorder(Color(nsColor: MultiDesign.secondary).opacity(0.13), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.025), radius: 8, y: 3)
    }
}

struct MultiActionButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        MultiActionButtonBody(configuration: configuration, primary: primary, enabled: enabled, reduceMotion: reduceMotion)
    }

    private struct MultiActionButtonBody: View {
        let configuration: Configuration
        let primary: Bool
        let enabled: Bool
        let reduceMotion: Bool
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(primary ? Color(nsColor: MultiDesign.canvas) : Color(nsColor: MultiDesign.ink))
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(primary ? Color(nsColor: MultiDesign.ink) : (hovered || configuration.isPressed ? Color(nsColor: MultiDesign.selected) : Color(nsColor: MultiDesign.rail)),
                            in: RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: MultiInterfaceMetrics.Radius.sm).strokeBorder(Color(nsColor: MultiDesign.secondary).opacity(0.13), lineWidth: 1))
                .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: MultiInterfaceMetrics.navigationDuration), value: configuration.isPressed)
                .animation(.easeOut(duration: MultiInterfaceMetrics.hoverDuration), value: hovered)
                .onHover { hovered = $0 }
        }
    }
}

struct MultiNavigationItem: Equatable {
    let id: String
    let title: String
    let symbol: String
}

@MainActor private final class MultiNavigationButton: NSButton {
    var phase: CGFloat = 1 { didSet { needsDisplay = true } }
    var selected = false { didSet { state = selected ? .on : .off; needsDisplay = true } }
    var navigate: ((Int) -> Void)?
    private var hovering = false
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 125 { navigate?(1); return }
        if event.keyCode == 126 { navigate?(-1); return }
        super.keyDown(with: event)
    }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: MultiInterfaceMetrics.Radius.sm, yRadius: MultiInterfaceMetrics.Radius.sm)
        if selected {
            MultiDesign.selected.withAlphaComponent(isHighlighted ? 0.98 : 0.88).setFill(); shape.fill()
        } else if hovering || isHighlighted {
            MultiDesign.ink.withAlphaComponent(isHighlighted ? 0.11 : 0.055).setFill(); shape.fill()
        }
        if window?.firstResponder === self {
            let focusShape = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                                          xRadius: MultiInterfaceMetrics.Radius.sm - 1,
                                          yRadius: MultiInterfaceMetrics.Radius.sm - 1)
            MultiDesign.ink.withAlphaComponent(0.72).setStroke()
            focusShape.lineWidth = 1.25
            focusShape.setLineDash([3, 2], count: 2, phase: 0)
            focusShape.stroke()
        }
        let ink = selected ? MultiDesign.ink : MultiDesign.secondary
        if let symbol = image?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))?
            .withSymbolConfiguration(.init(paletteColors: [ink])) {
            let rect = MultiDesign.symbolRect(size: symbol.size, center: NSPoint(x: 18, y: bounds.midY))
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                        respectFlipped: true, hints: nil)
        }
        let alpha = min(1, max(0, (phase - 0.65) / 0.35))
        if alpha > 0 {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            (title as NSString).draw(in: NSRect(x: 36, y: bounds.midY - 8, width: max(0, bounds.width - 44), height: 18), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .regular), .foregroundColor: ink.withAlphaComponent(alpha), .paragraphStyle: paragraph])
        }
    }
}
@MainActor private final class MultiRail: NSView {
    var appName = ""
    var phase: CGFloat = 1
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        MultiDesign.rail.setFill(); bounds.fill()
        let mark = NSRect(x: 16, y: 20, width: 28, height: 28)
        if appName != "multiswitcher" {
            MultiDesign.card.setFill(); NSBezierPath(roundedRect: mark, xRadius: MultiInterfaceMetrics.Radius.sm, yRadius: MultiInterfaceMetrics.Radius.sm).fill()
        }
        if appName == "multiswitcher" {
            // The external app icon includes a large shadow. At sidebar scale
            // AppKit clips that shadow to the image bounds, leaving a gray square
            // behind the rounded tile. The in-app brand mark has no shadow.
            MultiBrandIcon.embeddedSwitcher.draw(in: mark, from: .zero, operation: .sourceOver,
                fraction: 1, respectFlipped: true, hints: nil)
        }
        let text = appName == "multiswitcher" ? "" : "↑"
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (text as NSString).draw(in: mark.insetBy(dx: 1, dy: 5), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: MultiDesign.ink, .paragraphStyle: paragraph])
        let alpha = min(1, max(0, (phase - 0.65) / 0.35))
        if alpha > 0 {
            (appName as NSString).draw(in: NSRect(x: 54, y: 26, width: max(0, bounds.width - 62), height: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: MultiDesign.ink.withAlphaComponent(alpha)])
        }
    }
}
@MainActor private final class MultiRailDocument: NSView { override var isFlipped: Bool { true } }

/// A single continuously sampled phase owns the rail, rows, icons, selection and detail.
/// There is no fixed-width expanded subtree under a collapsed rail and no clipping fix.
@MainActor final class MultiSidebarHost: NSView {
    let detail: NSView
    private let rail = MultiRail()
    private let scroll = NSScrollView()
    private let document = MultiRailDocument()
    private var buttons: [MultiNavigationButton] = []
    private var items: [MultiNavigationItem] = []
    private(set) var selectedID = ""
    private(set) var progress: CGFloat = 1
    private(set) var requestedCollapsed = false
    private var automaticCollapsed = false
    private(set) var windowProgress: CGFloat = 1
    private(set) var isResizingWindow = false
    private var resizesWindow = false
    private var expandedContentWidth: CGFloat?
    private var progressVelocity: CGFloat = 0
    private var timer: Timer?
    private var goal: CGFloat = 1
    var reduceMotionOverride = false {
        didSet { if reduceMotionOverride { updateTarget(animated: false) } }
    }
    var onSelect: ((String) -> Void)?
    var onGeometry: (() -> Void)?
    private var geometryQueued = false
    private var lastDetailSize: NSSize?
    var frameSamples: [[Double]] = []
    var collectSamples = false
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    var railWidth: CGFloat { MultiDesign.collapsed + (MultiDesign.expanded - MultiDesign.collapsed) * progress }
    init(detail: NSView) {
        self.detail = detail
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 560))
        autoresizingMask = [.width, .height]
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        // An inset legacy scrollbar consumes 15 pt of the compact 36 pt row,
        // clipping the icon. Overlay scrolling preserves the navigation slot.
        scroll.scrollerStyle = .overlay
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = document
        rail.addSubview(scroll)
        addSubview(rail); addSubview(detail)
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(accessibilityMotionChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    @objc private func accessibilityMotionChanged() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { updateTarget(animated: false) }
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    func configure(appName: String, items: [MultiNavigationItem], selected: String) {
        rail.appName = appName
        if self.items != items {
            self.items = items
            buttons.forEach { $0.removeFromSuperview() }
            buttons = items.enumerated().map { index, item in
                let button = MultiNavigationButton(title: item.title, target: self, action: #selector(choose(_:)))
                button.tag = index; button.setButtonType(.radio); button.isBordered = false
                button.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
                button.focusRingType = .none; button.toolTip = item.title
                button.setAccessibilityLabel(item.title)
                button.navigate = { [weak self] delta in self?.moveSelection(delta) }
                document.addSubview(button)
                return button
            }
        }
        selectedID = selected
        for (index, button) in buttons.enumerated() { button.selected = items[index].id == selected }
        arrange()
    }
    @objc private func choose(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        selectedID = items[sender.tag].id
        for (index, button) in buttons.enumerated() { button.selected = items[index].id == selectedID }
        onSelect?(selectedID)
    }
    private func moveSelection(_ delta: Int) {
        guard let index = items.firstIndex(where: { $0.id == selectedID }), !buttons.isEmpty else { return }
        let next = min(buttons.count - 1, max(0, index + delta))
        window?.makeFirstResponder(buttons[next]); choose(buttons[next])
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window as? MultiBoundedWindow { window.sidebarHost = self }
    }
    func constrainWindow(to frame: NSRect) {
        guard let window else { return }
        isResizingWindow = true
        window.setFrame(frame, display: window.isVisible)
        isResizingWindow = false
    }
    func setCollapsed(_ collapsed: Bool, animated: Bool = true) {
        let changed = requestedCollapsed != collapsed
        if changed {
            if let window {
                if timer == nil || expandedContentWidth == nil {
                    expandedContentWidth = window.contentRect(forFrameRect: window.frame).width
                        + MultiInterfaceMetrics.sidebarDelta * (1 - windowProgress)
                }
                resizesWindow = true
            } else { windowProgress = collapsed ? 0 : 1 }
        }
        requestedCollapsed = collapsed
        updateTarget(animated: animated)
    }
    private func applyProgress(_ value: CGFloat) {
        progress = value
        if resizesWindow, let window, let expandedContentWidth {
            isResizingWindow = true
            windowProgress = value
            let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
            let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
            if let bounded = window as? MultiBoundedWindow,
               let minimum = bounded.expandedMinimum, let maximum = bounded.expandedMaximum {
                let room = NSSize(width: screen.width, height: max(1, screen.height - chrome))
                let low = MultiInterfaceMetrics.settingsSize(minimum, progress: value)
                let high = MultiInterfaceMetrics.settingsSize(maximum, progress: value)
                bounded.setUsefulLimits(minimum: MultiInterfaceMetrics.boundedSize(low, minimum: .zero, maximum: low, available: room),
                    maximum: MultiInterfaceMetrics.boundedSize(high, minimum: low, maximum: high, available: room))
            }
            var frame = window.frame
            frame.size.width = expandedContentWidth - MultiInterfaceMetrics.sidebarDelta * (1 - value)
            frame = MultiDesign.visibleFrame(frame, screens: NSScreen.screens.map(\.visibleFrame))
            if frame != window.frame { window.setFrame(frame, display: window.isVisible) }
            isResizingWindow = false
        }
        arrange()
    }
    private func updateTarget(animated: Bool) {
        let target: CGFloat = requestedCollapsed || automaticCollapsed ? 0 : 1
        // Reduced motion and immediate requests must interrupt an already-running spring.
        if !animated || reduceMotionOverride || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || window?.isVisible != true {
            let needsUpdate = timer != nil || goal != target || progress != target
            timer?.invalidate(); timer = nil; goal = target; progressVelocity = 0
            if needsUpdate { applyProgress(target) }
            resizesWindow = false
            return
        }
        guard target != goal || abs(progress - target) > 0.0001 && timer == nil else {
            if timer == nil { resizesWindow = false }
            return
        }
        if target == goal, timer != nil { return }
        timer?.invalidate(); timer = nil; goal = target
        guard animated, !reduceMotionOverride, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, window?.isVisible == true else {
            progressVelocity = 0; applyProgress(target); resizesWindow = false; return
        }
        // Keep spring arithmetic in Double; mixing CGFloat and Double here
        // exhausts the type solver in older supported Swift toolchains.
        let start: Double = Double(progress)
        let velocity: Double = Double(progressVelocity)
        let destination: Double = Double(target)
        let duration: Double = MultiDesign.sidebarDuration
        let startTime: Double = ProcessInfo.processInfo.systemUptime
        let animation = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                let t: Double = min(1.0, (ProcessInfo.processInfo.systemUptime - startTime) / duration)
                let decay: Double = exp(-9.0 * t)
                let normalization: Double = 1.0 - 10.0 * exp(-9.0)
                let spring: Double = (1.0 - (1.0 + 9.0 * t) * decay) / normalization
                let continuation: Double = velocity * duration * t * pow(1.0 - t, 2.0)
                let raw: Double = start + (destination - start) * spring + continuation
                let value: Double = min(1.0, max(0.0, raw))
                let baseVelocity: Double = (destination - start) * 81.0 * t * decay / normalization / duration
                let carriedVelocity: Double = velocity * (1.0 - 4.0 * t + 3.0 * t * t)
                self.progressVelocity = CGFloat(value == raw ? baseVelocity + carriedVelocity : 0.0)
                self.applyProgress(CGFloat(value))
                if t >= 1.0 { self.timer?.invalidate(); self.timer = nil; self.progressVelocity = 0; self.applyProgress(target); self.resizesWindow = false }
            }
        }
        timer = animation; RunLoop.main.add(animation, forMode: .common)
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        arrange()
        buttons.forEach { $0.needsDisplay = true }
    }
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        // Hysteresis is based on the space remaining for content, not the display.
        if !isResizingWindow && timer == nil {
            expandedContentWidth = bounds.width + MultiInterfaceMetrics.sidebarDelta * (1 - windowProgress)
        }
        let previous = automaticCollapsed
        let available = bounds.width + MultiInterfaceMetrics.sidebarDelta * (1 - windowProgress) - MultiDesign.expanded - 1
        if available < 440 { automaticCollapsed = true }
        else if available > 464 { automaticCollapsed = false }
        if previous != automaticCollapsed { updateTarget(animated: true) }
        arrange()
    }
    private func arrange() {
        guard bounds.width > 0 else { return }
        let width = min(railWidth, bounds.width)
        rail.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        rail.phase = progress; rail.needsDisplay = true
        scroll.frame = NSRect(x: 12, y: 64, width: max(0, width - 24), height: max(0, bounds.height - 76))
        document.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: CGFloat(items.count) * 36)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: 0, y: CGFloat(index) * 36, width: document.bounds.width, height: MultiDesign.rowHeight)
            button.phase = progress
        }
        let detailFrame = NSRect(x: width + 1, y: 0, width: max(0, bounds.width - width - 1), height: bounds.height)
        // During sidebar animation the outer window follows the rail, leaving the
        // detail size unchanged. Avoid repeatedly measuring the entire page tree.
        let sizeChanged = lastDetailSize.map {
            abs($0.width - detailFrame.width) > 0.5 || abs($0.height - detailFrame.height) > 0.5
        } ?? true
        if detail.frame != detailFrame { detail.frame = detailFrame }
        if sizeChanged { lastDetailSize = detailFrame.size }
        if collectSamples { frameSamples.append([ProcessInfo.processInfo.systemUptime, Double(progress), Double(width), Double(detail.frame.minX), Double(bounds.width)]) }
        if sizeChanged && !geometryQueued {
            geometryQueued = true
            DispatchQueue.main.async { [weak self] in self?.geometryQueued = false; self?.onGeometry?() }
        }
    }
    func geometryIsValid() -> Bool {
        let width = rail.bounds.width
        return buttons.allSatisfy { $0.frame.minX >= 0 && $0.frame.maxX <= width - 24 + 0.5 }
            && abs(detail.frame.minX - width - 1) < 0.5
            && abs(detail.frame.maxX - bounds.width) < 0.5
    }
    var isAnimating: Bool { timer != nil }
    var reviewSectionCount: Int { items.count }
    func reviewSelect(_ index: Int) {
        guard buttons.indices.contains(index) else { return }
        buttons[index].performClick(nil)
    }
    func reviewArrow() -> Bool {
        guard buttons.count > 1 else { return true }
        reviewSelect(0)
        window?.makeFirstResponder(buttons[0])
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function], timestamp: 0,
            windowNumber: window?.windowNumber ?? 0, context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125) else { return false }
        buttons[0].keyDown(with: event)
        return selectedID == items[1].id
    }
}

@MainActor struct MultiSidebarContainer<Detail: View>: NSViewRepresentable {
    let appName: String
    let items: [MultiNavigationItem]
    let selected: String
    let collapsed: Bool
    let onSelect: (String) -> Void
    @ViewBuilder var detail: () -> Detail
    func makeNSView(context: Context) -> MultiSidebarHost {
        let hosting = NSHostingView(rootView: detail())
        hosting.sizingOptions = []
        let host = MultiSidebarHost(detail: hosting)
        host.configure(appName: appName, items: items, selected: selected)
        host.onSelect = onSelect
        host.setCollapsed(collapsed, animated: false)
        return host
    }
    func updateNSView(_ host: MultiSidebarHost, context: Context) {
        (host.detail as? NSHostingView<Detail>)?.rootView = detail()
        host.onSelect = onSelect
        host.configure(appName: appName, items: items, selected: selected)
        if !host.collectSamples && ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] == nil { host.setCollapsed(collapsed) }
    }
}



/// Review geometry stays in SwiftUI preferences; no extra AppKit responder is inserted.
struct MultiSurfaceMetric: Equatable, Sendable {
    let kind: String
    let radius: CGFloat
    let frame: CGRect
}
struct MultiSurfacePreference: PreferenceKey {
    static var defaultValue: [String: MultiSurfaceMetric] { [:] }
    static func reduce(value: inout [String: MultiSurfaceMetric], nextValue: () -> [String: MultiSurfaceMetric]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
@MainActor enum MultiSurfaceMetrics { static var frames: [String: MultiSurfaceMetric] = [:] }
struct MultiMeasurement: View {
    let kind: String
    let radius: CGFloat
    @State private var id = UUID().uuidString
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: MultiSurfacePreference.self,
                value: [id: MultiSurfaceMetric(kind: kind, radius: radius, frame: proxy.frame(in: .named("multi-settings")))])
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Exercises the actual shared native component inside each application's real window.
/// Review mode never starts input monitors or changes business records.
@MainActor enum MultiEcosystemProbe {
    static func findHost(_ view: NSView?) -> MultiSidebarHost? {
        guard let view else { return nil }
        if let host = view as? MultiSidebarHost { return host }
        for child in view.subviews { if let found = findHost(child) { return found } }
        return nil
    }
    static func capture(_ window: NSWindow, path: String) {
        // Resume an interrupted review without overwriting successful native captures.
        if ProcessInfo.processInfo.environment["MULTI_QA_RESUME"] == "1",
           FileManager.default.fileExists(atPath: path) { return }
        window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        CATransaction.flush()
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        try? process.run(); process.waitUntilExit()
        if process.terminationStatus != 0, let view = window.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                let backing = URL(fileURLWithPath: path).deletingPathExtension().path + "-backing.png"
                try? data.write(to: URL(fileURLWithPath: backing))
            }
        }
    }
    static func checkRelaunch(window: NSWindow, directory: String, phase: String, ideal: NSSize) {
        let path = URL(fileURLWithPath: directory).appendingPathComponent("relaunch-expected.json")
        func values(_ frame: NSRect) -> [Double] { [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)] }
        if phase == "save" {
            window.setContentSize(ideal)
            if let screen = window.screen?.visibleFrame {
                window.setFrameOrigin(NSPoint(x: screen.minX + 48, y: screen.maxY - window.frame.height - 36))
            }
            if !window.frameAutosaveName.isEmpty { window.saveFrame(usingName: window.frameAutosaveName) }
            try? JSONSerialization.data(withJSONObject: values(window.frame)).write(to: path)
        } else {
            let data = try? Data(contentsOf: path)
            let expected = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [Double] } ?? []
            let actual = values(window.frame)
            let passed = expected.count == 4 && zip(expected, actual).allSatisfy { abs($0 - $1) < 1 }
            let report: [String: Any] = ["passed": passed, "expected": expected, "actual": actual,
                "freshProcess": true, "autosaveName": window.frameAutosaveName]
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: directory + "/relaunch-results.json"))
            capture(window, path: directory + "/relaunch-restored.png")
        }
        NSApp.terminate(nil)
    }
    static func measurements(_ window: NSWindow) -> [String: Any] {
        guard let root = window.contentView, let host = findHost(root) else { return [:] }
        var surfaces: [[String: Any]] = []
        var textOverflow = 0
        var tableCount = 0
        func frameData(_ rect: NSRect) -> [String: Double] {
            ["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)]
        }
        @MainActor func visit(_ view: NSView) {
            guard !view.isHidden else { return }
            let name = String(describing: type(of: view))
            let isCard = name.contains("SettingsCardBackground")
            let heading = ((view as? NSTextField)?.font?.pointSize ?? 0) >= 19
            if isCard || heading {
                let rect = view.convert(view.bounds, to: host.detail)
                surfaces.append(["kind": isCard ? "card" : "heading", "frame": frameData(rect),
                    "radius": Double(isCard ? MultiInterfaceMetrics.Radius.lg : 0),
                    "visible": !view.visibleRect.isEmpty])
            }
            if let field = view as? NSTextField, !field.isEditable, field.maximumNumberOfLines == 0, !field.visibleRect.isEmpty {
                let required = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 10000)).height ?? 0
                if required > field.bounds.height + 2 { textOverflow += 1 }
            }
            if view is NSTableView { tableCount += 1 }
            view.subviews.forEach(visit)
        }
        visit(host.detail)
        for metric in MultiSurfaceMetrics.frames.values {
            surfaces.append(["kind": metric.kind, "frame": frameData(metric.frame),
                "radius": Double(metric.radius), "visible": host.detail.bounds.intersects(metric.frame)])
        }
        let cards = surfaces.filter { ($0["kind"] as? String) == "card" }
        let leading = cards.compactMap { ($0["frame"] as? [String: Double])?["x"] }
        let guidesAligned = leading.isEmpty || (leading.max()! - leading.min()! < 1.5)
        return ["surfaces": surfaces, "cardLeadingAligned": guidesAligned, "textOverflowCandidates": textOverflow,
            "tables": tableCount, "detailWidth": Double(host.detail.bounds.width),
            "sidebarWidth": Double(host.railWidth), "backingScale": Double(window.backingScaleFactor),
            "windowContent": frameData(root.bounds), "minimum": [window.contentMinSize.width, window.contentMinSize.height],
            "maximum": [window.contentMaxSize.width, window.contentMaxSize.height],
            "focusVisible": (window.firstResponder as? NSView).map { !$0.visibleRect.isEmpty } ?? true]
    }
    static func run(window: NSWindow, app: String, directory: String, normal: NSSize, minimum: NSSize,
                    theme: @escaping @MainActor (String) -> Void, completion: @escaping @MainActor () -> Void) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        window.title = app + " ecosystem review"
        Task { @MainActor in
            let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "isolated window layout verification")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            func pause(_ seconds: Double) async {
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { continuation.resume() }
                }
            }
            await pause(1)
            guard let host = findHost(window.contentView) else { NSLog("ECOSYSTEM FAIL: native host missing"); completion(); return }
            var report: [String: Any] = ["app": app, "keyboard": host.reviewArrow()]
            var valid = true
            host.collectSamples = true
            let usefulMaximum = app == "multishift" ? MultiInterfaceMetrics.shiftMaximum : MultiInterfaceMetrics.switcherMaximum
            let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
            let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
            let large = MultiInterfaceMetrics.boundedSize(usefulMaximum, minimum: minimum, maximum: usefulMaximum,
                available: NSSize(width: screen.width, height: screen.height - chrome))
            let maximumEnforced = window.contentMaxSize.width <= large.width + 1 && window.contentMaxSize.height <= large.height + 1
            report["nativeMaximumEnforced"] = maximumEnforced
            valid = valid && maximumEnforced
            @MainActor func setSize(_ size: NSSize) {
                window.setContentSize(MultiInterfaceMetrics.boundedSize(MultiWindowPolicy.adjusted(size, in: window),
                    minimum: window.contentMinSize, maximum: window.contentMaxSize, available: window.contentMaxSize))
                // Programmatic QA resize can place the frame beyond the visible top.
                // Settle that system correction before checking navigation stability.
                let fitted = MultiDesign.visibleFrame(window.frame, screens: NSScreen.screens.map(\.visibleFrame))
                if fitted != window.frame { window.setFrame(fitted, display: true, animate: false) }
            }
            setSize(normal); window.center()
            let video = Process(); video.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            video.arguments = ["-x", "-v", "-V", "18", "-l", String(window.windowNumber), directory + "/sidebar-resize-theme.mov"]
            if ProcessInfo.processInfo.environment["MULTI_QA_RESUME"] != "1" ||
               !FileManager.default.fileExists(atPath: directory + "/sidebar-resize-theme.mov") { try? video.run() }
            // Twenty complete cycles, with frame containment checked at intermediate phases.
            for cycle in 0..<20 {
                if cycle % 5 == 0 { NSLog("LAYOUT REVIEW %@ sidebar cycle %d", app, cycle) }
                for collapsed in [true, false] {
                    host.setCollapsed(collapsed)
                    for _ in 0..<14 { await pause(0.02); valid = valid && host.geometryIsValid() }
                }
            }
            NSLog("LAYOUT REVIEW %@ full cycles finished", app)
            for index in 0..<20 {
                host.setCollapsed(index % 2 == 0)
                await pause(0.025)
                valid = valid && host.geometryIsValid()
            }
            NSLog("LAYOUT REVIEW %@ rapid reversals finished", app)
            host.setCollapsed(false)
            for size in [minimum, large, NSSize(width: minimum.width, height: large.height), NSSize(width: large.width, height: minimum.height), normal] {
                NSLog("LAYOUT REVIEW %@ resize %.0f x %.0f", app, size.width, size.height)
                setSize(size)
                await pause(0.22)
                valid = valid && host.geometryIsValid()
            }
            NSLog("LAYOUT REVIEW %@ themes", app)
            theme("dark"); await pause(0.25); theme("light"); await pause(0.25)
            NSLog("LAYOUT REVIEW %@ reduced motion", app)
            host.reduceMotionOverride = true
            host.setCollapsed(true)
            report["reducedMotion"] = !host.isAnimating && host.progress == 0
            host.setCollapsed(false); host.reduceMotionOverride = false
            await pause(0.3)
            report["cycles"] = 20; report["rapidReversals"] = 20
            report["geometry"] = valid; report["timerStopped"] = !host.isAnimating
            let frameFile = directory + "/sidebar-frames.json"
            try? JSONSerialization.data(withJSONObject: host.frameSamples).write(to: URL(fileURLWithPath: frameFile))
            host.collectSamples = false
            var stable = true
            var matrix: [[String: Any]] = []
            let quick = ProcessInfo.processInfo.environment["MULTI_QA_QUICK"] == "1"
            func sameFrame(_ a: NSRect, _ b: NSRect) -> Bool {
                abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1
                    && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
            }
            for mode in ["light", "dark"] {
                let sizes = [("minimum", minimum), ("ideal", normal), ("maximum", large),
                    ("narrow", NSSize(width: minimum.width, height: normal.height)),
                    ("wide", NSSize(width: large.width, height: normal.height)),
                    ("height-only", NSSize(width: normal.width, height: large.height)),
                    ("width-only", NSSize(width: large.width, height: normal.height)),
                    ("zoom", normal), ("restore", normal)]
                for (label, size) in sizes where !quick || ["minimum", "maximum", "restore"].contains(label) {
                    setSize(size); await pause(0.3)
                    let frame = window.frame
                    theme(mode); await pause(0.18)
                    stable = stable && sameFrame(window.frame, frame)
                    for collapsed in [false, true] {
                        let beforeCollapse = window.frame
                        let oldProgress = host.windowProgress
                        host.setCollapsed(collapsed); await pause(0.3)
                        for _ in 0..<50 where host.isAnimating { await pause(0.02) }
                        let expected = beforeCollapse.width + MultiInterfaceMetrics.sidebarDelta * (host.windowProgress - oldProgress)
                        stable = stable && abs(window.frame.width - expected) < 1
                            && abs(window.frame.height - beforeCollapse.height) < 1
                        for section in 0..<host.reviewSectionCount {
                            let beforeNavigation = window.frame
                            host.reviewSelect(section); await pause(0.3)
                            let navigationStable = sameFrame(window.frame, beforeNavigation)
                            stable = stable && navigationStable
                            valid = valid && host.geometryIsValid()
                            let before = window.frame
                            var restored = true
                            if label == "zoom" { window.zoom(nil); await pause(0.4) }
                            if label == "restore" {
                                // Fixture persistence never writes NSWindow keys into the real app domain.
                                let path = directory + "/restore-frame.txt"
                                try? NSStringFromRect(before).write(toFile: path, atomically: true, encoding: .utf8)
                                setSize(minimum)
                                if let saved = try? String(contentsOfFile: path, encoding: .utf8) {
                                    window.setFrame(NSRectFromString(saved), display: true, animate: false)
                                }
                                await pause(0.15)
                                for _ in 0..<50 where host.isAnimating { await pause(0.02) }
                                restored = abs(window.frame.width - before.width) < 1 && abs(window.frame.height - before.height) < 1
                            }
                            let filename = "\(mode)-\(label)-\(collapsed ? "compact" : "expanded")-\(section).png"
                            var measurement = measurements(window)
                            measurement["image"] = filename; measurement["restored"] = restored
                            measurement["nativeMaximumEnforced"] = window.contentMaxSize.width <= large.width + 1 && window.contentMaxSize.height <= large.height + 1
                            valid = valid && (measurement["nativeMaximumEnforced"] as? Bool == true)
                            measurement["geometry"] = host.geometryIsValid()
                            measurement["navigationStable"] = navigationStable
                            measurement["beforeNavigation"] = [beforeNavigation.minX, beforeNavigation.minY, beforeNavigation.width, beforeNavigation.height]
                            measurement["afterNavigation"] = [before.minX, before.minY, before.width, before.height]
                            measurement["restoreExpected"] = [before.width, before.height]
                            matrix.append(measurement)
                            capture(window, path: directory + "/" + filename)
                            matrix[matrix.count - 1]["systemScreenshot"] = FileManager.default.fileExists(atPath: directory + "/" + filename)
                            if label == "zoom" {
                                window.zoom(nil); await pause(0.4)
                                window.setFrame(before, display: true, animate: false); await pause(0.1)
                            }
                        }
                    }
                }
            }
            report["matrixStates"] = matrix.count
            report["systemScreenshots"] = matrix.filter { $0["systemScreenshot"] as? Bool == true }.count
            report["restoreMechanism"] = "isolated frame fixture; fresh-process app restoration tested separately"
            report["allRestoreStates"] = matrix.allSatisfy { $0["restored"] as? Bool == true }
            report["allCardGuidesAligned"] = matrix.allSatisfy { $0["cardLeadingAligned"] as? Bool == true }
            try? JSONSerialization.data(withJSONObject: matrix, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: directory + "/layout-measurements.json"))
            report["geometry"] = valid; report["stableNavigationAndTheme"] = stable
            report["sectionCount"] = host.reviewSectionCount
            report["windowNumber"] = window.windowNumber
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: directory + "/geometry-results.json"))
            NSLog("ECOSYSTEM %@ geometry=%@ stable=%@", app, valid.description, stable.description)
            completion()
        }
    }
}


/// One sheet per parent; the captured identity belongs to the caller, never a row index.
@MainActor enum MultiDeletionConfirmation {
    static func request(window: NSWindow?, defaults: UserDefaults, kind: String,
                        title: String, detail: String = "", russian: Bool,
                        completion: @escaping @MainActor () throws -> Void) {
        guard let window, window.attachedSheet == nil else { return }
        func execute() -> Bool {
            do { try completion(); return true }
            catch {
                let alert = NSAlert()
                alert.messageText = russian ? "не удалось сохранить изменение" : "could not save the change"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: russian ? "закрыть" : "close")
                DispatchQueue.main.async { alert.beginSheetModal(for: window) }
                return false
            }
        }
        if !isEnabled(defaults) { _ = execute(); return }
        let responder = window.firstResponder
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: russian ? "подтвердить" : "confirm").keyEquivalent = "\r"
        alert.addButton(withTitle: russian ? "отмена" : "cancel").keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = russian ? "больше не спрашивать" : "do not ask again"
        alert.beginSheetModal(for: window) { response in
            if let responder { window.makeFirstResponder(responder) }
            guard response == .alertFirstButtonReturn else { return }
            if execute(), alert.suppressionButton?.state == .on { setEnabled(false, defaults: defaults) }
        }
    }
    static let changed = Notification.Name("MultiDeletionConfirmationChanged")
    private static let enabledKey = "deletion.askBeforeDeleting"
    static func isEnabled(_ defaults: UserDefaults) -> Bool {
        if let value = defaults.object(forKey: enabledKey) as? Bool { return value }
        // Preserve a previously chosen suppression when upgrading the old control.
        return !defaults.dictionaryRepresentation().contains { $0.key.hasPrefix("deletion.skip.") && ($0.value as? Bool == true) }
    }
    static func setEnabled(_ enabled: Bool, defaults: UserDefaults) {
        defaults.set(enabled, forKey: enabledKey)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("deletion.skip.") {
            defaults.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }
    static func reset(_ defaults: UserDefaults) { setEnabled(true, defaults: defaults) }
}


/// Disclosure content keeps its identity throughout interrupted transitions.
struct MultiDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @State private var expanded = false
    @FocusState private var headerFocused: Bool
    @FocusState private var bodyFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if expanded && bodyFocused { headerFocused = true }
                withAnimation(reduceMotion || MultiMotion.keyboard ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                Label(title, systemImage: expanded ? "chevron.down" : "chevron.right")
            }.buttonStyle(.plain).focused($headerFocused)
                .accessibilityValue(expanded ? "expanded" : "collapsed")
            content().fixedSize(horizontal: false, vertical: true)
                .frame(height: expanded ? nil : 0, alignment: .top).clipped()
                .opacity(expanded ? 1 : 0).disabled(!expanded)
                .accessibilityHidden(!expanded).focused($bodyFocused)
        }
    }
}


/// A native checkbox whose checked state always means confirmation is enabled.
@MainActor final class MultiDeletionCheckbox: NSButton {
    private let defaults: UserDefaults
    init(defaults: UserDefaults, russian: Bool) {
        self.defaults = defaults
        super.init(frame: .zero)
        setButtonType(.switch)
        title = russian ? "спрашивать перед удалением" : "ask before deleting"
        font = .systemFont(ofSize: 12)
        target = self; action = #selector(changedValue)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: MultiDeletionConfirmation.changed, object: nil)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func refresh() { state = MultiDeletionConfirmation.isEnabled(defaults) ? .on : .off }
    @objc private func changedValue() { MultiDeletionConfirmation.setEnabled(state == .on, defaults: defaults) }
}

struct MultiDeletionPreference: NSViewRepresentable {
    let defaults: UserDefaults
    let russian: Bool
    func makeNSView(context: Context) -> MultiDeletionCheckbox { MultiDeletionCheckbox(defaults: defaults, russian: russian) }
    func updateNSView(_ view: MultiDeletionCheckbox, context: Context) {
        view.title = russian ? "спрашивать перед удалением" : "ask before deleting"
        view.state = MultiDeletionConfirmation.isEnabled(defaults) ? .on : .off
    }
}
