import AppKit
import MultiSwitcherCore

@main struct InteractionChecks {
    @MainActor static func main() {
        precondition(MultiAuditEnvironment.root != nil, "isolated data root required")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func check(_ value: Bool, _ message: String) { precondition(value, message) }
        func luminance(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        for identifier in ["SUStatus", "SUUpdateAlert", "SUUpdatePermissionPrompt"] {
            let updaterWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
                                         styleMask: [.titled], backing: .buffered, defer: false)
            updaterWindow.identifier = NSUserInterfaceItemIdentifier(identifier)
            let button = NSButton(title: "Установить обновление", target: nil, action: nil)
            button.bezelStyle = .rounded
            button.keyEquivalent = "\r"
            let originalCell = button.cell
            updaterWindow.contentView!.addSubview(button)
            DesignStyler.apply(button)
            check(button.cell === originalCell && button.keyEquivalent == "\r" && button.isEnabled,
                  "Sparkle control behavior was replaced")
            check(button.contentTintColor == nil && button.bezelColor == nil,
                  "Sparkle update controls were recolored by the application")
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                let text = DesignPalette.secondary.usingColorSpace(.sRGB)!
                for background in [DesignPalette.window, DesignPalette.inset, DesignPalette.selected] {
                    let color = background.usingColorSpace(.sRGB)!
                    let foregroundLuma = 0.2126 * luminance(text.redComponent)
                        + 0.7152 * luminance(text.greenComponent) + 0.0722 * luminance(text.blueComponent)
                    let backgroundLuma = 0.2126 * luminance(color.redComponent)
                        + 0.7152 * luminance(color.greenComponent) + 0.0722 * luminance(color.blueComponent)
                    let ratio = (max(foregroundLuma, backgroundLuma) + 0.05)
                        / (min(foregroundLuma, backgroundLuma) + 0.05)
                    check(ratio >= 4.5, "secondary text lacks contrast on a settings/selection surface")
                }
            }
        }
        let store = ProfileStore.shared
        try! store.update { profile in
            profile.learning = ["alpha", "beta", "gamma"].map { LearningEntry(word: $0, cancellationCount: 1, origin: .local) }
        }
        let editor = LearningListEditor()
        let root = editor.makeContainer(frame: NSRect(x: 0, y: 0, width: 550, height: 350))
        let window = MultiBoundedWindow(contentRect: root.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = root; window.makeKeyAndOrderFront(nil)
        let search = all(root).compactMap { $0 as? GraphiteSearchField }.first!
        check(search.isEditable && search.isSelectable, "search cell does not allow editing or selection")
        check(window.makeFirstResponder(search), "search field refuses keyboard focus")
        check(search.currentEditor() != nil, "search field did not start editing")
        let searchEditor = search.currentEditor() as! NSTextView
        searchEditor.insertText("alpha", replacementRange: NSRange(location: NSNotFound, length: 0))
        check(search.stringValue == "alpha", "search field did not accept typed text")
        let typedText = search.convert(window.convertFromScreen(searchEditor.firstRect(
            forCharacterRange: NSRange(location: 0, length: 5), actualRange: nil)), from: nil)
        let searchIcon = (search.cell as! NSSearchFieldCell).searchButtonRect(forBounds: search.bounds)
        check(!typedText.intersects(searchIcon) && typedText.minX >= searchIcon.maxX,
              "search editor text overlaps the magnifier")
        check(search.bounds.contains(typedText), "search editor text leaves the field bounds")
        searchEditor.selectAll(nil)
        searchEditor.insertText("", replacementRange: NSRange(location: NSNotFound, length: 0))
        let ruleEditor = UserRuleEditor()
        let ruleRoot = ruleEditor.makeContainer(frame: NSRect(x: 0, y: 0, width: 550, height: 350))
        ruleRoot.layoutSubtreeIfNeeded()
        let ruleTable = all(ruleRoot).compactMap { $0 as? NSTableView }.first!
        let ruleScroll = ruleTable.enclosingScrollView!
        ruleScroll.tile()
        let manualWidth = ruleTable.tableColumns[0].width + 20
        ruleTable.tableColumns[0].width = manualWidth
        ruleScroll.tile()
        check(abs(ruleTable.tableColumns[0].width - manualWidth) < 0.1,
              "a routine tile discarded a manually resized Rules column")
        let table = all(root).compactMap { $0 as? NSTableView }.first!
        check(table.allowsMultipleSelection, "learning list does not allow multiple selection")
        let defaults = MultiAuditEnvironment.defaults(appID: "com.multiswitcher.app")
        MultiDeletionConfirmation.reset(defaults)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let original = store.current.learning[1].word
        for _ in 0..<100 {
            NotificationCenter.default.post(name: .multiSwitcherLearningDidChange, object: nil)
            check(table.selectedRow == 1, "refresh discarded selection")
        }
        // Graphite paints selection in the table background, outside native row views.
        table.displayIfNeeded()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        check(table.needsDisplay, "selection change did not invalidate the custom highlight")
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        Task { @MainActor in
            func pause() async { try? await Task.sleep(for: .milliseconds(50)) }
            @MainActor func key(_ code: UInt16, repeat repeated: Bool = false, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
                let character = code == 125 ? "\u{F701}" : code == 126 ? "\u{F700}" : ""
                return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: repeated, keyCode: code)!
            }
            window.makeFirstResponder(table)
            table.keyDown(with: key(125))
            check(table.selectedRow == 2, "Down did not move to the next word")
            table.keyDown(with: key(126))
            check(table.selectedRow == 1, "Up did not move to the previous word")
            table.keyDown(with: key(125, modifiers: .shift))
            check(table.selectedRowIndexes == IndexSet([1, 2]), "Shift+Down did not extend selection")
            table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
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
            // Clicking Forget must leave the next row ready for keyboard selection/deletion.
            let forget = all(root).compactMap { $0 as? NSButton }.first { $0.title == L10n.learningForget }!
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            window.makeFirstResponder(forget)
            forget.performClick(nil)
            await pause()
            check(store.current.learning.count == 1, "Forget button did not remove entry")
            check(table.selectedRow == 0, "Forget button did not select the next row")
            check(window.firstResponder === table, "Forget button did not return keyboard focus to the next row")
            table.keyDown(with: key(51))
            await pause()
            check(store.current.learning.isEmpty, "repeated deletion did not remove the next row")
            check(table.selectedRow == -1 && !forget.isEnabled, "empty list retained an actionable selection")
            try! store.update { profile in
                profile.learning = ["delta", "epsilon"].map { LearningEntry(word: $0, cancellationCount: 1, origin: .local) }
            }
            editor.reloadFromStore()
            MultiDeletionConfirmation.setEnabled(true, defaults: defaults)
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            for remaining in [1, 0] {
                window.makeFirstResponder(forget)
                forget.performClick(nil)
                await pause()
                check(window.attachedSheet != nil, "repeated Forget did not request confirmation")
                if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
                try? await Task.sleep(for: .milliseconds(250))
                check(store.current.learning.count == remaining, "confirmed Forget did not remove the selected entry")
                check(window.firstResponder === table, "confirmation did not return focus to the table")
                check(table.selectedRow == (remaining == 0 ? -1 : 0), "confirmed Forget lost the next selection")
            }
            MultiDeletionConfirmation.setEnabled(false, defaults: defaults)
            try! store.update { profile in
                profile.learning = ["a", "b", "c", "d", "e"].map { LearningEntry(word: $0, cancellationCount: 1, origin: .local) }
            }
            editor.reloadFromStore()
            table.selectRowIndexes(IndexSet([1, 3]), byExtendingSelection: false)
            NotificationCenter.default.post(name: .multiSwitcherLearningDidChange, object: nil)
            check(table.selectedRowIndexes == IndexSet([1, 3]), "refresh collapsed multiple selection")
            forget.performClick(nil)
            await pause()
            check(Set(store.current.learning.map(\.word)) == Set(["a", "c", "e"]), "bulk Forget removed the wrong words")
            check(table.selectedRow == 1, "bulk Forget did not select the next word")
            table.selectAll(nil)
            check(table.selectedRowIndexes.count == 3, "Select All did not select all visible words")
            table.keyDown(with: key(51))
            await pause()
            check(store.current.learning.isEmpty, "Delete did not forget all selected words")
            try! store.update { profile in
                profile.learning = ["one", "two"].map { LearningEntry(word: $0, cancellationCount: 1, origin: .local) }
            }
            editor.reloadFromStore()
            MultiDeletionConfirmation.setEnabled(true, defaults: defaults)
            table.selectAll(nil)
            forget.performClick(nil)
            await pause()
            check(window.attachedSheet != nil, "bulk Forget did not open confirmation")
            if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertSecondButtonReturn) }
            try? await Task.sleep(for: .milliseconds(250))
            check(store.current.learning.count == 2 && table.selectedRowIndexes.count == 2, "bulk cancellation lost words or selection")
            forget.performClick(nil)
            await pause()
            if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
            try? await Task.sleep(for: .milliseconds(250))
            check(store.current.learning.isEmpty && window.attachedSheet == nil, "bulk confirmation did not remove the entire selection at once")
            MultiDeletionConfirmation.setEnabled(false, defaults: defaults)
            try! store.update { profile in
                profile.learning = ["remaining", "second"].map { LearningEntry(word: $0, cancellationCount: 1, origin: .local) }
            }
            editor.reloadFromStore()
            // A failed write must propagate and preserve the cached model.
            let expected = store.current
            try! FileManager.default.removeItem(at: store.profileURL)
            try! FileManager.default.createDirectory(at: store.profileURL, withIntermediateDirectories: false)
            do {
                _ = try SettingsManager.shared.forgetLearnedWords(expected.learning.map(\.word))
                preconditionFailure("save failure was swallowed")
            } catch { check(store.current == expected, "failed write changed the model") }
            try! FileManager.default.removeItem(at: store.profileURL)
            try! store.update { $0 = expected }
            let settings = SettingsWindowController()
            settings.showWindow()
            await pause()
            let settingsWindow = app.windows.first { $0 !== window && $0.isVisible }!
            let about = all(settingsWindow.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "о приложении" || $0.title == "about" }!
            about.performClick(nil)
            try? await Task.sleep(for: .milliseconds(300))
            let disclosure = all(settingsWindow.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "техническая информация" || $0.title == "technical information" }!
            var ancestor = disclosure.superview
            while let view = ancestor, String(describing: type(of: view)) != "SettingsCardBackground" { ancestor = view.superview }
            let card = ancestor!
            let collapsedHeight = card.frame.height
            let cardTop = card.convert(card.bounds, to: settingsWindow.contentView).maxY
            @MainActor func toggleDisclosure() {
                // performClick holds the native pressed highlight and delays early frames.
                _ = app.sendAction(disclosure.action!, to: disclosure.target, from: disclosure)
            }
            @MainActor func sampleDisclosure() async -> [CGFloat] {
                var heights: [CGFloat] = []
                for _ in 0..<24 {
                    heights.append(card.frame.height)
                    check(abs(card.convert(card.bounds, to: settingsWindow.contentView).maxY - cardTop) < 2,
                          "disclosure moved the top of its card")
                    try? await Task.sleep(for: .milliseconds(12))
                }
                return heights
            }
            toggleDisclosure()
            let opening = await sampleDisclosure()
            let expandedHeight = card.frame.height
            check(expandedHeight > collapsedHeight + 30, "technical information did not expand")
            func intermediateCount(_ heights: [CGFloat]) -> Int {
                Set(heights.filter { $0 > collapsedHeight + 1 && $0 < expandedHeight - 1 }.map { Int($0.rounded()) }).count
            }
            check(intermediateCount(opening) >= 3, "disclosure jumped open instead of animating")
            toggleDisclosure()
            let closing = await sampleDisclosure()
            check(intermediateCount(closing) >= 3, "disclosure jumped closed instead of animating")
            check(abs(card.frame.height - collapsedHeight) < 1, "disclosure did not return to its collapsed height")
            toggleDisclosure()
            try? await Task.sleep(for: .milliseconds(45))
            let interruptedHeight = card.frame.height
            toggleDisclosure()
            check(abs(card.frame.height - interruptedHeight) < 1, "reversing disclosure restarted its height")
            _ = await sampleDisclosure()
            check(abs(card.frame.height - collapsedHeight) < 1, "interrupted disclosure did not settle")
            toggleDisclosure()
            _ = await sampleDisclosure()
            let originalSize = settingsWindow.contentView!.frame.size
            for width in [CGFloat(737), 897] {
                settingsWindow.setContentSize(NSSize(width: width, height: originalSize.height))
                try? await Task.sleep(for: .milliseconds(100))
                let reveal = (disclosure.superview as! NSStackView).arrangedSubviews.last!
                check(abs(reveal.frame.height - ceil(reveal.subviews[0].fittingSize.height)) < 1,
                      "expanded disclosure clipped text after window resize")
            }
            settingsWindow.setContentSize(originalSize)
            toggleDisclosure()
            try? await Task.sleep(for: .milliseconds(250))
            let learning = all(settingsWindow.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "обучение" || $0.title == "learning" }!
            learning.performClick(nil)
            try? await Task.sleep(for: .milliseconds(300))
            check(settingsWindow.firstResponder is NSTableView, "opening Learning did not focus its word list")
            if let focused = settingsWindow.firstResponder as? NSTableView {
                check(focused.selectionHighlightStyle == .none,
                      "opening Learning did not apply graphite selection styling")
                check(focused.selectedRow == 0, "opening Learning did not select the first word")
                focused.keyDown(with: key(125))
                check(focused.selectedRow == 1, "Down did not work immediately after opening Learning")
            }
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
            print("InteractionChecks PASS: selection, bulk deletion, focus, disclosure opening/closing/reversal/resize, save failure, 100 refreshes and theme actions")
            app.terminate(nil)
        }
        app.run()
    }
}
