import AppKit

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
