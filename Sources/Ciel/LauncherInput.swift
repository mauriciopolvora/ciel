import AppKit

class FlippedView: NSView { override var isFlipped: Bool { true } }

/// Draws the panel surface in `draw(_:)` rather than in sublayers, so smoke captures show it.
final class LauncherDragSurface: FlippedView {
    var palette = LauncherPalette.inverse { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = Theme.panelRadius
    override func draw(_ dirtyRect: NSRect) {
        if palette.surfaceTop == palette.surfaceBottom {
            palette.surfaceTop.setFill()
            bounds.fill()
        } else {
            NSGradient(starting: palette.surfaceTop, ending: palette.surfaceBottom)?.draw(
                from: NSPoint(x: 0, y: 0), to: NSPoint(x: 0, y: bounds.height), options: [])
        }
        if let highlight = palette.highlight {
            highlight.setFill()
            NSRect(x: cornerRadius, y: 1, width: bounds.width - cornerRadius * 2, height: 1).fill()
        }
    }
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

/// Ignores the caret and selection colors AppKit sets when the editor attaches, keeping the ones from `tint`.
final class MonochromeFieldEditor: NSTextView {
    private var ink = Theme.text
    private var highlight = Theme.selection
    func tint(ink: NSColor, highlight: NSColor) {
        self.ink = ink
        self.highlight = highlight
        super.insertionPointColor = ink
        super.selectedTextAttributes = [.backgroundColor: highlight, .foregroundColor: ink]
        needsDisplay = true
    }
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
        get { ink }
        set { super.insertionPointColor = ink }
    }
    override var selectedTextAttributes: [NSAttributedString.Key: Any] {
        get { [.backgroundColor: highlight, .foregroundColor: ink] }
        set { super.selectedTextAttributes = [.backgroundColor: highlight, .foregroundColor: ink] }
    }
}
