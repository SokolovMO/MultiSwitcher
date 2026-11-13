import AppKit

// Only business-service adapters are fixtures. The state store, menu controller,
// rows, native popover and permanent renderer under test are production sources.
enum L10n { static let languageCode = "ru" }
@MainActor final class SettingsManager {
    static let shared = SettingsManager()
    var autoSwitchEnabled = true
}
@MainActor enum DesignPalette { static var reducedMotion: Bool { MultiMotion.reduced } }
@MainActor enum DesignIcon {
    static func application(dark: Bool, size: CGFloat) -> NSImage { MultiBrandIcon.switcher }
}
extension Notification.Name { static let multiswitcherThemeChanged = Self("multiswitcher.theme.changed") }

@main struct LayoutStateChecks {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        var sourceID = "russian"
        var sources = [LayoutPresentationSnapshot.Source(id: "russian", name: "русская", language: "ru"),
                       .init(id: "us", name: "U.S.", language: "en"),
                       .init(id: "british", name: "British", language: "en")]
        let state = LayoutPresentationState {
            LayoutPresentationSnapshot(selectedID: sourceID, sources: sources, language: sources.first { $0.id == sourceID }?.language)
        }
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        let brand = MultiBrandIcon.switcher.tiffRepresentation!
        let controller = StatusPopoverController(behavior: .applicationDefined)
        let root = NSMenu(); let layout = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        layout.tag = 740; layout.submenu = NSMenu(); root.addItem(layout)
        controller.menuProvider = {
            let snapshot = state.snapshot
            layout.title = "раскладка: " + snapshot.badge
            layout.submenu!.removeAllItems()
            for source in snapshot.sources {
                let row = NSMenuItem(title: source.badge + " " + source.name, action: nil, keyEquivalent: "")
                row.representedObject = source.id; row.state = source.id == snapshot.selectedID ? .on : .off
                layout.submenu!.addItem(row)
            }
            return root
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button!.title = "ui check"
        Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(200))
        controller.toggle(near: item.button!)
        try? await Task.sleep(for: .milliseconds(200))
        check(controller.reviewShown, "native test popover must be open before live state changes")
        check(controller.reviewRows[0].title == "раскладка: AЯ", "root initially reflects selected source")
        sourceID = "us"; check(state.refresh(), "selected source changes state"); controller.refresh()
        check(controller.reviewRows[0].title == "раскладка: AZ", "open root updates without reopening")
        controller.openFirstSubmenuForReview()
        check(controller.reviewRows.filter(\.selected).count == 1, "submenu has one selected source")
        sourceID = "british"; check(state.refresh(), "same badge but different source ID must update"); controller.refresh()
        check(controller.reviewRows.first(where: \.selected)?.title == "AZ British", "open submenu updates same-language checkmark")
        sourceID = "russian"; state.refresh(); controller.refresh()
        check(controller.reviewRows.first(where: \.selected)?.title == "AЯ русская", "open submenu updates to Russian")
        sources.removeLast(); state.refresh(); controller.refresh()
        check(controller.reviewRows.count == 3, "enabled-source change updates open submenu and keeps back row")
        check(brand == MultiBrandIcon.switcher.tiffRepresentation!, "permanent brand is unchanged by input source updates")
        check(!state.refresh(), "unchanged state is deduplicated")
        controller.close(); NSStatusBar.system.removeStatusItem(item)
        print("LayoutStateChecks: \(checks) PASS (open root, submenu, same-language IDs, source removal, brand)")
        app.terminate(nil)
        }
        app.run()
    }
}
