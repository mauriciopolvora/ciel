import AppKit
import CielCore
import QuartzCore

final class ActionIcon: NSView {
    var action: WindowAction? { didSet { needsDisplay = true } }
    var line = Theme.secondary { didSet { needsDisplay = true } }
    var ink = Theme.text { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let size = bounds.width
        let screen = bounds.insetBy(dx: size * 0.07, dy: size * 0.18)
        let border = NSBezierPath(roundedRect: screen, xRadius: size * 0.1, yRadius: size * 0.1)
        line.setStroke()
        border.lineWidth = size < 24 ? 1 : 1.2
        border.stroke()
        if let unit = action?.unitRect {
            let area = screen.insetBy(dx: size * 0.09, dy: size * 0.09)
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
                    in: screen.insetBy(dx: size * 0.14, dy: size * 0.036))
        }
    }
}

final class ResultRow: NSTableRowView {
    private let style: LauncherStyle
    private let hoverLayer = CAShapeLayer()
    private var tracking: NSTrackingArea?
    init(style: LauncherStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        hoverLayer.opacity = 0
        layer?.addSublayer(hoverLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    private var plate: NSRect {
        switch style.selection {
        case .inverse: bounds.insetBy(dx: 1, dy: 2)
        case .raised: bounds.insetBy(dx: 2, dy: 3)
        case .bar: bounds.insetBy(dx: 0, dy: 1)
        }
    }
    override func layout() {
        super.layout()
        hoverLayer.fillColor = Theme.cg(style.palette.hover, in: self)
        hoverLayer.path = CGPath(
            roundedRect: plate, cornerWidth: style.rowRadius, cornerHeight: style.rowRadius, transform: nil)
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
        CATransaction.setAnimationDuration(Theme.reduceMotion ? 0 : style.hoverDuration)
        CATransaction.setDisableActions(style.hoverDuration == 0)
        CATransaction.setAnimationTimingFunction(Theme.easeOut)
        hoverLayer.opacity = visible && !isSelected ? 1 : 0
        CATransaction.commit()
    }
    override func mouseEntered(with event: NSEvent) { hover(true) }
    override func mouseExited(with event: NSEvent) { hover(false) }
    override func drawSelection(in dirtyRect: NSRect) {
        let palette = style.palette
        let path = NSBezierPath(roundedRect: plate, xRadius: style.rowRadius, yRadius: style.rowRadius)
        NSGraphicsContext.saveGraphicsState()
        if let color = palette.selectionShadow {
            let shadow = NSShadow()
            shadow.shadowColor = color
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 3
            shadow.set()
        }
        palette.selectionFill.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        if let ring = palette.selectionRing {
            let edge = NSBezierPath(
                roundedRect: plate.insetBy(dx: 0.5, dy: 0.5), xRadius: style.rowRadius - 0.5,
                yRadius: style.rowRadius - 0.5)
            ring.setStroke()
            edge.lineWidth = 1
            edge.stroke()
        }
        if let bar = palette.bar {
            bar.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: plate.minX, y: plate.minY + 7, width: 2, height: plate.height - 14),
                xRadius: 1, yRadius: 1
            ).fill()
        }
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
    var style = LauncherStyle.make(.a, systemDark: true) {
        didSet {
            guard style.titleFont != oldValue.titleFont || style.iconSize != oldValue.iconSize else { return }
            titleLabel.font = style.titleFont
            hintLabel.font = style.hintFont
            needsLayout = true
        }
    }
    private var representedID: String?
    private var currentIconPath: String?
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [appIcon, commandIcon, titleLabel, hintLabel] { addSubview(view) }
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        hintLabel.alignment = .right
        titleLabel.font = style.titleFont
        hintLabel.font = style.hintFont
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let icon = style.iconSize
        let middle = bounds.height / 2
        appIcon.frame = NSRect(x: 12, y: middle - (icon - 2) / 2, width: icon - 2, height: icon - 2)
        commandIcon.frame = NSRect(x: 11, y: middle - icon / 2, width: icon, height: icon)
        let titleX = 11 + icon + (icon < 24 ? 10 : 12)
        titleLabel.frame = NSRect(x: titleX, y: middle - 10.5, width: bounds.width - titleX - 54, height: 21)
        hintLabel.frame = NSRect(x: bounds.width - 48, y: middle - 9, width: 32, height: 18)
    }
    func mark(index: Int, selected: Bool, showKeys: Bool) {
        hintLabel.stringValue = showKeys && index < 9 ? "⌘\(index + 1)" : selected ? "↵" : ""
        let palette = style.palette
        titleLabel.textColor = selected ? palette.selectedTitle : palette.title
        hintLabel.textColor = selected ? palette.selectedMuted : palette.muted
        appIcon.contentTintColor = selected ? palette.selectedMuted : palette.muted
        commandIcon.line = selected ? palette.selectedMuted : palette.muted
        commandIcon.ink = selected ? palette.selectedTitle : palette.title
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
