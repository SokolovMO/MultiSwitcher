import AppKit
import MultiSwitcherCore

@MainActor
final class LearningListEditor: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private enum Column {
        static let word = NSUserInterfaceItemIdentifier("learning.word")
        static let count = NSUserInterfaceItemIdentifier("learning.count")
        static let state = NSUserInterfaceItemIdentifier("learning.state")
    }

    private let table = NSTableView()
    private let searchField = NSSearchField()
    private let forgetButton = NSButton()
    private var entries: [LearningEntry] = []
    private var visibleEntries: [LearningEntry] = []

    func makeContainer(frame: NSRect) -> NSView {
        let root = NSView(frame: frame)
        searchField.frame = NSRect(x: 0, y: frame.height - 30, width: frame.width, height: 24)
        searchField.placeholderString = L10n.learningSearch
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        root.addSubview(searchField)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 34, width: frame.width, height: frame.height - 70))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        addColumn(L10n.learningColumnWord, identifier: Column.word, width: frame.width * 0.54)
        addColumn(L10n.learningColumnCount, identifier: Column.count, width: frame.width * 0.18)
        addColumn(L10n.learningColumnState, identifier: Column.state, width: frame.width * 0.28)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 24
        scroll.documentView = table
        root.addSubview(scroll)

        forgetButton.frame = NSRect(x: 0, y: 0, width: 100, height: 26)
        forgetButton.title = L10n.learningForget
        forgetButton.bezelStyle = .rounded
        forgetButton.target = self
        forgetButton.action = #selector(forgetSelected)
        forgetButton.isEnabled = false
        root.addSubview(forgetButton)
        return root
    }

    private func addColumn(_ title: String, identifier: NSUserInterfaceItemIdentifier, width: CGFloat) {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.width = width
        column.minWidth = identifier == Column.word ? 120 : 64
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visibleEntries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleEntries.indices.contains(row), let id = tableColumn?.identifier else { return nil }
        let entry = visibleEntries[row]
        let value: String
        switch id {
        case Column.word: value = entry.word
        case Column.count: value = String(entry.cancellationCount)
        case Column.state: value = entry.isExcluded ? L10n.learningStateExcluded : L10n.learningStatePending
        default: return nil
        }
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: value)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        if id == Column.word { label.font = SystemTypography.monospaced(.body) }
        if id == Column.state && !entry.isExcluded { label.textColor = .secondaryLabelColor }
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        forgetButton.isEnabled = table.selectedRow >= 0 && table.selectedRow < visibleEntries.count
    }

    func reloadFromStore() {
        entries = SettingsManager.shared.learningEntries
        applySearch()
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        applySearch()
    }

    private func applySearch() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleEntries = query.isEmpty
            ? entries
            : entries.filter { $0.word.localizedCaseInsensitiveContains(query) }
        table.reloadData()
        forgetButton.isEnabled = false
    }

    @objc private func forgetSelected() {
        let row = table.selectedRow
        guard visibleEntries.indices.contains(row) else { return }
        SettingsManager.shared.forgetLearnedWord(visibleEntries[row].word)
        reloadFromStore()
    }
}
