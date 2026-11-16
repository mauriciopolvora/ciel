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
    private let surface = LauncherDragSurface()
    private var displayObserver: Cleanup?
    private var designObserver: Cleanup?
    private var showKeys = false
    private var applyingSelection = false
    private(set) var style: LauncherStyle

    static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    override init(frame frameRect: NSRect) {
        style = LauncherStyle.make(DesignPreview().launcher, systemDark: Self.systemIsDark)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        surface.wantsLayer = true
        addSubview(surface)
        divider.wantsLayer = true
        addSubview(divider)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.placeholderString = nil
        searchField.setAccessibilityLabel("Search apps and commands")
        addSubview(searchField)
        scopeButton.bezelStyle = .inline
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
        addSubview(emptyTitle)
        addSubview(emptyDetail)
        restyle()
        displayObserver = NSWorkspace.shared.notificationCenter.observe(
            NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        ) { [weak self] in
            self?.refreshDesign(force: true)
        }
        designObserver = NotificationCenter.default.observe(.designPreviewChanged) { [weak self] in
            self?.refreshDesign()
        }
        render(.initial)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Applies the Design preview choice. Graphite follows the system appearance, which this reads on every open
    /// because a nonactivating panel may not receive the theme change notification while the app is inactive.
    func refreshDesign(force: Bool = false) {
        let next = LauncherStyle.make(DesignPreview().launcher, systemDark: Self.systemIsDark)
        guard force || next.design != style.design || next.dark != style.dark else { return }
        style = next
        restyle()
    }
    func applyDesign(_ design: LauncherDesign, systemDark: Bool) {
        style = LauncherStyle.make(design, systemDark: systemDark)
        restyle()
    }
    private func restyle() {
        let palette = style.palette
        appearance = NSAppearance(named: style.dark ? .darkAqua : .aqua)
        layer?.cornerRadius = style.panelRadius
        surface.cornerRadius = style.panelRadius
        surface.palette = palette
        searchField.font = style.queryFont
        searchField.textColor = palette.ink
        scopeButton.font = style.scopeFont
        scopeButton.contentTintColor = style.scopeTint
        for (label, font, color) in [
            (emptyTitle, style.noMatchFont, palette.ink),
            (emptyDetail, style.noMatchDetailFont, palette.muted),
        ] {
            label.font = font
            label.textColor = color
            label.alignment = style.noMatchAlignment
        }
        divider.isHidden = style.dividerInset == nil || !state.hasQuery
        table.rowHeight = style.rowHeight
        tintEditor()
        updateSurface()
        applyingSelection = true
        defer { applyingSelection = false }
        table.reloadData()
        if let index = state.selectedIndex {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            table.scrollRowToVisible(index)
        }
        resize()
        updateHints()
    }
    private func tintEditor() {
        (searchField.currentEditor() as? MonochromeFieldEditor)?.tint(
            ink: style.palette.ink, highlight: style.palette.textHighlight)
    }
    private func updateSurface() {
        layer?.borderColor = Theme.cg(style.palette.ring, in: self)
        divider.layer?.backgroundColor = Theme.cg(style.palette.divider, in: self)
        surface.needsDisplay = true
        table.needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurface()
    }
    override func layout() {
        super.layout()
        let width = bounds.width
        let header = Self.initialHeight
        surface.frame = bounds
        let queryHeight = style.queryHeight
        searchField.frame = NSRect(
            x: style.queryX, y: ((header - queryHeight) / 2).rounded(.down),
            width: width - style.queryX - (scopeButton.isHidden ? 24 : 116), height: queryHeight)
        scopeButton.frame = NSRect(x: width - 108, y: 21, width: 88, height: 26)
        let inset = style.dividerInset ?? 0
        divider.frame = NSRect(x: inset, y: header - 1, width: width - inset * 2, height: 1)
        let top = header + style.topGap
        scroll.frame = NSRect(
            x: style.rowInset, y: top, width: width - style.rowInset * 2,
            height: max(0, bounds.height - top - style.bottomPad))
        table.tableColumns.first?.width = scroll.contentSize.width
        let textX = style.noMatchAlignment == .left ? style.rowInset + 11 + style.iconSize + 10 : 24
        let textWidth = width - textX - 24
        emptyTitle.frame = NSRect(x: textX, y: top + 15, width: textWidth, height: 20)
        emptyDetail.frame = NSRect(x: textX, y: top + 40, width: textWidth, height: 18)
    }
    func reset() {
        refreshDesign()
        searchField.stringValue = ""
        showKeys = false
        render(state.reset())
        updateHints()
        window?.makeFirstResponder(searchField)
        tintEditor()
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
            let palette = style.palette
            editor.allowsUndo = true
            tintEditor()
            editor.insertionPointColor = palette.ink
            editor.selectedTextAttributes = [
                .backgroundColor: palette.textHighlight, .foregroundColor: palette.ink,
            ]
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
            scopeButton.setAccessibilityLabel("Search category: " + name)
            emptyDetail.stringValue =
                filter == nil
                ? "Try another app name or window command." : "Try another name, or switch to All."
        }
        if change.hasQueryChanged {
            scopeButton.isHidden = !state.hasQuery
            divider.isHidden = style.dividerInset == nil || !state.hasQuery
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
        if change.resultsChanged || change.hasQueryChanged { resize() }
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
    private func resize() {
        emptyTitle.isHidden = !state.hasQuery || !results.isEmpty
        emptyDetail.isHidden = !state.hasQuery || !results.isEmpty
        scroll.isHidden = results.isEmpty
        onHeightChange?(style.height(results: results.count, hasQuery: state.hasQuery))
        needsLayout = true
        layoutSubtreeIfNeeded()
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
        cell.style = style
        cell.configure(
            results[row], index: row, icons: icons, selected: row == table.selectedRow, showKeys: showKeys)
        return cell
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ResultRow(style: style)
    }
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
                .mark(index: index, selected: index == table.selectedRow, showKeys: showKeys)
        }
    }
}
