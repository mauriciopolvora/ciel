import AppKit
import CielCore
import QuartzCore

class FlippedView: NSView { override var isFlipped: Bool { true } }

final class LauncherDragSurface: FlippedView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { (window as? LauncherPanel)?.drag(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

final class LauncherSearchField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        super.resetCursorRects()
        if stringValue.isEmpty { addCursorRect(bounds, cursor: .openHand) }
    }
    override func mouseDown(with event: NSEvent) {
        if stringValue.isEmpty, let panel = window as? LauncherPanel {
            panel.drag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
}

/// Keep native editing behavior while removing the system accent from the caret and selection.
final class MonochromeFieldEditor: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        super.resetCursorRects()
        if string.isEmpty { addCursorRect(bounds, cursor: .openHand) }
    }
    override func mouseDown(with event: NSEvent) {
        if string.isEmpty, let panel = window as? LauncherPanel {
            panel.drag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
    override var insertionPointColor: NSColor? {
        get { Theme.text }
        set { super.insertionPointColor = Theme.text }
    }
    override var selectedTextAttributes: [NSAttributedString.Key: Any] {
        get { [.backgroundColor: Theme.selection, .foregroundColor: Theme.text] }
        set {
            super.selectedTextAttributes = [.backgroundColor: Theme.selection, .foregroundColor: Theme.text]
        }
    }
}

final class LauncherPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuickOpen: ((Int) -> Void)?
    var onModifiers: ((Bool) -> Void)?
    var onDragEnd: ((Bool) -> Void)?
    var onDragModifiersChange: (() -> Void)?
    private(set) var isDragging = false
    func drag(with event: NSEvent) {
        guard !isDragging else { return }
        let origin = frame.origin
        let start = screenPoint(for: event)
        isDragging = true
        NSCursor.closedHand.push()
        defer {
            NSCursor.pop()
            isDragging = false
            onDragEnd?(origin != frame.origin)
        }
        // Track our own mouse sequence so the guide preview and final snap share
        // one lifecycle. No global input monitor or idle timer is needed.
        trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp, .flagsChanged], timeout: 0.1,
            mode: .eventTracking
        ) { event, stop in
            guard let event else {
                if NSEvent.pressedMouseButtons & 1 == 0 { stop.pointee = true }
                return
            }
            if event.type == .flagsChanged {
                self.onDragModifiersChange?()
                return
            }
            let pointer = self.screenPoint(for: event)
            let dx = pointer.x - start.x
            let dy = pointer.y - start.y
            if hypot(dx, dy) >= 3 {
                self.setFrameOrigin(CGPoint(x: origin.x + dx, y: origin.y + dy))
            }
            if event.type == .leftMouseUp { stop.pointee = true }
        }
    }
    private func screenPoint(for event: NSEvent) -> CGPoint {
        if let point = event.cgEvent?.location {
            return CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        }
        return convertPoint(toScreen: event.locationInWindow)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            // Accessory panels have no foreground Edit menu. Route standard text shortcuts
            // directly to the native field editor.
            if let editor = firstResponder as? NSTextView {
                switch event.charactersIgnoringModifiers {
                case "a":
                    editor.selectAll(nil)
                    return true
                case "c":
                    editor.copy(nil)
                    return true
                case "x":
                    editor.cut(nil)
                    return true
                case "v":
                    editor.paste(nil)
                    return true
                case "z":
                    if event.modifierFlags.contains(.shift) {
                        editor.undoManager?.redo()
                    } else {
                        editor.undoManager?.undo()
                    }
                    return true
                default: break
                }
            }
            if event.charactersIgnoringModifiers == "," {
                onSettings?()
                return true
            }
            if let character = event.charactersIgnoringModifiers, let number = Int(character),
                (1...9).contains(number)
            {
                onQuickOpen?(number - 1)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    override func flagsChanged(with event: NSEvent) {
        onModifiers?(event.modifierFlags.contains(.command))
        super.flagsChanged(with: event)
    }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

final class ActionIcon: NSView {
    var action: WindowAction? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let screen = bounds.insetBy(dx: 2, dy: 5)
        let border = NSBezierPath(roundedRect: screen, xRadius: 3, yRadius: 3)
        Theme.secondary.setStroke()
        border.lineWidth = 1.2
        border.stroke()
        if let unit = action?.unitRect {
            let area = screen.insetBy(dx: 2.5, dy: 2.5)
            let part = CGRect(
                x: area.minX + unit.minX * area.width, y: area.minY + unit.minY * area.height,
                width: unit.width * area.width, height: unit.height * area.height)
            Theme.text.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: part, xRadius: 0.8, yRadius: 0.8).fill()
        } else {
            let symbol =
                action == .nextDisplay
                ? "arrow.right"
                : action == .previousDisplay
                    ? "arrow.left"
                    : action == .restore
                        ? "arrow.uturn.backward"
                        : action == .minimize ? "chevron.down" : "rectangle.center.inset.filled"
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [Theme.text]))?.draw(
                    in: screen.insetBy(dx: 4, dy: 1))
        }
    }
}

