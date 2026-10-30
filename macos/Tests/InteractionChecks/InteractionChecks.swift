import AppKit
import MultiSwitcherCore

@main struct InteractionChecks {
    @MainActor static func main() {
        precondition(MultiAuditEnvironment.root != nil, "isolated data root required")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func check(_ value: Bool, _ message: String) { precondition(value, message) }
        let store = ProfileStore.shared
        try! store.update { profile in
            profile.learning = ["alpha", "beta", "gamma"].map { LearningEntry(word: $0, cancellationCount: 1, origin: .local) }
        }
        let editor = LearningListEditor()
        let root = editor.makeContainer(frame: NSRect(x: 0, y: 0, width: 550, height: 350))
        let window = MultiBoundedWindow(contentRect: root.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = root; window.makeKeyAndOrderFront(nil)
        let table = all(root).compactMap { $0 as? NSTableView }.first!
        let defaults = MultiAuditEnvironment.defaults(appID: "com.multiswitcher.app")
        MultiDeletionConfirmation.reset(defaults)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let original = store.current.learning[1].word
        for _ in 0..<100 {
            NotificationCenter.default.post(name: .multiSwitcherLearningDidChange, object: nil)
            check(table.selectedRow == 1, "refresh discarded selection")
        }
        Task { @MainActor in
            func pause() async { try? await Task.sleep(for: .milliseconds(50)) }
            func key(_ code: UInt16, repeat repeated: Bool = false) -> NSEvent {
                NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: repeated, keyCode: code)!
            }
            table.keyDown(with: key(51, repeat: true))
            check(window.attachedSheet == nil, "held delete opened a sheet")
            table.keyDown(with: key(51))
            await pause()
            check(window.attachedSheet != nil, "delete did not request confirmation")
            if let sheet = window.attachedSheet { app.endSheet(sheet, returnCode: NSApplication.ModalResponse.alertSecondButtonReturn.rawValue) }
            await pause()
            check(store.current.learning.count == 3, "cancel deleted data")
            MultiDeletionConfirmation.setEnabled(false, defaults: defaults)
            table.keyDown(with: key(117))
            await pause()
            check(store.current.learning.count == 2, "forward delete did not remove entry")
            check(!store.current.learning.contains { $0.word == original }, "deleted the wrong identity")
            check(table.selectedRow == 1, "next row was not selected")
            check(!MultiDeletionConfirmation.isEnabled(defaults), "unchecked preference did not disable confirmation")
            // A failed write must propagate and preserve the cached model.
            let expected = store.current
            try! FileManager.default.removeItem(at: store.profileURL)
            try! FileManager.default.createDirectory(at: store.profileURL, withIntermediateDirectories: false)
            do {
                _ = try SettingsManager.shared.forgetLearnedWord(expected.learning[0].word)
                preconditionFailure("save failure was swallowed")
            } catch { check(store.current == expected, "failed write changed the model") }
            try! FileManager.default.removeItem(at: store.profileURL)
            try! store.update { $0 = expected }
            let settings = SettingsWindowController()
            settings.showWindow()
            await pause()
            let settingsWindow = app.windows.first { $0 !== window && $0.isVisible }!
            let navigation = all(settingsWindow.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "оформление" || $0.title == "appearance" }!
            navigation.performClick(nil)
            try? await Task.sleep(for: .milliseconds(300))
            let views = all(settingsWindow.contentView!)
            let themes = views.compactMap { $0 as? NSButton }.filter { String(describing: type(of: $0)) == "SettingsThemeChoice" }
            check(themes.count == 3, "missing theme controls")
            for button in themes {
                for fraction in [CGFloat(0.1), 0.5, 0.9] {
                    let point = NSPoint(x: button.bounds.width * fraction, y: button.bounds.height * 0.65)
                    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: button.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: settingsWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    check(button.cell!.hitTest(for: event, in: button.bounds, of: button).contains(.trackableArea), "visible theme card does not accept pointer tracking")
                }
            }
            for index in 0..<100 {
                themes[index % 3].performClick(nil)
                await pause()
                check(settingsWindow.attachedSheet == nil, "theme left a blocking sheet")
                check(themes[index % 3].isEnabled, "theme control became disabled")
                table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                check(table.selectedRow == 0, "table stopped responding after theme")
            }
            let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 140, height: 24))
            root.addSubview(field); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(field)
            check(window.firstResponder is NSTextView, "field did not begin native editing")
            _ = window.performKeyEquivalent(with: key(53))
            check(!(window.firstResponder is NSTextView) && window.isVisible, "first Escape failed to end editing")
            _ = window.performKeyEquivalent(with: key(53))
            check(!window.isVisible, "second Escape failed to close the window")
            MultiDeletionConfirmation.reset(defaults)
            check(MultiDeletionConfirmation.isEnabled(defaults), "reset did not restore confirmation")
            print("InteractionChecks PASS: 100 refreshes, cancellation, both delete keys, repeat, save failure, 100 theme actions")
            app.terminate(nil)
        }
        app.run()
    }
}
