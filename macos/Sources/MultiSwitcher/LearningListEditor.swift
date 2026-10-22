import AppKit
import MultiSwitcherCore

extension Notification.Name {
    static let multiSwitcherLearningDidChange = Notification.Name("MultiSwitcherLearningDidChange")
}

@MainActor
final class LearningListEditor: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private enum Column {
        static let word = NSUserInterfaceItemIdentifier("learning.word")
        static let count = NSUserInterfaceItemIdentifier("learning.count")
        static let state = NSUserInterfaceItemIdentifier("learning.state")
    }

    private enum Filter: Int {
        case candidates
        case active
        case imported
        case all
    }

    private let table = NSTableView()
    private let searchField = NSSearchField()
    private let filterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let emptyStateLabel = NSTextField(wrappingLabelWithString: "")
    private let forgetButton = NSButton()
    private let confirmButton = NSButton()
    private var entries: [LearningEntry] = []
    private var visibleEntries: [LearningEntry] = []
    private var selectedFilter: Filter = .candidates

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(learningDidChange(_:)),
                                               name: .multiSwitcherLearningDidChange, object: nil)
    }

    func setCompactMode(_ compact: Bool) {
        table.rowHeight = compact ? 20 : 24
        table.intercellSpacing = NSSize(width: 0, height: compact ? 1 : 3)
    }

    func makeContainer(frame: NSRect) -> NSView {
        let root = NSView(frame: frame)
        root.autoresizesSubviews = true

        searchField.frame = NSRect(x: 0, y: frame.height - 30, width: frame.width, height: 24)
        searchField.autoresizingMask = [.width, .minYMargin]
        searchField.placeholderString = L10n.learningSearch
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        root.addSubview(searchField)

        filterPopup.frame = NSRect(x: 0, y: frame.height - 62, width: min(210, frame.width), height: 26)
        filterPopup.autoresizingMask = [.minYMargin, .maxXMargin]
        addFilter(L10n.learningFilterCandidates, filter: .candidates)
        addFilter(L10n.learningFilterActive, filter: .active)
        addFilter(L10n.learningFilterImported, filter: .imported)
        addFilter(L10n.learningFilterAll, filter: .all)
        filterPopup.target = self
        filterPopup.action = #selector(filterChanged)
        filterPopup.selectItem(at: Filter.candidates.rawValue)
        root.addSubview(filterPopup)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 34, width: frame.width,
                                               height: max(50, frame.height - 102)))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        addColumn(L10n.learningColumnWord, identifier: Column.word, width: frame.width * 0.54)
        addColumn(L10n.learningColumnCount, identifier: Column.count, width: frame.width * 0.14)
        addColumn(L10n.learningColumnState, identifier: Column.state, width: frame.width * 0.32)
        table.autoresizingMask = [.width]
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 24
        scroll.documentView = table
        root.addSubview(scroll)

        emptyStateLabel.alignment = .center
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.maximumNumberOfLines = 3
        emptyStateLabel.lineBreakMode = .byWordWrapping
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.leadingAnchor, constant: 18),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: scroll.trailingAnchor, constant: -18),
            emptyStateLabel.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor, constant: -36)
        ])

        forgetButton.frame = NSRect(x: 0, y: 0, width: 100, height: 26)
        forgetButton.autoresizingMask = [.maxYMargin]
        forgetButton.title = L10n.learningForget
        forgetButton.bezelStyle = .rounded
        forgetButton.target = self
        forgetButton.action = #selector(forgetSelected)
        forgetButton.isEnabled = false
        root.addSubview(forgetButton)

        confirmButton.frame = NSRect(x: 108, y: 0, width: 190, height: 26)
        confirmButton.autoresizingMask = [.maxYMargin]
        confirmButton.title = L10n.learningConfirmManual
        confirmButton.bezelStyle = .rounded
        confirmButton.target = self
        confirmButton.action = #selector(confirmSelectedCandidate)
        confirmButton.isEnabled = false
        root.addSubview(confirmButton)

        reloadFromStore()
        return root
    }

    private func addFilter(_ title: String, filter: Filter) {
        filterPopup.addItem(withTitle: title)
        filterPopup.lastItem?.tag = filter.rawValue
    }

    private func addColumn(_ title: String, identifier: NSUserInterfaceItemIdentifier, width: CGFloat) {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.width = width
        column.minWidth = identifier == Column.word ? 120 : 56
        column.maxWidth = .greatestFiniteMagnitude
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visibleEntries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleEntries.indices.contains(row), let id = tableColumn?.identifier else { return nil }
        let entry = visibleEntries[row]
        let value: String
        let tooltip: String?
        switch id {
        case Column.word:
            value = entry.word
            tooltip = nil
        case Column.count:
            if entry.origin == .punto {
                value = String(entry.importedCancellationCount ?? entry.cancellationCount)
                tooltip = L10n.learningImportedCountTooltip
            } else if entry.isExcluded {
                value = "—"
                tooltip = nil
            } else if let cycles = entry.manualRoundTripCount, cycles > 0 {
                value = "\(min(cycles, LearningEngine.requiredManualRoundTrips))/\(LearningEngine.requiredManualRoundTrips)"
                tooltip = L10n.learningManualRoundTripCount(cycles)
            } else {
                let cycles = max(0, entry.cancellationCount)
                value = "\(min(cycles, LearningEngine.requiredCancellations))/\(LearningEngine.requiredCancellations)"
                tooltip = L10n.learningAutoCancellationCount(cycles)
            }
        case Column.state:
            value = entry.isExcluded ? L10n.learningStateExcluded
                : isManualCandidate(entry) ? L10n.learningManualCandidateState
                : entry.origin == .punto ? L10n.learningStateImportedHistory
                : L10n.learningStatePending
            tooltip = nil
        default: return nil
        }

        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: value)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = tooltip
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
        updateActionButtons()
    }

    func reloadFromStore() {
        entries = SettingsManager.shared.learningEntries
        applySearchAndFilter()
    }

    @objc private func learningDidChange(_ notification: Notification) {
        reloadFromStore()
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        applySearchAndFilter()
    }

    @objc private func filterChanged(_ sender: NSPopUpButton) {
        guard let filter = Filter(rawValue: sender.selectedTag()) else { return }
        selectedFilter = filter
        applySearchAndFilter()
    }

    private func applySearchAndFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = entries.filter { entry in
            switch selectedFilter {
            case .candidates: return !entry.isExcluded && entry.origin == .local
            case .active: return entry.isExcluded
            case .imported: return entry.origin == .punto
            case .all: return true
            }
        }
        visibleEntries = query.isEmpty
            ? filtered
            : filtered.filter { $0.word.localizedCaseInsensitiveContains(query) }
        table.reloadData()
        table.deselectAll(nil)
        updateEmptyState(query: query)
        updateActionButtons()
    }

    private func updateEmptyState(query: String) {
        guard visibleEntries.isEmpty else {
            emptyStateLabel.isHidden = true
            return
        }
        if !query.isEmpty {
            emptyStateLabel.stringValue = L10n.learningNoSearchResults
        } else {
            switch selectedFilter {
            case .candidates: emptyStateLabel.stringValue = L10n.learningCandidatesEmpty
            case .active: emptyStateLabel.stringValue = L10n.learningActiveEmpty
            case .imported: emptyStateLabel.stringValue = L10n.learningImportedEmpty
            case .all: emptyStateLabel.stringValue = L10n.learningAllEmpty
            }
        }
        emptyStateLabel.isHidden = false
    }

    @objc private func forgetSelected() {
        let row = table.selectedRow
        guard visibleEntries.indices.contains(row) else { return }
        SettingsManager.shared.forgetLearnedWord(visibleEntries[row].word)
        reloadFromStore()
    }

    @objc private func confirmSelectedCandidate() {
        let row = table.selectedRow
        guard visibleEntries.indices.contains(row),
              isManualCandidate(visibleEntries[row]),
              SettingsManager.shared.confirmManualLearningCandidate(visibleEntries[row].word) else { return }
        reloadFromStore()
    }

    private func updateActionButtons() {
        guard visibleEntries.indices.contains(table.selectedRow) else {
            forgetButton.isEnabled = false
            confirmButton.isEnabled = false
            return
        }
        let selected = visibleEntries[table.selectedRow]
        forgetButton.isEnabled = true
        confirmButton.isEnabled = isManualCandidate(selected)
    }

    private func isManualCandidate(_ entry: LearningEntry) -> Bool {
        !entry.isExcluded && (entry.manualRoundTripCount ?? 0) >= LearningEngine.requiredManualRoundTrips
    }
}
