import AppKit
import CielCore

final class LauncherPanel: NSPanel {
    let launcher: LauncherView
    let fieldEditor = MonochromeFieldEditor()
    var onSettings: (() -> Void)?
    private(set) var isDragging = false
    private let placements = LauncherPlacementStore()
    private let guides = LauncherGuides()
    private var anchor: CGPoint?
    private var presenting = false

    init() {
        let initial = NSRect(x: 0, y: 0, width: LauncherView.width, height: LauncherView.initialHeight)
        launcher = LauncherView(frame: initial)
        super.init(
            contentRect: initial, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        title = "Ciel"
        appearance = NSAppearance(named: .darkAqua)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        fieldEditor.isFieldEditor = true
        fieldEditor.insertionPointColor = Theme.text
        fieldEditor.selectedTextAttributes = [
            .backgroundColor: Theme.selection, .foregroundColor: Theme.text,
        ]
        contentView = launcher
        launcher.onDismiss = { [weak self] in self?.dismiss() }
        launcher.onHeightChange = { [weak self] height in self?.resize(toHeight: height) }
    }

    func present() {
        launcher.reset()
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        })
            ?? NSScreen.main
        {
            let area = screen.visibleFrame
            let placed =
                placements.placement(for: LauncherGuides.displayID(screen))?.frame(
                    size: frame.size, screen: area, headerHeight: LauncherView.initialHeight)
                ?? CGRect(
                    x: area.midX - frame.width / 2, y: area.minY + (area.height - frame.height) * 0.62,
                    width: frame.width, height: frame.height)
            setFrame(placed, display: true)
            anchor = CGPoint(x: placed.minX, y: placed.maxY)
        }
        presenting = true
        makeKeyAndOrderFront(nil)
        makeFirstResponder(launcher.searchField)
        presenting = false
    }

    func dismiss() {
        guides.hide()
        orderOut(nil)
    }

    private func resize(toHeight height: CGFloat) {
        guard frame.height != height else { return }
        var resized = frame
        resized.origin.y += resized.height - height
        resized.size.height = height
        if let anchor, let screen = screen ?? NSScreen.main {
            resized = LauncherPlacement.frame(anchor: anchor, size: resized.size, screen: screen.visibleFrame)
        }
        setFrame(resized, display: true)
    }

    func drag(with event: NSEvent) {
        guard !isDragging else { return }
        let origin = frame.origin
        let start = screenPoint(for: event)
        isDragging = true
        NSCursor.closedHand.push()
        defer {
            NSCursor.pop()
            isDragging = false
            dragEnded(moved: origin != frame.origin)
        }
        trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp, .flagsChanged], timeout: 0.1,
            mode: .eventTracking
        ) { event, stop in
            guard let event else {
                if NSEvent.pressedMouseButtons & 1 == 0 { stop.pointee = true }
                return
            }
            if event.type == .flagsChanged {
                self.guides.update(for: self)
                return
            }
            let pointer = self.screenPoint(for: event)
            let dx = pointer.x - start.x
            let dy = pointer.y - start.y
            if hypot(dx, dy) >= 3 {
                self.setFrameOrigin(CGPoint(x: origin.x + dx, y: origin.y + dy))
                self.guides.update(for: self)
            }
            if event.type == .leftMouseUp { stop.pointee = true }
        }
    }

    private func dragEnded(moved: Bool) {
        guides.hide()
        if moved, let screen = screen ?? NSScreen.main {
            let snap = LauncherPlacement.snap(
                frame, screen: screen.visibleFrame, headerHeight: LauncherView.initialHeight,
                enabled: !NSEvent.modifierFlags.contains(.option))
            setFrame(snap.frame, display: true)
            anchor = CGPoint(x: snap.frame.minX, y: snap.frame.maxY)
            placements.save(
                LauncherPlacement(
                    frame: snap.frame, screen: screen.visibleFrame, headerHeight: LauncherView.initialHeight),
                for: LauncherGuides.displayID(screen))
        }
        makeFirstResponder(launcher.searchField)
    }

    private func screenPoint(for event: NSEvent) -> CGPoint {
        if let point = event.cgEvent?.location {
            return CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        }
        return convertPoint(toScreen: event.locationInWindow)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        if !presenting && !isDragging { dismiss() }
    }

    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        (object as? NSTextField) === launcher.searchField
            ? fieldEditor : super.fieldEditor(createFlag, for: object)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            // Accessory apps have no Edit menu, so nothing else routes these shortcuts to the field editor.
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
                launcher.execute(at: number - 1)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        launcher.setQuickKeys(event.modifierFlags.contains(.command))
        super.flagsChanged(with: event)
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }
}
