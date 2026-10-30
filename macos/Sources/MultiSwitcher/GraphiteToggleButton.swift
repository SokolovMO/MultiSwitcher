import AppKit
import Observation
import SwiftUI

@Observable @MainActor
private final class GraphiteToggleState {
    var title = ""
    var isOn = false
    var isEnabled = true
    var font = NSFont.systemFont(ofSize: 12)
    var tint = DesignPalette.on
    @ObservationIgnored var change: (Bool) -> Void = { _ in }
}

@MainActor
private struct GraphiteToggleRow: View {
    let model: GraphiteToggleState

    var body: some View {
        // Read here so Observation invalidates the row when AppKit reflects a
        // setting. A read only inside Binding.get can bypass body tracking.
        let value = model.isOn
        Toggle(isOn: Binding(get: { value }, set: { next in model.change(next) })) {
            Text(model.title)
                .font(Font(model.font))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Color(nsColor: model.tint))
            .disabled(!model.isEnabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Retains the settings controller's NSButton target/action contract while the
/// same native SwiftUI switch used by MultiShift owns drawing, input and motion.
@MainActor
final class GraphiteToggleButton: NSButton {
    private let model = GraphiteToggleState()
    private var hosting: NSHostingView<GraphiteToggleRow>?

    override init(frame: NSRect) {
        super.init(frame: frame)
        installSwitch()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installSwitch()
    }

    private func installSwitch() {
        font = .systemFont(ofSize: 12)
        isBordered = false
        setAccessibilityElement(false)
        model.title = title
        model.isOn = state == .on
        model.isEnabled = isEnabled
        model.change = { [weak self] value in self?.commit(value) }
        let host = NSHostingView(rootView: GraphiteToggleRow(model: model))
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        hosting = host
    }

    override var title: String {
        didSet { model.title = title; invalidateIntrinsicContentSize() }
    }
    override var state: NSControl.StateValue {
        didSet { model.isOn = state == .on }
    }
    override var isEnabled: Bool {
        didSet { model.isEnabled = isEnabled }
    }
    override var font: NSFont? {
        didSet {
            model.font = font ?? .systemFont(ofSize: 12)
            invalidateIntrinsicContentSize()
        }
    }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var intrinsicContentSize: NSSize {
        let labelWidth = (title as NSString).size(withAttributes: [.font: model.font]).width
        return NSSize(width: ceil(labelWidth) + 60, height: 28)
    }
    override func sizeToFit() { setFrameSize(intrinsicContentSize) }
    override func layout() {
        super.layout()
        hosting?.frame = bounds
    }
    func refreshAppearance() { model.tint = DesignPalette.on }
    override func draw(_ dirtyRect: NSRect) {}
    // The embedded native control owns keyboard focus and accessibility.
    override var acceptsFirstResponder: Bool { false }

    override func performClick(_ sender: Any?) { commit(state != .on) }

    private func commit(_ value: Bool) {
        guard isEnabled, value != (state == .on) else { return }
        state = value ? .on : .off
        _ = sendAction(action, to: target)
        // A handler can reject or normalize the change (for example, a permission
        // request). Keep the native view consistent with the resulting NSButton state.
        model.isOn = state == .on
    }
}
