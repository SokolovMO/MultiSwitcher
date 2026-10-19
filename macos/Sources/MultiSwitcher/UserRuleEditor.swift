import AppKit
import MultiSwitcherCore
import UniformTypeIdentifiers

private final class RuleTableView: NSTableView {
    var onDeleteSelection: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Support both the forward-delete key on compact keyboards and the
        // dedicated Delete key. Keep the same confirmation path as the button.
        if event.keyCode == 51 || event.keyCode == 117 {
            onDeleteSelection?()
            return
        }
        super.keyDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        super.rightMouseDown(with: event)
    }
}

/// Searchable editor for local, imported, and learned rules.
@MainActor
final class UserRuleEditor: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private enum Column {
        static let pattern = NSUserInterfaceItemIdentifier("rules.pattern")
        static let behavior = NSUserInterfaceItemIdentifier("rules.behavior")
        static let replacement = NSUserInterfaceItemIdentifier("rules.replacement")
        static let source = NSUserInterfaceItemIdentifier("rules.source")
    }

    private let table = RuleTableView()
    private let searchField = NSSearchField()
    private var editButton: NSButton?
    private var deleteButton: NSButton?
    private var restorePuntoButton: NSButton?
    private var entries: [ProfileRule] = []
    private var visibleEntries: [ProfileRule] = []
    private weak var dialogReplacementField: NSTextField?
    var onRulesChanged: (() -> Void)?

    private let matchModes: [ProfileRuleMatch] = [.exact, .prefix, .contains, .regularExpression]
    private let actions: [ProfileRuleAction] = [.neverConvert, .alwaysConvert, .replace]

    func makeContainer(frame: NSRect) -> NSView {
        let root = NSView(frame: frame)
        searchField.frame = NSRect(x: 0, y: frame.height - 28, width: frame.width, height: 24)
        searchField.placeholderString = L10n.userRulesSearch
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        root.addSubview(searchField)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 76, width: frame.width, height: frame.height - 180))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let columnWidths: [CGFloat] = [frame.width * 0.28, frame.width * 0.28,
                                       frame.width * 0.18, frame.width * 0.26]
        addColumn(L10n.userRulesColumnPattern, identifier: Column.pattern, width: columnWidths[0])
        addColumn(L10n.userRulesColumnBehavior, identifier: Column.behavior, width: columnWidths[1])
        addColumn(L10n.userRulesColumnReplacement, identifier: Column.replacement, width: columnWidths[2])
        addColumn(L10n.userRulesColumnSource, identifier: Column.source, width: columnWidths[3])
        table.rowHeight = 34
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.usesAlternatingRowBackgroundColors = true
        table.gridStyleMask = [.solidHorizontalGridLineMask]
        table.gridColor = .separatorColor
        table.backgroundColor = .controlBackgroundColor
        table.selectionHighlightStyle = .regular
        table.allowsMultipleSelection = false
        table.onDeleteSelection = { [weak self] in self?.deleteTapped() }
        let rowMenu = NSMenu(title: L10n.userRulesSourceUser)
        let deleteItem = NSMenuItem(title: L10n.userRulesDelete, action: #selector(deleteTapped), keyEquivalent: "")
        deleteItem.target = self
        rowMenu.addItem(deleteItem)
        table.menu = rowMenu
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        root.addSubview(scroll)

        let hint = NSTextField(wrappingLabelWithString: L10n.userRulesHint)
        hint.frame = NSRect(x: 0, y: frame.height - 68, width: frame.width, height: 34)
        hint.font = SystemTypography.font(.footnote)
        hint.textColor = .secondaryLabelColor
        root.addSubview(hint)

        let buttons: [(String, Selector, String?, CGFloat)] = [
            (L10n.userRulesAdd, #selector(addTapped), "plus", 34),
            (L10n.userRulesEdit, #selector(editTapped), "pencil", 34),
            (L10n.userRulesDelete, #selector(deleteTapped), "trash", 34),
            (L10n.userRulesImport, #selector(importTapped), "square.and.arrow.down", 2),
            (L10n.userRulesExport, #selector(exportTapped), "square.and.arrow.up", 2),
            (L10n.userRulesRestorePunto, #selector(restorePuntoTapped), "arrow.uturn.backward", 2),
        ]
        var rowX: [CGFloat] = [0, 0]
        for (title, action, symbol, rowY) in buttons {
            let button = NSButton(title: title, target: self, action: action)
            let textWidth = ceil((title as NSString).size(withAttributes: [.font: SystemTypography.font(.body)]).width)
            let width = textWidth + (symbol == nil ? 20 : 40)
            let row = rowY == 34 ? 0 : 1
            let x = rowX[row]
            button.frame = NSRect(x: x, y: rowY, width: width, height: 30)
            button.bezelStyle = .rounded
            if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                button.image = image
                button.imagePosition = .imageLeading
            }
            root.addSubview(button)
            if action == #selector(editTapped) { editButton = button }
            if action == #selector(deleteTapped) { deleteButton = button }
            if action == #selector(restorePuntoTapped) { restorePuntoButton = button }
            rowX[row] += width + 4
        }
        editButton?.isEnabled = false
        deleteButton?.isEnabled = false
        deleteButton?.toolTip = L10n.userRulesDeleteHint
        restorePuntoButton?.isEnabled = SettingsManager.shared.removedPuntoRuleCount > 0
        reloadFromStore()
        return root
    }

    private func addColumn(_ title: String, identifier: NSUserInterfaceItemIdentifier, width: CGFloat) {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.width = width
        column.minWidth = width
        column.maxWidth = width
        column.resizingMask = .userResizingMask
        table.addTableColumn(column)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visibleEntries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleEntries.indices.contains(row), let id = tableColumn?.identifier else { return nil }
        let rule = visibleEntries[row]
        let value: String
        switch id {
        case Column.pattern: value = rule.pattern
        case Column.behavior:
            value = compactActionTitle(rule.action)
        case Column.replacement: value = rule.replacement ?? "—"
        case Column.source:
            let source: String
            switch rule.origin {
            case .user: source = L10n.userRulesSourceUser
            case .punto: source = L10n.userRulesSourcePunto
            case .learned: source = L10n.userRulesSourceLearned
            }
            if rule.semanticStatus == .unverifiedPuntoType || rule.match == .unverifiedPunto {
                value = "\(source) · \(rule.enabled ? L10n.userRulesEnabled : L10n.userRulesDisabled) · \(L10n.userRulesUnverified)"
            } else {
                value = "\(source) · \(rule.enabled ? L10n.userRulesEnabled : L10n.userRulesDisabled)"
            }
        default: return nil
        }
        let cell = NSTableCellView()
        if id == Column.source {
            let indicator = NSImageView()
            indicator.image = NSImage(systemSymbolName: rule.enabled ? "checkmark.circle.fill" : "pause.circle",
                                      accessibilityDescription: rule.enabled ? L10n.userRulesEnabled : L10n.userRulesDisabled)
            indicator.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            indicator.contentTintColor = rule.enabled ? .systemGreen : .tertiaryLabelColor
            indicator.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(indicator)
            let sourceLabel = NSTextField(labelWithString: sourceTitle(rule.origin))
            sourceLabel.lineBreakMode = .byTruncatingTail
            sourceLabel.toolTip = value
            sourceLabel.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(sourceLabel)
            NSLayoutConstraint.activate([
                indicator.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
                indicator.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                indicator.widthAnchor.constraint(equalToConstant: 14),
                indicator.heightAnchor.constraint(equalToConstant: 14),
                sourceLabel.leadingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: 5),
                sourceLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
                sourceLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        let label = NSTextField(labelWithString: value)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = id == Column.behavior ? "\(matchTitle(rule.match)) · \(actionTitle(rule.action))" : value
        label.translatesAutoresizingMaskIntoConstraints = false
        if id == Column.pattern { label.font = SystemTypography.monospaced(.callout) }
        if !rule.enabled { label.textColor = .secondaryLabelColor }
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionButtons()
    }

    func reloadFromStore() {
        entries = SettingsManager.shared.allRules
        applySearch()
    }

    @objc private func searchChanged(_ sender: NSSearchField) { applySearch() }

    private func applySearch() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleEntries = query.isEmpty ? entries : entries.filter { rule in
            [rule.pattern, rule.replacement ?? "", rule.match.rawValue, matchTitle(rule.match),
             rule.action.rawValue, actionTitle(rule.action), rule.origin.rawValue]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        table.reloadData()
        updateSelectionButtons()
    }

    private func updateSelectionButtons() {
        let row = table.selectedRow
        let selected = visibleEntries.indices.contains(row) ? visibleEntries[row] : nil
        editButton?.isEnabled = selected?.origin == .user
        deleteButton?.isEnabled = selected != nil
        deleteButton?.toolTip = selected.map {
            L10n.userRulesDeleteSelectedHint($0.pattern)
        } ?? L10n.userRulesDeleteHint
        table.menu?.items.first?.isEnabled = selected != nil
        restorePuntoButton?.isEnabled = SettingsManager.shared.removedPuntoRuleCount > 0
    }

    @objc private func addTapped() {
        guard let rule = presentRuleEditor(existing: nil) else { return }
        var rules = SettingsManager.shared.userRules
        guard !rules.contains(where: { equivalent($0, rule) }) else {
            showAlert(title: L10n.userRulesDuplicate, message: rule.pattern, style: .informational)
            return
        }
        rules.append(rule)
        save(rules)
    }

    @objc private func editTapped() {
        guard let old = selectedEditableRule(), let updated = presentRuleEditor(existing: old) else { return }
        var rules = SettingsManager.shared.userRules
        guard let index = rules.firstIndex(where: { $0.id == old.id }) else { return }
        guard !rules.enumerated().contains(where: { $0.offset != index && equivalent($0.element, updated) }) else {
            showAlert(title: L10n.userRulesDuplicate, message: updated.pattern, style: .informational)
            return
        }
        rules[index] = updated
        save(rules)
    }

    @objc private func deleteTapped() {
        guard let selected = selectedRule() else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.userRulesDeleteTitle
        alert.informativeText = L10n.userRulesDeleteMessage(selected.pattern, sourceTitle(selected.origin))
        alert.addButton(withTitle: L10n.userRulesDelete)
        alert.addButton(withTitle: L10n.commonCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            guard try SettingsManager.shared.deleteRule(selected) else { return }
            reloadFromStore()
            onRulesChanged?()
        } catch {
            showAlert(title: L10n.userRulesSaveFailure, message: error.localizedDescription, style: .warning)
        }
    }

    @objc private func restorePuntoTapped() {
        do {
            let restored = try SettingsManager.shared.restoreDeletedPuntoRules()
            reloadFromStore()
            onRulesChanged?()
            showAlert(title: L10n.userRulesRestoreSuccess,
                      message: L10n.userRulesRestoreCount(restored), style: .informational)
        } catch {
            showAlert(title: L10n.userRulesSaveFailure, message: error.localizedDescription, style: .warning)
        }
    }

    @objc private func importTapped() {
        let panel = NSOpenPanel()
        panel.title = L10n.userRulesImport
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try UserRuleFileCodec.decode(Data(contentsOf: url))
            var local = SettingsManager.shared.userRules
            var added = 0
            for var rule in imported where !local.contains(where: { equivalent($0, rule) }) {
                if local.contains(where: { $0.id == rule.id }) { rule.id = UUID().uuidString }
                local.append(rule)
                added += 1
            }
            try SettingsManager.shared.replaceUserRules(local)
            reloadFromStore()
            onRulesChanged?()
            showAlert(title: L10n.userRulesImportSuccess,
                      message: String(format: L10n.userRulesImportAdded, added), style: .informational)
        } catch {
            showAlert(title: L10n.userRulesImportFailure, message: error.localizedDescription, style: .warning)
        }
    }

    @objc private func exportTapped() {
        let panel = NSSavePanel()
        panel.title = L10n.userRulesExport
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MultiSwitcher-Rules.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try UserRuleFileCodec.encode(SettingsManager.shared.userRules)
            try data.write(to: url, options: .atomic)
            showAlert(title: L10n.userRulesExportSuccess, message: url.lastPathComponent, style: .informational)
        } catch {
            showAlert(title: L10n.userRulesExportFailure, message: error.localizedDescription, style: .warning)
        }
    }

    private func selectedEditableRule() -> ProfileRule? {
        let row = table.selectedRow
        guard visibleEntries.indices.contains(row), visibleEntries[row].origin == .user else { return nil }
        return visibleEntries[row]
    }

    private func selectedRule() -> ProfileRule? {
        let row = table.selectedRow
        guard visibleEntries.indices.contains(row) else { return nil }
        return visibleEntries[row]
    }

    private func sourceTitle(_ origin: ProfileRuleOrigin) -> String {
        switch origin {
        case .user: return L10n.userRulesSourceUser
        case .punto: return L10n.userRulesSourcePunto
        case .learned: return L10n.userRulesSourceLearned
        }
    }

    private func save(_ rules: [ProfileRule]) {
        do {
            try SettingsManager.shared.replaceUserRules(rules)
            reloadFromStore()
            onRulesChanged?()
        } catch {
            showAlert(title: L10n.userRulesSaveFailure, message: error.localizedDescription, style: .warning)
        }
    }

    private func equivalent(_ lhs: ProfileRule, _ rhs: ProfileRule) -> Bool {
        lhs.pattern == rhs.pattern && lhs.replacement == rhs.replacement && lhs.match == rhs.match
            && lhs.action == rhs.action && lhs.enabled == rhs.enabled && lhs.caseSensitive == rhs.caseSensitive
    }

    private func presentRuleEditor(existing: ProfileRule?) -> ProfileRule? {
        let alert = NSAlert()
        alert.messageText = existing == nil ? L10n.userRulesAddTitle : L10n.userRulesEditTitle
        alert.informativeText = L10n.userRulesDialogHint
        alert.addButton(withTitle: L10n.userRulesSave)
        alert.addButton(withTitle: L10n.commonCancel)

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 240))
        func label(_ title: String, y: CGFloat) {
            let field = NSTextField(labelWithString: title)
            field.frame = NSRect(x: 0, y: y, width: 132, height: 22)
            field.alignment = .right
            accessory.addSubview(field)
        }
        func addPopup(titles: [String], selected: Int, y: CGFloat) -> NSPopUpButton {
            let popup = NSPopUpButton(frame: NSRect(x: 140, y: y, width: 380, height: 24), pullsDown: false)
            for (index, title) in titles.enumerated() {
                popup.addItem(withTitle: title)
                popup.item(at: index)?.tag = index
            }
            popup.selectItem(at: min(max(0, selected), titles.count - 1))
            accessory.addSubview(popup)
            return popup
        }

        label(L10n.userRulesPattern, y: 207)
        let pattern = NSTextField(frame: NSRect(x: 140, y: 206, width: 380, height: 24))
        pattern.placeholderString = L10n.userRulesPatternPlaceholder
        pattern.stringValue = existing?.pattern ?? ""
        accessory.addSubview(pattern)

        label(L10n.userRulesMatch, y: 164)
        let modeIndex = matchModes.firstIndex(of: existing?.match == .unverifiedPunto ? .exact : existing?.match ?? .exact) ?? 0
        let modePopup = addPopup(titles: matchModes.map(matchTitle), selected: modeIndex, y: 163)

        label(L10n.userRulesAction, y: 121)
        let actionIndex = actions.firstIndex(of: existing?.action ?? .neverConvert) ?? 0
        let actionPopup = addPopup(titles: actions.map(actionTitle), selected: actionIndex, y: 120)

        label(L10n.userRulesReplacement, y: 78)
        let replacement = NSTextField(frame: NSRect(x: 140, y: 77, width: 380, height: 24))
        replacement.stringValue = existing?.replacement ?? ""
        replacement.placeholderString = L10n.userRulesReplacementPlaceholder
        replacement.isEnabled = actions[actionIndex] == .replace
        accessory.addSubview(replacement)
        dialogReplacementField = replacement
        actionPopup.target = self
        actionPopup.action = #selector(ruleActionChanged(_:))

        let caseCheckbox = NSButton(checkboxWithTitle: L10n.userRulesCaseSensitive, target: nil, action: nil)
        caseCheckbox.frame = NSRect(x: 0, y: 30, width: 230, height: 22)
        caseCheckbox.state = existing?.caseSensitive == true ? .on : .off
        accessory.addSubview(caseCheckbox)
        let enabledCheckbox = NSButton(checkboxWithTitle: L10n.userRulesEnabled, target: nil, action: nil)
        enabledCheckbox.frame = NSRect(x: 250, y: 30, width: 260, height: 22)
        enabledCheckbox.state = existing?.enabled == false ? .off : .on
        accessory.addSubview(enabledCheckbox)

        alert.accessoryView = accessory
        let editorWindow = alert.window
        editorWindow.styleMask.insert(.resizable)
        editorWindow.collectionBehavior = [.managed, .fullScreenPrimary]
        editorWindow.minSize = NSSize(width: 560, height: 430)
        editorWindow.setContentSize(NSSize(width: 620, height: 470))
        editorWindow.standardWindowButton(.zoomButton)?.isEnabled = true
        editorWindow.initialFirstResponder = pattern
        defer { dialogReplacementField = nil }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = pattern.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = matchModes[modePopup.indexOfSelectedItem]
        let action = actions[actionPopup.indexOfSelectedItem]
        let replacementText = replacement.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProfileRuleEngine.isValidPattern(text, mode: mode),
              action != .replace || (!replacementText.isEmpty && replacementText.count <= 4096) else {
            showAlert(title: L10n.userRulesInvalidTitle, message: L10n.userRulesInvalidMessage, style: .warning)
            return nil
        }
        return ProfileRule(
            id: existing?.id ?? UUID().uuidString,
            pattern: text,
            replacement: action == .replace ? replacementText : nil,
            match: mode,
            action: action,
            enabled: enabledCheckbox.state == .on,
            caseSensitive: caseCheckbox.state == .on,
            origin: .user,
            semanticStatus: .verified
        )
    }

    @objc private func ruleActionChanged(_ sender: NSPopUpButton) {
        dialogReplacementField?.isEnabled = actions.indices.contains(sender.indexOfSelectedItem)
            && actions[sender.indexOfSelectedItem] == .replace
    }

    private func matchTitle(_ match: ProfileRuleMatch) -> String {
        switch match {
        case .exact, .unverifiedPunto: return L10n.userRulesMatchExact
        case .prefix: return L10n.userRulesMatchPrefix
        case .contains: return L10n.userRulesMatchContains
        case .regularExpression: return L10n.userRulesMatchRegex
        }
    }

    private func actionTitle(_ action: ProfileRuleAction) -> String {
        switch action {
        case .neverConvert: return L10n.userRulesActionNever
        case .alwaysConvert: return L10n.userRulesActionAlways
        case .replace: return L10n.userRulesActionReplace
        }
    }

    private func compactActionTitle(_ action: ProfileRuleAction) -> String {
        switch action {
        case .neverConvert: return L10n.userRulesActionNeverShort
        case .alwaysConvert: return L10n.userRulesActionAlwaysShort
        case .replace: return L10n.userRulesActionReplaceShort
        }
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.commonOkay)
        alert.runModal()
    }
}
