import AppKit
@main struct PopoverChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let page = MultiPopoverView()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 340, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = page; window.title = "menu regression check"
        page.onSize = { window.setContentSize($0) }
        page.configure(name: "menu regression check", status: "long text and navigation", icon: NSImage(size: NSSize(width: 34, height: 34)), enabled: true, toggle: {})
        var count = 0
        func check(_ test: Bool, _ message: String) { if !test { fatalError(message) }; count += 1 }
        let long = MultiPopoverItem(title: "очень длинная подпись действия полностью переносится на несколько строк", detail: "пауза · нужны разрешения для работы с клавиатурой", symbol: "circle")
        let root = [long, MultiPopoverItem(title: "обычная строка", symbol: "clock")]
        let footer = [MultiPopoverItem(title: "настройки…"), MultiPopoverItem(title: "справка"), MultiPopoverItem(title: "выход")]
        page.setItems(root, footer: footer)
        window.makeKeyAndOrderFront(nil)
        check(page.rowViews[0].height(for: 312) > 31, "long action must grow instead of truncate")
        check(page.rowViews[0].toolTip?.contains(long.title) == true, "full action accessibility and tooltip")
        check(page.reviewGeometry["headerTop"] as? CGFloat == 14, "canonical header top")
        check(page.reviewGeometry["iconTop"] as? CGFloat == 20, "canonical icon top")
        check(page.reviewGeometry["bodyTop"] as? CGFloat == 70, "canonical body top")
        check(page.reviewGeometry["rowWidthsValid"] as? Bool == true, "all rows inside viewport")
        window.makeFirstResponder(page.rowViews[0])
        let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125)!
        page.rowViews[0].keyDown(with: down)
        check(window.firstResponder === page.rowViews[1], "down arrow moves native focus")
        page.setItems(root, footer: footer)
        check(window.firstResponder === page.rowViews[1], "refresh preserves native focus")
        let dir = ProcessInfo.processInfo.environment["MULTI_POPOVER_CHECK_OUTPUT"] ?? NSTemporaryDirectory() + "multi-popover-check-output"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        MultiEcosystemProbe.capture(window, path: dir + "/long-text.png")
        Task { @MainActor in
            let size = window.frame.size; let base = page.bodyHeight
            let recorder = Process(); recorder.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            recorder.arguments = ["-x", "-v", "-V", "4", "-l", String(window.windowNumber), dir + "/submenu-transitions.mov"]
            try? recorder.run()
            for _ in 0..<20 {
                page.setItems([MultiPopoverItem(title: "назад"), MultiPopoverItem(title: "первый пункт")], footer: footer, animated: true, minimumBodyHeight: base)
                check(window.frame.size == size, "submenu keeps stable outer size")
                try? await Task.sleep(for: .milliseconds(25))
                page.setItems(root, footer: footer, animated: true)
                check(page.reviewGeometry["rowWidthsValid"] as? Bool == true, "rapid transition containment")
                try? await Task.sleep(for: .milliseconds(25))
            }
            try? await Task.sleep(for: .milliseconds(300))
            check(page.subviews.count == 4, "completed transitions remove old snapshots")
            check(page.subviews.filter { $0 is NSScrollView }.first?.alphaValue == 1, "no residual body opacity")
            let history = (0..<20).map { MultiPopoverItem(title: "готово", detail: "MiXeD File Name \($0).PNG", fileName: true) }
            page.setItems(history, footer: footer, maximumBodyHeight: 180)
            check(page.bodyHeight == 180, "history viewport is bounded")
            check(page.rowViews[0].toolTip?.contains("MiXeD") == true, "filename case preserved")
            let retained = page.rowViews[0]
            window.makeFirstResponder(retained)
            let scrolling = page.subviews.compactMap { $0 as? NSScrollView }.first!
            scrolling.contentView.scroll(to: NSPoint(x: 0, y: 100))
            page.setItems(history, footer: footer, maximumBodyHeight: 180)
            check(page.rowViews[0] === retained, "live refresh must retain operation row identity")
            check(window.firstResponder === retained, "live refresh must retain keyboard focus")
            check(scrolling.contentView.bounds.minY == 100, "live refresh must not reset history scroll")
            page.setItems(root, footer: footer)
            let beforeAnimation = page.bodyHeight
            page.setItems(history, footer: footer, animated: true, maximumBodyHeight: 250)
            check(page.isResizing, "history expansion uses one coordinated resize")
            try? await Task.sleep(for: .milliseconds(35))
            let intermediate = page.bodyHeight
            check(intermediate > beforeAnimation && intermediate < 250, "history has an intermediate height")
            page.setItems(history, footer: footer, maximumBodyHeight: 250)
            check(page.isResizing, "unrelated model refresh must not cancel resize")
            try? await Task.sleep(for: .milliseconds(230))
            check(!page.isResizing && page.bodyHeight == 250, "history reaches its exact final size")
            page.reduceMotionOverride = true
            page.setItems(root, footer: footer, animated: true)
            check(!page.isResizing, "reduce motion applies final geometry immediately")
            page.reduceMotionOverride = false
            let native = NSPopover(); native.behavior = .applicationDefined; native.animates = false
            let controller = NSViewController(); let nativePage = MultiPopoverView(); controller.view = nativePage; native.contentViewController = controller
            nativePage.onSize = { size in controller.preferredContentSize = size; native.contentSize = size }
            nativePage.configure(name: "native popover", status: "geometry regression", icon: NSImage(size: NSSize(width: 34, height: 34)), enabled: true, toggle: {})
            nativePage.setItems(root, footer: footer)
            native.show(relativeTo: NSRect(x: 100, y: 100, width: 1, height: 1), of: window.contentView!, preferredEdge: .maxY)
            try? await Task.sleep(for: .milliseconds(150))
            check(native.isShown, "native popup is visible")
            nativePage.setItems(history, footer: footer, maximumBodyHeight: 180)
            try? await Task.sleep(for: .milliseconds(150))
            check(abs(nativePage.bounds.height - native.contentSize.height) < 0.5, "native view and popup size agree after expansion")
            check(abs(nativePage.bounds.height - nativePage.bodyHeight - 199) < 0.5, "no extra top gap from double autoresizing")
            nativePage.setItems(root, footer: footer)
            try? await Task.sleep(for: .milliseconds(150))
            check(abs(nativePage.bounds.height - native.contentSize.height) < 0.5, "native collapse restores exact size")
            native.close()
            let result: [String: Any] = ["checks": count, "passed": true, "rapidCycles": 20, "geometry": page.reviewGeometry]
            try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: dir + "/results.json"))
            print("PopoverChecks: \(count) PASS")
            try? await Task.sleep(for: .seconds(3))
            app.terminate(nil)
        }
        app.run()
    }
}
