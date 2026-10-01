import AppKit
import CielCore
import QuartzCore

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
    private var representedID: String?
    private var currentIconPath: String?
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
        representedID = entry.id
        currentIconPath = entry.path
        titleLabel.stringValue = entry.title
        toolTip = entry.title
        hint(index: index, selected: selected, showKeys: showKeys)
        appIcon.isHidden = entry.kind == .window
        commandIcon.isHidden = entry.kind != .window
        if let path = entry.path {
            appIcon.image = icons.icon(for: path) { [weak self] loadedPath, image in
                guard let self, self.representedID == entry.id, self.currentIconPath == loadedPath else {
                    return
                }
                self.appIcon.image = image
            }
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
