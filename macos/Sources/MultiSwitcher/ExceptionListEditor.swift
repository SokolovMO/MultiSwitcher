import AppKit
import MultiSwitcherCore
import UniformTypeIdentifiers

/// Редактор одного списка-исключений (приложения или слова): таблица + кнопки «+»/«−».
/// Привязка к данным — через замыкания get/set, чтобы один класс обслуживал любой список.
@MainActor
final class ExceptionListEditor: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    enum Kind { case apps, words }

    private let kind: Kind
    private let getList: () -> [String]
    private let setList: ([String]) -> Void
    private let isProtected: (String) -> Bool
    private let addWordPrompt: String
    var onPreferredHeightChange: ((CGFloat) -> Void)?

    private var items: [String] = []
    private let table = GraphiteTableView()
    private let emptyStateLabel = NSTextField(wrappingLabelWithString: "")
    private let removeButton = GraphiteButton()
    private let countLabel = NSTextField(labelWithString: "")
    /// Кэш имени/иконки по bundle id, чтобы не дёргать NSWorkspace на каждый vend ячейки.
    private var infoCache: [String: (text: String, icon: NSImage?)] = [:]

    var preferredHeight: CGFloat {
        let rowCount = CGFloat(items.count)
        return items.isEmpty ? 82 : min(158, max(82, rowCount * table.rowHeight + 38))
    }

    func setCompactMode(_ compact: Bool) {
        table.rowHeight = compact ? 26 : 30
    }

    init(kind: Kind,
         get: @escaping () -> [String],
         set: @escaping ([String]) -> Void,
         isProtected: @escaping (String) -> Bool = { _ in false },
         addWordPrompt: String = "") {
        self.kind = kind
        self.getList = get
        self.setList = set
        self.isProtected = isProtected
        self.addWordPrompt = addWordPrompt
        super.init()
        self.table.rowHeight = 30
        self.items = get()
    }

    /// Контейнер: прокручиваемая таблица + строка кнопок «+»/«−» снизу.
    func makeContainer(frame: NSRect) -> NSView {
        let container = NSView(frame: frame)
        container.autoresizesSubviews = true
        let stripH: CGFloat = 38

        let scroll = NSScrollView(frame: NSRect(x: 0, y: stripH, width: frame.width, height: frame.height - stripH))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
        col.width = frame.width - 4
        col.minWidth = 120
        col.maxWidth = .greatestFiniteMagnitude
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.autoresizingMask = [.width]
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.rowHeight = 30
        table.onDeleteSelection = { [weak self] in self?.removeTapped() }
        let menu = NSMenu()
        let item = NSMenuItem(title: L10n.uiRemove, action: #selector(removeTapped), keyEquivalent: "")
        item.target = self; menu.addItem(item); table.menu = menu
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        container.addSubview(scroll)

        emptyStateLabel.stringValue = kind == .apps ? L10n.exceptionsEmptyApps : L10n.exceptionsEmptyWords
        emptyStateLabel.alignment = .center
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.maximumNumberOfLines = 2
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.leadingAnchor, constant: 18),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: scroll.trailingAnchor, constant: -18),
            emptyStateLabel.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor, constant: -36)
        ])

        let addBtn = GraphiteButton(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
        addBtn.autoresizingMask = [.maxYMargin]
        addBtn.title = ""
        addBtn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: L10n.uiAdd)
        addBtn.imagePosition = .imageOnly
        addBtn.setAccessibilityLabel(L10n.uiAdd)
        addBtn.toolTip = L10n.uiAdd
        addBtn.bezelStyle = .rounded
        addBtn.target = self
        addBtn.action = #selector(addTapped)
        container.addSubview(addBtn)

        removeButton.frame = NSRect(x: 30, y: 0, width: 28, height: 24)
        removeButton.autoresizingMask = [.maxYMargin]
        removeButton.title = ""
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: L10n.uiRemove)
        removeButton.imagePosition = .imageOnly
        removeButton.setAccessibilityLabel(L10n.uiRemove)
        removeButton.toolTip = L10n.uiRemove
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.isEnabled = false
        container.addSubview(removeButton)
        let separator = NSBox(frame: NSRect(x: 0, y: 31, width: frame.width, height: 1))
        separator.boxType = .separator; separator.autoresizingMask = [.width, .maxYMargin]
        container.addSubview(separator)
        countLabel.frame = NSRect(x: 74, y: 4, width: max(0, frame.width - 74), height: 18)
        countLabel.autoresizingMask = [.width, .maxYMargin]
        countLabel.alignment = .right; countLabel.font = SystemTypography.font(.footnote)
        countLabel.textColor = .secondaryLabelColor
        container.addSubview(countLabel)

        updateEmptyState()
        onPreferredHeightChange?(preferredHeight)

        return container
    }

    // MARK: - Table data

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = items[row]
        let info = cellInfo(id)
        let cell = NSTableCellView()

        let text = NSTextField(labelWithString: info.text)
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        if isProtected(id) { text.textColor = .secondaryLabelColor }
        cell.addSubview(text)

        var leading: CGFloat = 4
        if kind == .apps {
            let iv = NSImageView(image: cellInfo(id).icon ?? NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil) ?? NSImage())
            iv.contentTintColor = DesignPalette.secondary
            iv.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
                iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 16),
                iv.heightAnchor.constraint(equalToConstant: 16),
            ])
            leading = 24
        }
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: leading),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveButton()
    }

    private func updateRemoveButton() {
        let row = table.selectedRow
        removeButton.isEnabled = row >= 0 && row < items.count && !isProtected(items[row])
    }

    // MARK: - Actions

    @objc private func addTapped() {
        switch kind {
        case .apps: addApp()
        case .words: addWord()
        }
    }

    @objc private func removeTapped() {
        let row = table.selectedRow
        guard row >= 0, row < items.count else { return }
        let value = items[row]
        guard !isProtected(value) else { return }
        MultiDeletionConfirmation.request(window: table.window,
            defaults: MultiAuditEnvironment.defaults(appID: "com.multiswitcher.app"),
            kind: kind == .apps ? "apps" : "words",
            title: L10n.languageCode == "ru" ? "удалить «\(displayText(value))»?" : "delete ‘\(displayText(value))’?",
            russian: L10n.languageCode == "ru") { [weak self] in
                guard let self, !self.isProtected(value) else { return }
                self.items = self.getList(); self.items.removeAll { $0 == value }
                self.setList(self.items)
                guard self.getList() == self.items else {
                    self.items = self.getList()
                    throw NSError(domain: "MultiSwitcher", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.languageCode == "ru" ? "не удалось сохранить список. повторите удаление." : "could not save the list. please retry."])
                }
                self.table.reloadData(); self.updateEmptyState(); self.updateRemoveButton()
                if !self.items.isEmpty {
                    self.table.selectRowIndexes(IndexSet(integer: min(row, self.items.count - 1)), byExtendingSelection: false)
                }
            }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        items = getList()
        guard !items.contains(id) else { return }
        items.append(id)
        persist()
    }

    private func addWord() {
        let alert = GraphiteAlert()
        alert.messageText = addWordPrompt
        let field = GraphiteTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.commonAdd)
        alert.addButton(withTitle: L10n.commonCancel)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let word = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        items = getList()
        guard !word.isEmpty,
              !items.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
        items.append(word)
        persist()
    }

    private func persist() {
        setList(items)
        table.reloadData()
        updateEmptyState()
        onPreferredHeightChange?(preferredHeight)
        updateRemoveButton()
    }

    func reloadFromStore() {
        items = getList()
        table.reloadData()
        updateEmptyState()
        updateRemoveButton()
    }

    private func updateEmptyState() {
        emptyStateLabel.isHidden = !items.isEmpty
        countLabel.stringValue = "\(items.count) · \(kind == .apps ? L10n.uiApplications : L10n.uiWords)"
        onPreferredHeightChange?(preferredHeight)
    }

    // MARK: - Display helpers

    private func cellInfo(_ id: String) -> (text: String, icon: NSImage?) {
        if let cached = infoCache[id] { return cached }
        let info = (text: displayText(id), icon: kind == .apps ? appIcon(id) : nil)
        infoCache[id] = info
        return info
    }

    private func displayText(_ id: String) -> String {
        guard kind == .apps else { return id }
        if id.hasSuffix("*") { return String(id.dropLast()) + "* (все)" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            let name = FileManager.default.displayName(atPath: url.path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
        let shortName = id.split(separator: ".").last.map(String.init) ?? id
        return shortName.replacingOccurrences(of: "-", with: " ")
    }

    private func appIcon(_ id: String) -> NSImage? {
        guard !id.hasSuffix("*"),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
