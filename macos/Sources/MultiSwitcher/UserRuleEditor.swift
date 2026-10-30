import AppKit
import MultiSwitcherCore
import UniformTypeIdentifiers

private final class RuleTableView: GraphiteTableView {

    override func keyDown(with event: NSEvent) {
        // Support both the forward-delete key on compact keyboards and the
        // dedicated Delete key. Keep the same confirmation path as the button.
        if event.keyCode == 51 || event.keyCode == 117 {
            if !event.isARepeat { onDeleteSelection?() }
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

/// The viewport owns column allocation. NSTableView's automatic sizing keeps the
/// original document width when the scroll view narrows, hiding the source column.
@MainActor private final class RuleScrollView: NSScrollView {
    private var sizingColumns = false
    override func tile() {
        super.tile()
        guard !sizingColumns, let table = documentView as? NSTableView,
              table.tableColumns.count == 4, contentSize.width > 0 else { return }
        sizingColumns = true
        defer { sizingColumns = false }
        let columns = table.tableColumns
        let minimum = columns.reduce(CGFloat.zero) { $0 + $1.minWidth }
        let width = max(minimum, contentSize.width)
        let extra = width - minimum
        let weights: [CGFloat] = [0.3, 0.25, 0.18, 0.27]
        for (index, column) in columns.enumerated() {
            let target = column.minWidth + extra * weights[index]
            if abs(column.width - target) > 0.1 { column.width = target }
        }
        let rowsHeight = table.numberOfRows > 0
            ? table.rect(ofRow: table.numberOfRows - 1).maxY
            : 0
        let documentHeight = max(contentSize.height, rowsHeight)
        if abs(table.frame.width - width) > 0.1 || abs(table.frame.height - documentHeight) > 0.1 {
            table.setFrameSize(NSSize(width: width, height: documentHeight))
        }
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
    private let searchField = GraphiteSearchField()
    private let sourceFilter = NSPopUpButton(frame: .zero, pullsDown: false)
    private let emptyStateLabel = NSTextField(wrappingLabelWithString: "")
    var onPreferredHeightChange: ((CGFloat) -> Void)?
    var preferredHeight: CGFloat { min(540, max(230, CGFloat(visibleEntries.count) * 31 + 184)) }
    private let sourceKinds: [ProfileRuleOrigin?] = [nil, .user, .learned, .punto]
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(rulesDidChange), name: .multiSwitcherLearningDidChange, object: nil)
    }
    @objc private func rulesDidChange() { reloadFromStore() }
    @objc private func sourceChanged() { applySearch() }
    func showLearnedRule(word: String) {
        sourceFilter.selectItem(at: 2)
        searchField.stringValue = word
        reloadFromStore()
        if let row = visibleEntries.firstIndex(where: { $0.origin == .learned && $0.pattern.localizedCaseInsensitiveCompare(word) == .orderedSame }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
    }
    private var editButton: NSButton?
    private var deleteButton: NSButton?
    private var restorePuntoButton: NSButton?
    private var entries: [ProfileRule] = []
    private var visibleEntries: [ProfileRule] = []
    private weak var dialogReplacementField: NSTextField?
    var onRulesChanged: (() -> Void)?

    private let matchModes: [ProfileRuleMatch] = [.exact, .prefix, .contains, .regularExpression]
    private let actions: [ProfileRuleAction] = [.neverConvert, .alwaysConvert, .replace]

    func setCompactMode(_ compact: Bool) {
        table.rowHeight = compact ? 26 : 30
        table.intercellSpacing = NSSize(width: 0, height: compact ? 1 : 3)
    }

    func makeContainer(frame: NSRect) -> NSView {
        let root = NSView(frame: frame)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = L10n.userRulesSearch
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        root.addSubview(searchField)
        sourceFilter.addItems(withTitles: [L10n.uiAllSources, L10n.uiManualSource, L10n.uiLearnedSource, L10n.uiImportedSource])
        sourceFilter.target = self; sourceFilter.action = #selector(sourceChanged)
        sourceFilter.setAccessibilityLabel(L10n.uiRuleSource)
        sourceFilter.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sourceFilter)

        let hint = NSTextField(wrappingLabelWithString: L10n.uiRulesHint)
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.font = SystemTypography.font(.footnote)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 0
        hint.cell?.lineBreakMode = .byWordWrapping
        root.addSubview(hint)

        let scroll = RuleScrollView(frame: .zero)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let columnWidths: [CGFloat] = [frame.width * 0.28, frame.width * 0.28,
                                       frame.width * 0.18, frame.width * 0.26]
        addColumn(L10n.userRulesColumnPattern, identifier: Column.pattern, width: columnWidths[0])
        addColumn(L10n.userRulesColumnBehavior, identifier: Column.behavior, width: columnWidths[1])
        addColumn(L10n.userRulesColumnReplacement, identifier: Column.replacement, width: columnWidths[2])
        addColumn(L10n.userRulesColumnSource, identifier: Column.source, width: columnWidths[3])
        table.rowHeight = 30
        table.autoresizingMask = [.width]
        // Every column participates when the viewport narrows. Horizontal scrolling
        // remains available below the usable column minima.
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.usesAlternatingRowBackgroundColors = false
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
        emptyStateLabel.stringValue = L10n.languageCode == "ru" ? "пока нет правил" : "no rules yet"
        emptyStateLabel.alignment = .center
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.maximumNumberOfLines = 2
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.leadingAnchor, constant: 18),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: scroll.trailingAnchor, constant: -18),
        ])

        let addButton = makeActionButton(L10n.userRulesAdd, symbol: "plus", action: #selector(addTapped))
        let edit = makeActionButton(L10n.userRulesEdit, symbol: "pencil", action: #selector(editTapped))
        let delete = makeActionButton(L10n.userRulesDelete, symbol: "trash", action: #selector(deleteTapped))
        let importButton = makeActionButton(L10n.userRulesImport, symbol: "square.and.arrow.down",
                                            action: #selector(importTapped))
        let exportButton = makeActionButton(L10n.userRulesExport, symbol: "square.and.arrow.up",
                                            action: #selector(exportTapped))
        let restore = makeActionButton(L10n.userRulesRestorePunto, symbol: "arrow.uturn.backward",
                                       action: #selector(restorePuntoTapped))
        editButton = edit
        deleteButton = delete
        restorePuntoButton = restore

        // One compact toolbar; tooltips and accessibility retain the full action names.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for button in [edit, delete, importButton, exportButton, restore] {
            button.imagePosition = .imageOnly
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        }
        addButton.widthAnchor.constraint(equalToConstant: 108).isActive = true
        let toolbar = NSStackView(views: [addButton, edit, delete, spacer, importButton, exportButton, restore])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.distribution = .fill
        toolbar.spacing = 6
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolbar)

        editButton?.isEnabled = false
        deleteButton?.isEnabled = false
        deleteButton?.toolTip = L10n.userRulesDeleteHint
        restorePuntoButton?.isEnabled = SettingsManager.shared.removedPuntoRuleCount > 0

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            searchField.topAnchor.constraint(equalTo: root.topAnchor),
            hint.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            sourceFilter.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sourceFilter.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            hint.topAnchor.constraint(equalTo: sourceFilter.bottomAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -8),
        ])

        reloadFromStore()
        return root
    }

    private func makeActionButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = GraphiteButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel(title)
        button.toolTip = title
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func horizontalActionRow(_ buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func addColumn(_ title: String, identifier: NSUserInterfaceItemIdentifier, width: CGFloat) {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.width = width
        column.minWidth = identifier == Column.source ? 116 : identifier == Column.behavior ? 104 : identifier == Column.pattern ? 88 : 72
        column.maxWidth = .greatestFiniteMagnitude
        column.resizingMask = [.userResizingMask, .autoresizingMask]
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
            indicator.contentTintColor = rule.enabled ? .labelColor : .tertiaryLabelColor
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
        let previousRow = table.selectedRow
        let selectedID = visibleEntries.indices.contains(previousRow) ? visibleEntries[previousRow].id : nil
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = sourceKinds[max(0, sourceFilter.indexOfSelectedItem)]
        let matchingSource = entries.filter { source == nil || $0.origin == source }
        visibleEntries = query.isEmpty ? matchingSource : matchingSource.filter { rule in
            [rule.pattern, rule.replacement ?? "", rule.match.rawValue, matchTitle(rule.match),
             rule.action.rawValue, actionTitle(rule.action), rule.origin.rawValue]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
        table.reloadData()
        if let selectedID {
            let index = visibleEntries.firstIndex { $0.id == selectedID } ?? min(previousRow, visibleEntries.count - 1)
            if index >= 0 { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        }
        emptyStateLabel.isHidden = !visibleEntries.isEmpty
        updateSelectionButtons()
        onPreferredHeightChange?(preferredHeight)
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
        MultiDeletionConfirmation.request(window: table.window,
            defaults: MultiAuditEnvironment.defaults(appID: "com.multiswitcher.app"), kind: "rules",
            title: L10n.userRulesDeleteTitle,
            detail: L10n.userRulesDeleteMessage(selected.pattern, sourceTitle(selected.origin)),
            russian: L10n.languageCode == "ru") { [weak self] in
                guard try SettingsManager.shared.deleteRule(selected) else { return }
                self?.reloadFromStore(); self?.onRulesChanged?()
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
        panel.allowedContentTypes = [.json, .plainText, .commaSeparatedText,
                                     UTType(filenameExtension: "tsv") ?? .plainText,
                                     .propertyList]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let fileExtension = url.pathExtension.lowercased()
            if fileExtension == "plist" {
                let report = try SettingsManager.shared.importPuntoProfile(from: url)
                reloadFromStore()
                onRulesChanged?()

                let alert = GraphiteAlert()
                alert.alertStyle = .informational
                alert.messageText = L10n.settingsImportPuntoSuccess
                alert.informativeText = L10n.settingsImportPuntoAppliedDetails(
                    report.rulesImported,
                    report.unverifiedRules,
                    report.learningImported,
                    report.learningDiscardedByReview,
                    report.snapshotName
                )
                alert.addButton(withTitle: L10n.commonOkay)
                alert.runModal()
                return
            }
            let intent = fileExtension == "txt" ? chooseTextImportIntent() : nil
            if fileExtension == "txt", intent == nil { return }
            let preview = try UserRuleFileCodec.previewImport(
                Data(contentsOf: url), fileExtension: fileExtension, textIntent: intent
            )
            var local = SettingsManager.shared.userRules
            var additions: [ProfileRule] = []
            var alreadyPresent = 0
            var conflicts = 0
            for var rule in preview.rules {
                if local.contains(where: { equivalent($0, rule) }) {
                    alreadyPresent += 1
                    continue
                }
                if local.contains(where: { sameRuleTarget($0, rule) }) {
                    conflicts += 1
                    continue
                }
                if local.contains(where: { $0.id == rule.id }) { rule.id = UUID().uuidString }
                local.append(rule)
                additions.append(rule)
            }
            let skippedDuplicates = preview.duplicateRowCount + alreadyPresent
            let message = L10n.userRulesImportPreview(
                preview.sourceRowCount, additions.count, skippedDuplicates, conflicts
            )
            let confirmation = GraphiteAlert()
            confirmation.alertStyle = .informational
            confirmation.messageText = L10n.userRulesImportPreviewTitle
            confirmation.informativeText = message
            confirmation.addButton(withTitle: L10n.userRulesImport)
            confirmation.addButton(withTitle: L10n.commonCancel)
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }

            if !additions.isEmpty {
                try SettingsManager.shared.replaceUserRules(local)
                reloadFromStore()
                onRulesChanged?()
            }
            showAlert(title: L10n.userRulesImportSuccess,
                      message: String(format: L10n.userRulesImportAdded, additions.count), style: .informational)
        } catch {
            showAlert(title: L10n.userRulesImportFailure, message: error.localizedDescription, style: .warning)
        }
    }

    private func chooseTextImportIntent() -> UserRuleTextIntent? {
        let alert = GraphiteAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.userRulesImportTextIntentTitle
        alert.addButton(withTitle: L10n.userRulesActionNever)
        alert.addButton(withTitle: L10n.userRulesActionAlways)
        alert.addButton(withTitle: L10n.commonCancel)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .neverConvert
        case .alertSecondButtonReturn: return .alwaysConvert
        default: return nil
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

    private func sameRuleTarget(_ lhs: ProfileRule, _ rhs: ProfileRule) -> Bool {
        lhs.match == rhs.match
            && lhs.pattern.precomposedStringWithCanonicalMapping.lowercased()
                == rhs.pattern.precomposedStringWithCanonicalMapping.lowercased()
    }

    func resetReviewFilters() { sourceFilter.selectItem(at: 0); searchField.stringValue = ""; applySearch() }
    func exerciseForReview() -> Bool {
        let originalSource = sourceFilter.indexOfSelectedItem
        defer { sourceFilter.selectItem(at: originalSource); searchField.stringValue = ""; applySearch() }
        var sourcesPassed = true
        for (index, source) in sourceKinds.enumerated() {
            sourceFilter.selectItem(at: index); searchField.stringValue = ""; applySearch()
            sourcesPassed = sourcesPassed && visibleEntries.count == entries.filter { source == nil || $0.origin == source }.count
            sourcesPassed = sourcesPassed && visibleEntries.allSatisfy { source == nil || $0.origin == source }
        }
        sourceFilter.selectItem(at: 0); applySearch()
        guard !entries.isEmpty else { return sourcesPassed }
        let count = entries.count
        searchField.stringValue = entries[0].pattern
        applySearch()
        let searchPassed = !visibleEntries.isEmpty
        searchField.stringValue = ""
        applySearch()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let selectionPassed = deleteButton?.isEnabled == true
        if table.numberOfRows > 1, let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.function], timestamp: 0, windowNumber: table.window?.windowNumber ?? 0,
            context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125) {
            table.window?.makeFirstResponder(table)
            table.keyDown(with: event)
        }
        let keyboardPassed = table.numberOfRows < 2 || table.selectedRow == 1
        return sourcesPassed && searchPassed && selectionPassed && keyboardPassed && entries.count == count
    }
    func captureDialogForReview() { _ = presentRuleEditor(existing: nil) }

    private func presentRuleEditor(existing: ProfileRule?) -> ProfileRule? {
        let alert = GraphiteAlert()
        alert.messageText = existing == nil ? L10n.userRulesAddTitle : L10n.userRulesEditTitle
        alert.informativeText = L10n.userRulesDialogHint
        alert.addButton(withTitle: L10n.userRulesSave)
        alert.addButton(withTitle: L10n.commonCancel)

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 240))
        func label(_ title: String, y: CGFloat) {
            let field = NSTextField(labelWithString: title)
            field.frame = NSRect(x: 0, y: y, width: 132, height: 22)
            field.alignment = .left
            accessory.addSubview(field)
        }
        func addPopup(titles: [String], selected: Int, y: CGFloat) -> NSPopUpButton {
            let popup = GraphitePopUpButton(frame: NSRect(x: 140, y: y, width: 380, height: 24), pullsDown: false)
            for (index, title) in titles.enumerated() {
                popup.addItem(withTitle: title)
                popup.item(at: index)?.tag = index
            }
            popup.selectItem(at: min(max(0, selected), titles.count - 1))
            accessory.addSubview(popup)
            return popup
        }

        label(L10n.userRulesPattern, y: 207)
        let pattern = GraphiteTextField(frame: NSRect(x: 140, y: 206, width: 380, height: 24))
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
        let replacement = GraphiteTextField(frame: NSRect(x: 140, y: 77, width: 380, height: 24))
        replacement.stringValue = existing?.replacement ?? ""
        replacement.placeholderString = L10n.userRulesReplacementPlaceholder
        replacement.isEnabled = actions[actionIndex] == .replace
        accessory.addSubview(replacement)
        dialogReplacementField = replacement
        actionPopup.target = self
        actionPopup.action = #selector(ruleActionChanged(_:))

        let caseCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.userRulesCaseSensitive, target: nil, action: nil)
        caseCheckbox.frame = NSRect(x: 0, y: 30, width: 230, height: 22)
        caseCheckbox.state = existing?.caseSensitive == true ? .on : .off
        accessory.addSubview(caseCheckbox)
        let enabledCheckbox = GraphiteToggleButton(checkboxWithTitle: L10n.userRulesEnabled, target: nil, action: nil)
        enabledCheckbox.frame = NSRect(x: 250, y: 30, width: 260, height: 22)
        enabledCheckbox.state = existing?.enabled == false ? .off : .on
        accessory.addSubview(enabledCheckbox)

        let editorWindow = GraphiteDialogPanel(title: alert.messageText, message: alert.informativeText,
            accessory: accessory, confirm: L10n.userRulesSave, cancel: L10n.commonCancel)
        editorWindow.collectionBehavior = [.managed, .fullScreenNone]
        editorWindow.standardWindowButton(.zoomButton)?.isEnabled = false
        editorWindow.initialFirstResponder = pattern
        defer { dialogReplacementField = nil }
        if let directory = ProcessInfo.processInfo.environment["MULTISWITCHER_UI_REVIEW"] ?? ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] {
            let theme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
            let timer = Timer(timeInterval: 0.4, repeats: false) { _ in
                MainActor.assumeIsolated {
                    SettingsWindowController.captureWindow(editorWindow, to: directory + "/\(theme)-rule-dialog.png")
                    editorWindow.cancelForReview()
                }
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
        }
        guard editorWindow.runDialog() == .alertFirstButtonReturn else { return nil }
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
        let alert = GraphiteAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.commonOkay)
        alert.runModal()
    }
}
