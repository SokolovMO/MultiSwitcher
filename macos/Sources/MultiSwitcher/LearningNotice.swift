import AppKit
import MultiSwitcherCore

/// Short nonactivating feedback anchored beside the menu-bar status item.
@MainActor
final class LearningNotice {
    var reviewWindow: NSWindow { panel }
    private let panel: NSPanel
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private var hideTimer: Timer?
    private let width: CGFloat = 340

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 82),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isExcludedFromWindowsMenu = true

        let backdrop = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: 82))
        backdrop.material = .popover
        backdrop.state = .active
        backdrop.blendingMode = .behindWindow
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = MultiInterfaceMetrics.Radius.lg
        backdrop.layer?.masksToBounds = true
        panel.contentView = backdrop

        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = NSFont.systemFont(ofSize: 11)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.preferredMaxLayoutWidth = width - 32
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [titleLabel, bodyLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -12),
        ])
    }

    func show(title: String, body: String, near button: NSStatusBarButton?) {
        titleLabel.stringValue = InterfaceText.chrome(title)
        bodyLabel.stringValue = body
        panel.layoutIfNeeded()
        let height = max(72, min(panel.contentView?.fittingSize.height ?? 82, 150))
        panel.setContentSize(NSSize(width: width, height: height))
        position(near: button, height: height)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = DesignPalette.reducedMotion ? 0 : 0.12; panel.animator().alphaValue = 1 }
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func position(near button: NSStatusBarButton?, height: CGFloat) {
        guard let button, let window = button.window else {
            let frame = NSScreen.main?.visibleFrame ?? .zero
            panel.setFrameOrigin(NSPoint(x: frame.midX - width / 2, y: frame.maxY - height - 12))
            return
        }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(anchor.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
        let y = max(visible.minY + 8, anchor.minY - height - 10)
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = DesignPalette.reducedMotion ? 0 : 0.15; panel.animator().alphaValue = 0 },
                                             completionHandler: { [weak self] in Task { @MainActor in self?.panel.orderOut(nil) } })
    }
}
