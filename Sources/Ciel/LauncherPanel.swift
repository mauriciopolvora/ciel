import AppKit

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
