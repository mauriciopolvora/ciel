import AppKit
import CielCore

@MainActor
final class LauncherView: FlippedView, NSTextFieldDelegate, NSTableViewDataSource,
    NSTableViewDelegate
{
    static let width: CGFloat = 640
    static let initialHeight: CGFloat = 68
    var onExecute: ((SearchEntry) -> Void)?
    var onDismiss: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    private let state = LauncherState()
    var results: [SearchEntry] { state.results }
    var filter: SearchEntry.Kind? { state.filter }
    var pendingIconCount: Int { icons.pendingCount }
    private(set) var resultReloadCount = 0
    let searchField = LauncherSearchField()
    let table = NSTableView()
    private let scroll = NSScrollView()
    private let icons = IconCache()
    let scopeButton = NSButton()
    private let emptyTitle = Theme.label("No matches", size: 14, weight: .medium)
    private let emptyDetail = Theme.label(
        "Try another name, or switch to All.", size: 12, color: Theme.secondary)
    private let divider = FlippedView()
    private let tint = LauncherDragSurface()
    private var displayObserver: NotificationObservation?
    private var showKeys = false
    private var applyingSelection = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Theme.panelRadius
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        appearance = NSAppearance(named: .darkAqua)
        tint.wantsLayer = true
        addSubview(tint)
        divider.wantsLayer = true
        addSubview(divider)
        searchField.font = .systemFont(ofSize: 21)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.textColor = Theme.text
        searchField.delegate = self
        searchField.placeholderString = nil
        searchField.setAccessibilityLabel("Search apps and commands")
        addSubview(searchField)
        scopeButton.bezelStyle = .inline
        scopeButton.font = .systemFont(ofSize: 12, weight: .medium)
        scopeButton.target = self
        scopeButton.action = #selector(nextScope)
        scopeButton.toolTip = "Change category (Tab / Shift–Tab)"
        scopeButton.setAccessibilityHelp("Click or press Tab to change the search category.")
        addSubview(scopeButton)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        column.width = bounds.width - 16
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = Theme.rowHeight
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .regular
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.focusRingType = .none
        table.allowsEmptySelection = false
        table.setAccessibilityLabel("Search results")
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        addSubview(scroll)
        emptyTitle.alignment = .center
        addSubview(emptyTitle)
        emptyDetail.alignment = .center
        addSubview(emptyDetail)
        updateSurface()
        displayObserver = NotificationObservation(
            center: NSWorkspace.shared.notificationCenter,
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        ) { [weak self] in
            self?.updateSurface()
        }
        render(.initial)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateSurface() {
        tint.layer?.backgroundColor = Theme.cg(Theme.surface, in: self)
        layer?.borderColor = Theme.cg(
            Theme.border.withAlphaComponent(Theme.increaseContrast ? 1 : 0.55), in: self)
        divider.layer?.backgroundColor = Theme.cg(
            Theme.border.withAlphaComponent(Theme.increaseContrast ? 1 : 0.22), in: self)
        table.needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurface()
    }
    override func layout() {
        super.layout()
        tint.frame = bounds
        searchField.frame = NSRect(
            x: 24, y: 18, width: bounds.width - (scopeButton.isHidden ? 48 : 140), height: 31)
        scopeButton.frame = NSRect(x: bounds.width - 108, y: 21, width: 88, height: 26)
        divider.frame = NSRect(x: 20, y: 62, width: bounds.width - 40, height: 1)
        scroll.frame = NSRect(x: 8, y: 68, width: bounds.width - 16, height: max(0, bounds.height - 76))
        table.tableColumns.first?.width = scroll.contentSize.width
        emptyTitle.frame = NSRect(x: 24, y: 83, width: bounds.width - 48, height: 20)
        emptyDetail.frame = NSRect(x: 24, y: 108, width: bounds.width - 48, height: 18)
    }
    func reset() {
        searchField.stringValue = ""
        showKeys = false
        render(state.reset())
        updateHints()
        window?.makeFirstResponder(searchField)
    }
    func update(entries: [SearchEntry], usage: [String: Int], lastUsed: [String: Double]) {
        render(state.update(entries: entries, usage: usage, lastUsed: lastUsed))
    }
    func updateUsage(_ usage: [String: Int], lastUsed: [String: Double]) {
        render(state.updateUsage(usage, lastUsed: lastUsed))
    }
    func updateEntries(_ entries: [SearchEntry]) {
        render(state.updateEntries(entries))
    }
    func selectFilter(_ index: Int) {
        render(state.selectFilter(index, query: searchField.stringValue))
    }
    @objc private func nextScope() {
        selectFilter(filter == nil ? 1 : filter == .application ? 2 : 0)
        window?.makeFirstResponder(searchField)
    }
    func setQuickKeys(_ visible: Bool) {
        guard showKeys != visible else { return }
        showKeys = visible
        updateHints()
    }
    @objc private func clicked() {
        guard results.indices.contains(table.clickedRow) else { return }
        onExecute?(results[table.clickedRow])
    }
    func executeSelected() {
        guard let entry = state.selectedEntry else { return }
        onExecute?(entry)
    }
    func execute(at index: Int) { if let entry = state.entry(at: index) { onExecute?(entry) } }
    func controlTextDidBeginEditing(_ obj: Notification) {
        if let editor = searchField.currentEditor() as? NSTextView {
            editor.allowsUndo = true
            editor.insertionPointColor = Theme.text
            editor.selectedTextAttributes = [.backgroundColor: Theme.selection, .foregroundColor: Theme.text]
        }
    }
    func controlTextDidChange(_ obj: Notification) { updateResults() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            move(1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            move(-1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            executeSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onDismiss?()
            return true
        case #selector(NSResponder.insertTab(_:)):
            selectFilter(filter == nil ? 1 : filter == .application ? 2 : 0)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            selectFilter(filter == nil ? 2 : filter == .application ? 0 : 1)
            return true
        default: return false
        }
    }
    private func move(_ delta: Int) {
        render(state.moveSelection(delta))
    }
    func updateResults(preserveSelection: Bool = false) {
        render(state.setQuery(searchField.stringValue, preserveSelection: preserveSelection))
    }
    private func render(_ change: LauncherState.Change) {
        guard !change.isEmpty else { return }
        PerformanceTrace.measure("LauncherUpdate") { apply(change) }
    }
    private func apply(_ change: LauncherState.Change) {
        if change.filterChanged {
            let name = filter == .application ? "Apps" : filter == .window ? "Windows" : "All"
            scopeButton.title = name + "  ⇥"
            scopeButton.contentTintColor = Theme.accent
            scopeButton.setAccessibilityLabel("Search category: " + name)
            emptyDetail.stringValue =
                filter == nil
                ? "Try another app name or window command." : "Try another name, or switch to All."
        }
        if change.hasQueryChanged {
            scopeButton.isHidden = !state.hasQuery
            divider.isHidden = !state.hasQuery
        }
        if change.queryChanged {
            window?.invalidateCursorRects(for: searchField)
            if let editor = searchField.currentEditor() as? NSTextView {
                window?.invalidateCursorRects(for: editor)
            }
        }
        applyingSelection = true
        defer { applyingSelection = false }
        // Refresh row count before resizing can trigger AppKit layout. Query or
        // history changes with identical results retain the existing cells.
        if change.resultsChanged {
            resultReloadCount += 1
            table.reloadData()
        }
        if change.resultsChanged || change.hasQueryChanged {
            let height: CGFloat =
                !state.hasQuery
                ? Self.initialHeight
                : results.isEmpty
                    ? 140
                    : 76 + CGFloat(min(results.count, 7)) * Theme.rowHeight + (results.count > 7 ? 20 : 0)
            emptyTitle.isHidden = !state.hasQuery || !results.isEmpty
            emptyDetail.isHidden = !state.hasQuery || !results.isEmpty
            scroll.isHidden = results.isEmpty
            onHeightChange?(height)
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
        if change.resultsChanged || change.selectionChanged {
            if let index = state.selectedIndex {
                if table.selectedRow != index {
                    table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                }
                table.scrollRowToVisible(index)
            } else if table.selectedRow >= 0 {
                table.deselectAll(nil)
            }
        }
        if change.resultsChanged || change.selectionChanged { updateHints() }
    }
    func invalidateIcons(paths: Set<String>) {
        icons.invalidate(paths: paths)
        for index in visibleRows() {
            guard let entry = state.entry(at: index), let path = entry.path, paths.contains(path),
                let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? ResultCell
            else { continue }
            cell.configure(
                entry, index: index, icons: icons, selected: index == state.selectedIndex,
                showKeys: showKeys)
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? ResultCell) ?? ResultCell()
        cell.identifier = id
        cell.configure(
            results[row], index: row, icons: icons, selected: row == table.selectedRow, showKeys: showKeys)
        return cell
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ResultRow() }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !applyingSelection else { return }
        state.select(index: table.selectedRow)
        updateHints()
    }
    private func visibleRows() -> Range<Int> {
        let visible = table.rows(in: table.visibleRect)
        guard visible.location != NSNotFound else { return 0..<0 }
        let end = min(visible.location + visible.length, results.count)
        return min(visible.location, end)..<end
    }
    private func updateHints() {
        for index in visibleRows() {
            (table.view(atColumn: 0, row: index, makeIfNecessary: false) as? ResultCell)?
                .hint(index: index, selected: index == table.selectedRow, showKeys: showKeys)
        }
    }
}
