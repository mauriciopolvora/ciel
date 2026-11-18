import AppKit
import CielCore
import QuartzCore

final class ActionIcon: NSView {
    var action: WindowAction? { didSet { needsDisplay = true } }
    var line = Theme.secondary { didSet { needsDisplay = true } }
    var ink = Theme.text { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let screen = bounds.insetBy(dx: 2, dy: 5)
        let border = NSBezierPath(roundedRect: screen, xRadius: 3, yRadius: 3)
        line.setStroke()
        border.lineWidth = 1.2
        border.stroke()
        if let unit = action?.unitRect {
            let area = screen.insetBy(dx: 2.5, dy: 2.5)
            let part = CGRect(
                x: area.minX + unit.minX * area.width, y: area.minY + unit.minY * area.height,
                width: unit.width * area.width, height: unit.height * area.height)
            ink.withAlphaComponent(0.8).setFill()
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
                .withSymbolConfiguration(.init(paletteColors: [ink]))?.draw(
                    in: screen.insetBy(dx: 4, dy: 1))
        }
    }
}

final class ResultRow: NSTableRowView {
    private let hoverLayer = CAShapeLayer()
    private var tracking: NSTrackingArea?
    private var pointerInside = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        hoverLayer.fillColor = Theme.cg(Theme.selection.withAlphaComponent(0.7), in: self)
        hoverLayer.opacity = 0
        layer?.addSublayer(hoverLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        hoverLayer.fillColor = Theme.cg(Theme.selection.withAlphaComponent(0.7), in: self)
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
    private func showHover(animated: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated && !Theme.reduceMotion ? Theme.hoverDuration : 0)
        CATransaction.setAnimationTimingFunction(Theme.easeOut)
        hoverLayer.opacity = pointerInside && !isSelected ? 1 : 0
        CATransaction.commit()
    }
    override var isSelected: Bool {
        didSet { showHover(animated: false) }
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        pointerInside = false
        showHover(animated: false)
    }
    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        showHover(animated: true)
    }
    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        showHover(animated: true)
    }
    override func drawSelection(in dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: Theme.rowRadius, yRadius: Theme.rowRadius)
        Theme.accent.setFill()
        path.fill()
        guard Theme.increaseContrast else { return }
        let ring = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1.5, dy: 2.5), xRadius: Theme.rowRadius - 0.5,
            yRadius: Theme.rowRadius - 0.5)
        Theme.border.setStroke()
        ring.lineWidth = 1
        ring.stroke()
    }
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

final class ResultCell: NSTableCellView {
    let appIcon = NSImageView()
    let commandIcon = ActionIcon()
    let titleLabel = Theme.label("", size: 15, weight: .medium)
    let hintLabel = Theme.label("", size: 12, weight: .medium, color: Theme.secondary)
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
    func mark(index: Int, selected: Bool, showKeys: Bool) {
        hintLabel.stringValue = showKeys && index < 9 ? "⌘\(index + 1)" : selected ? "↵" : ""
        let quiet = selected ? Theme.selectedSecondary : Theme.secondary
        titleLabel.textColor = selected ? Theme.selectedText : Theme.text
        hintLabel.textColor = quiet
        appIcon.contentTintColor = quiet
        commandIcon.line = quiet
        commandIcon.ink = selected ? Theme.selectedText : Theme.text
    }
    func configure(_ entry: SearchEntry, index: Int, icons: IconCache, selected: Bool, showKeys: Bool) {
        representedID = entry.id
        currentIconPath = entry.path
        titleLabel.stringValue = entry.title
        toolTip = entry.title
        mark(index: index, selected: selected, showKeys: showKeys)
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
            appIcon.image = entry.utility.flatMap {
                NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: nil)
            }
        }
        commandIcon.action = entry.action
        setAccessibilityElement(true)
        setAccessibilityLabel(entry.title + ", " + entry.subtitle)
    }
}

extension UtilityCommand {
    var symbolName: String {
        switch self {
        case .settings: "slider.horizontal.3"
        case .rescan: "arrow.clockwise"
        }
    }
}
