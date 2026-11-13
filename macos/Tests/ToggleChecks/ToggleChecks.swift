import AppKit

@MainActor private final class ToggleTarget: NSObject {
    var calls = 0
    var observedState = false
    var rejectNext = false
    weak var status: NSTextField?
    @objc func changed(_ sender: NSButton) {
        calls += 1
        observedState = sender.state == .on
        if rejectNext { sender.state = .off; rejectNext = false }
        status?.stringValue = "actions: \(calls), value: \(sender.state.rawValue)"
    }
}

@main struct ToggleChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 140, y: 160, width: 520, height: 180),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "native toggle checks"
        let target = ToggleTarget()
        let toggle = GraphiteToggleButton(checkboxWithTitle: "test option", target: target,
                                         action: #selector(ToggleTarget.changed(_:)))
        toggle.frame = NSRect(x: 20, y: 104, width: 480, height: 28)
        window.contentView!.addSubview(toggle)
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        window.contentView!.layoutSubtreeIfNeeded()
        var checks = 0
        func nativeValue(in view: NSView) -> Bool? {
            if let value = view.accessibilityValue() as? NSNumber { return value.boolValue }
            for child in view.subviews {
                if let value = nativeValue(in: child) { return value }
            }
            return nil
        }
        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        func check(_ condition: Bool, _ message: String) {
            guard condition else { fputs("ToggleChecks FAIL: \(message)\n", stderr); exit(1) }
            checks += 1
        }
        // Follow the real hit-test path at the right-hand visual switch, not the
        // checkbox cell's unrelated left-hand label/image region.
        for width in [CGFloat(260), 480, 640] {
            toggle.frame.size.width = width
            toggle.layoutSubtreeIfNeeded()
            let local = NSPoint(x: width - 15, y: toggle.bounds.midY)
            let point = toggle.convert(local, to: toggle.superview)
            let receiver = toggle.hitTest(point)
            let event = NSEvent.mouseEvent(with: .leftMouseDown,
                location: toggle.convert(local, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            let tracks = receiver === toggle
                ? toggle.cell!.hitTest(for: event, in: toggle.bounds, of: toggle).contains(.trackableArea)
                : receiver?.isDescendant(of: toggle) == true
            check(tracks, "visible switch is outside the clickable input surface at width \(width)")
        }
        toggle.frame.size.width = 480
        toggle.state = .on
        settle()
        check(nativeValue(in: toggle.subviews[0]) == true, "native switch did not reflect programmatic on")
        toggle.state = .off
        settle()
        check(nativeValue(in: toggle.subviews[0]) == false, "native switch did not reflect programmatic off")
        toggle.state = .on
        check(target.calls == 0, "programmatic reflection must not send an action")
        toggle.performClick(nil)
        check(toggle.state == .off && target.calls == 1 && !target.observedState, "on-to-off action")
        toggle.performClick(nil)
        check(toggle.state == .on && target.calls == 2 && target.observedState, "off-to-on action")
        toggle.isEnabled = false
        toggle.performClick(nil)
        check(toggle.state == .on && target.calls == 2, "disabled toggle accepted input")
        toggle.isEnabled = true
        toggle.state = .off
        target.rejectNext = true
        toggle.performClick(nil)
        check(toggle.state == .off && target.calls == 3, "handler rejection was not reflected")
        for _ in 0..<100 { toggle.performClick(nil) }
        check(toggle.state == .off && target.calls == 103, "rapid toggles lost or duplicated actions")
        check(toggle.intrinsicContentSize.height == 28, "settings row geometry changed")
        print("ToggleChecks: \(checks) PASS (pointer targets, reflection, actions, disabled, rejection, 100 reversals)")
        if CommandLine.arguments.contains("--interactive") {
            toggle.state = .off
            target.calls = 0
            let status = NSTextField(labelWithString: "actions: 0, value: 0")
            status.frame = NSRect(x: 20, y: 12, width: 480, height: 20)
            target.status = status
            window.contentView!.addSubview(status)
            let disabled = GraphiteToggleButton(checkboxWithTitle: "disabled option", target: nil, action: nil)
            disabled.frame = NSRect(x: 20, y: 52, width: 480, height: 28)
            disabled.state = .on; disabled.isEnabled = false
            window.contentView!.addSubview(disabled)
            let menu = NSMenu(); let item = NSMenuItem(); let submenu = NSMenu()
            submenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.submenu = submenu; menu.addItem(item); app.mainMenu = menu
            withExtendedLifetime(target) { app.run() }
        }
    }
}