final class ResultRow: NSTableRowView {
    private let hoverLayer = CAShapeLayer()
    private var tracking: NSTrackingArea?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        hoverLayer.fillColor = Theme.cg(Theme.selection.withAlphaComponent(0.45), in: self)
        hoverLayer.opacity = 0
        layer?.addSublayer(hoverLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        hoverLayer.fillColor = Theme.cg(Theme.selection.withAlphaComponent(0.45), in: self)
        hoverLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 2), cornerWidth: Theme.rowRadius,
            cornerHeight: Theme.rowRadius, transform: nil)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    private func hover(_ visible: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(Theme.reduceMotion ? 0 : Theme.hoverDuration)
        CATransaction.setAnimationTimingFunction(Theme.easeOut)
        hoverLayer.opacity = visible && !isSelected ? 1 : 0
        CATransaction.commit()
    }
    override func mouseEntered(with event: NSEvent) { hover(true) }
    override func mouseExited(with event: NSEvent) { hover(false) }
    override func drawSelection(in dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: Theme.rowRadius, yRadius: Theme.rowRadius)
        Theme.selection.setFill()
        path.fill()
        Theme.accent.withAlphaComponent(Theme.increaseContrast ? 1 : 0.16).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

final class ResultCell: NSTableCellView {
    let appIcon = NSImageView()
    let commandIcon = ActionIcon()
    let titleLabel = Theme.label("", size: 15)
    let hintLabel = Theme.label("", size: 12, color: Theme.secondary)
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [appIcon, commandIcon, titleLabel, hintLabel] { addSubview(view) }
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        hintLabel.alignment = .right
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        appIcon.frame = NSRect(x: 12, y: 9, width: 26, height: 26)
        commandIcon.frame = NSRect(x: 11, y: 8, width: 28, height: 28)
        titleLabel.frame = NSRect(x: 50, y: 12, width: bounds.width - 104, height: 21)
        hintLabel.frame = NSRect(x: bounds.width - 48, y: 13, width: 32, height: 18)
    }
    func hint(index: Int, selected: Bool, showKeys: Bool) {
        hintLabel.stringValue = showKeys && index < 9 ? "⌘\(index + 1)" : selected ? "↵" : ""
    }
    func configure(_ entry: SearchEntry, index: Int, icons: IconCache, selected: Bool, showKeys: Bool) {
        titleLabel.stringValue = entry.title
        toolTip = entry.title
        hint(index: index, selected: selected, showKeys: showKeys)
        appIcon.isHidden = entry.kind == .window
        commandIcon.isHidden = entry.kind != .window
        if let path = entry.path {
            appIcon.image = icons.icon(for: path)
        } else {
            appIcon.image = NSImage(
                systemSymbolName: entry.id == "settings" ? "slider.horizontal.3" : "arrow.clockwise",
                accessibilityDescription: nil)
        }
        appIcon.contentTintColor = Theme.secondary
        commandIcon.action = entry.action
        setAccessibilityElement(true)
        setAccessibilityLabel(entry.title + ", " + entry.subtitle)
    }
}

