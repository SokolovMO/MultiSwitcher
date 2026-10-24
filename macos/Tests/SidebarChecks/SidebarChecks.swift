import AppKit

@main struct SidebarChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        // Wide and tall symbols must retain proportions, including during collapse.
        for size in [NSSize(width: 24, height: 12), NSSize(width: 10, height: 20), NSSize(width: 16, height: 16)] {
            let rect = MultiDesign.symbolRect(size: size, center: NSPoint(x: 18, y: 16))
            check(abs(rect.width / rect.height - size.width / size.height) < 0.001, "symbol was distorted")
            check(abs(rect.midX - 18) < 0.001 && abs(rect.midY - 16) < 0.001, "symbol moved")
            check(rect.minX >= 9 && rect.maxX <= 27, "compact icon slot overflow")
        }
        let host = MultiSidebarHost(detail: NSView())
        host.configure(appName: "multiswitcher", items: (0..<7).map {
            MultiNavigationItem(id: String($0), title: "navigation \($0)", symbol: "gearshape.2")
        }, selected: "0")
        let window = MultiBoundedWindow(contentRect: NSRect(x: 120, y: 120, width: 860, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        MultiWindowPolicy.configure(window, minimum: MultiInterfaceMetrics.switcherMinimum, maximum: MultiInterfaceMetrics.switcherMaximum)
        check(window.contentMaxSize.width <= 1120 && window.contentMaxSize.height <= 800, "missing useful maximum")
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        check(window.contentMaxSize.width <= 1120 && window.contentMaxSize.height <= 800, "hosting reset useful maximum")
        window.contentMinSize = .zero; window.minSize = .zero
        check(window.contentMinSize == MultiInterfaceMetrics.switcherMinimum, "hosting reset useful minimum")
        window.setContentSize(NSSize(width: 3000, height: 2000))
        MultiWindowPolicy.configure(window, minimum: MultiInterfaceMetrics.switcherMinimum, maximum: MultiInterfaceMetrics.switcherMaximum)
        check(window.contentRect(forFrameRect: window.frame).width <= 1120, "oversized saved width not clamped")
        check(window.contentRect(forFrameRect: window.frame).height <= 800, "oversized saved height not clamped")
        let zoom = MultiWindowPolicy.zoomFrame(window, ideal: MultiInterfaceMetrics.switcherDefault)
        check(zoom.width <= window.frameRect(forContentRect: NSRect(origin: .zero, size: MultiInterfaceMetrics.switcherDefault)).width, "zoom exceeds useful width")
        let boundedFrame = MultiWindowPolicy.resizeFrameSize(window, proposed: NSSize(width: 5000, height: 5000),
            minimum: MultiInterfaceMetrics.switcherMinimum, maximum: MultiInterfaceMetrics.switcherMaximum)
        let boundedContent = window.contentRect(forFrameRect: NSRect(origin: .zero, size: boundedFrame)).size
        check(boundedContent.width <= 1120, "native resize delegate width is unbounded")
        check(boundedContent.height <= 800, "native resize delegate height is unbounded")
        window.makeKeyAndOrderFront(nil)
        Task { @MainActor in
            window.setContentSize(NSSize(width: 860, height: 600))
            let expanded = window.frame
            let contentWidth = host.detail.frame.width
            host.setCollapsed(true, animated: false)
            check(abs(window.frame.width - expanded.width + 148) < 1, "collapse must shrink the outer window by 148 pt")
            check(abs(host.detail.frame.width - contentWidth) < 1, "collapse must preserve detail width")
            check(abs(window.contentMinSize.width - 572) < 1, "compact minimum must account for the narrower rail")
            check(abs(window.contentMaxSize.width - 852) < 1, "compact maximum must account for the narrower rail")
            host.setCollapsed(false, animated: false)
            check(abs(window.frame.width - expanded.width) < 1, "expand must restore the previous width")
            for _ in 0..<20 {
                host.setCollapsed(true, animated: false)
                host.setCollapsed(false, animated: false)
                check(abs(window.frame.width - expanded.width) < 1, "collapse cycles must not accumulate width drift")
            }
            host.setCollapsed(true, animated: false)
            window.setContentSize(NSSize(width: 740, height: 600))
            host.setCollapsed(false, animated: false)
            check(abs(window.contentRect(forFrameRect: window.frame).width - 888) < 1, "manual compact resize updates the expanded width")
            window.setContentSize(NSSize(width: 860, height: 600))
            func pause() async { try? await Task.sleep(for: .milliseconds(18)) }
            for scale in [CGFloat(1), 2] {
                host.wantsLayer = true; host.layer?.contentsScale = scale
                for size in [NSSize(width: 700, height: 480), NSSize(width: 860, height: 600), NSSize(width: 1200, height: 760), NSSize(width: 620, height: 420)] {
                    window.setContentSize(size)
                    for collapsed in [true, false] {
                        host.setCollapsed(collapsed)
                        for _ in 0..<18 {
                            await pause()
                            check(host.geometryIsValid(), "navigation clipped during resize or collapse")
                        }
                        check(!host.isAnimating, "animation timer did not stop")
                    }
                }
            }
            window.setContentSize(NSSize(width: 860, height: 600))
            for index in 0..<40 { host.setCollapsed(index % 2 == 0); await pause(); check(host.geometryIsValid(), "rapid reversal clipped") }
            host.setCollapsed(false)
            try? await Task.sleep(for: .milliseconds(350))
            check(host.progress == 1 && !host.isAnimating, "interrupted animation did not settle")
            check(host.reviewArrow(), "keyboard navigation failed")
            host.reduceMotionOverride = true; host.setCollapsed(true)
            check(host.progress == 0 && !host.isAnimating, "reduced motion still animated")
            print("SidebarChecks: \(checks) PASS (1x/2x rendering, 4 sizes, 40 reversals)")
            app.terminate(nil)
        }
        app.run()
    }
}