final class LauncherView: FlippedView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let width: CGFloat = 640
    static let initialHeight: CGFloat = 68
    var onExecute: ((SearchEntry) -> Void)?
    var onDismiss: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var entries: [SearchEntry] = [] { didSet { updateResults(preserveSelection: true) } }
    var usage: [String: Int] = [:]
    var lastUsed: [String: Double] = [:]
    private(set) var results: [SearchEntry] = []
    private(set) var filter: SearchEntry.Kind?
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
    private var displayObserver: NSObjectProtocol?
    private var showKeys = false

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
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.updateSurface() }
        selectFilter(0)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }

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
        selectFilter(0)
        window?.makeFirstResponder(searchField)
    }
    func selectFilter(_ index: Int) {
        filter = index == 1 ? .application : index == 2 ? .window : nil
        scopeButton.title = (filter == .application ? "Apps" : filter == .window ? "Windows" : "All") + "  ⇥"
        scopeButton.contentTintColor = Theme.accent
        scopeButton.setAccessibilityLabel(
            "Search category: " + (filter == .application ? "Apps" : filter == .window ? "Windows" : "All"))
        updateResults()
    }
    @objc private func nextScope() {
        selectFilter(filter == nil ? 1 : filter == .application ? 2 : 0)
        window?.makeFirstResponder(searchField)
    }
    func setQuickKeys(_ visible: Bool) {
        showKeys = visible
        updateHints()
    }
    @objc private func clicked() {
        guard results.indices.contains(table.clickedRow) else { return }
        onExecute?(results[table.clickedRow])
    }
    func executeSelected() {
        guard results.indices.contains(table.selectedRow) else { return }
        onExecute?(results[table.selectedRow])
    }
    func execute(at index: Int) { if results.indices.contains(index) { onExecute?(results[index]) } }
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
        guard !results.isEmpty else { return }
        let row = min(max(table.selectedRow + delta, 0), results.count - 1)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }
    func updateResults(preserveSelection: Bool = false) {
        let selectedID =
            preserveSelection && results.indices.contains(table.selectedRow)
            ? results[table.selectedRow].id : nil
        let hasQuery = !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        results =
            hasQuery
            ? SearchEngine.search(
                searchField.stringValue, entries: entries, kind: filter, usage: usage, lastUsed: lastUsed)
            : []
        scopeButton.isHidden = !hasQuery
        divider.isHidden = !hasQuery
        window?.invalidateCursorRects(for: searchField)
        if let editor = searchField.currentEditor() as? NSTextView {
            window?.invalidateCursorRects(for: editor)
        }
        // Refresh the table row count before resizing can trigger AppKit layout.
        table.reloadData()
        let height: CGFloat =
            !hasQuery
            ? Self.initialHeight
            : results.isEmpty
                ? 140 : 76 + CGFloat(min(results.count, 7)) * Theme.rowHeight + (results.count > 7 ? 20 : 0)
        onHeightChange?(height)
        needsLayout = true
        layoutSubtreeIfNeeded()
        if !results.isEmpty {
            let index = selectedID.flatMap { id in results.firstIndex { $0.id == id } } ?? 0
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            table.scrollRowToVisible(index)
        }
        emptyTitle.isHidden = !hasQuery || !results.isEmpty
        emptyDetail.isHidden = !hasQuery || !results.isEmpty
        scroll.isHidden = results.isEmpty
        emptyDetail.stringValue =
            filter == nil ? "Try another app name or window command." : "Try another name, or switch to All."
        updateHints()
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
    func tableViewSelectionDidChange(_ notification: Notification) { updateHints() }
    private func updateHints() {
        let visible = table.rows(in: table.visibleRect)
        guard visible.location != NSNotFound else { return }
        for index in visible.location..<(visible.location + visible.length) {
            (table.view(atColumn: 0, row: index, makeIfNecessary: false) as? ResultCell)?
                .hint(index: index, selected: index == table.selectedRow, showKeys: showKeys)
        }
    }
}

final class StatusHUD {
    private var panel: NSPanel?
    private var dismiss: DispatchWorkItem?
    func show(_ message: String, error: Bool = false) {
        dismiss?.cancel()
        panel?.orderOut(nil)
        let width: CGFloat = min(570, max(280, CGFloat(message.count) * 6.5 + 65))
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 54),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.appearance = NSAppearance(named: .darkAqua)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.ignoresMouseEvents = true
        let view = SurfaceView(frame: NSRect(x: 0, y: 0, width: width, height: 54))
        view.isFloating = true
        view.refreshSurface()
        view.layer?.masksToBounds = true
        let icon = NSImageView(frame: NSRect(x: 17, y: 17, width: 20, height: 20))
        icon.image = NSImage(
            systemSymbolName: error ? "exclamationmark.circle.fill" : "checkmark.circle.fill",
            accessibilityDescription: nil)
        icon.contentTintColor = error ? Theme.error : Theme.success
        view.addSubview(icon)
        let label = Theme.label(message, size: 12, weight: .medium)
        label.frame = NSRect(x: 47, y: 18, width: width - 60, height: 18)
        view.addSubview(label)
        p.contentView = view
        let screen =
            NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: frame.midX - width / 2, y: frame.minY + 90))
        }
        panel = p
        p.alphaValue = Theme.reduceMotion ? 1 : 0
        p.orderFrontRegardless()
        if !Theme.reduceMotion {
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.16
                p.animator().alphaValue = 1
            }
        }
        let work = DispatchWorkItem { [weak self, weak p] in
            guard let p else { return }
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = Theme.reduceMotion ? 0 : Theme.hoverDuration
                    p.animator().alphaValue = 0
                },
                completionHandler: {
                    p.orderOut(nil)
                    if self?.panel === p { self?.panel = nil }
                })
        }
        dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (error ? 4 : 1.6), execute: work)
    }
}
