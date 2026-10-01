import AppKit
import QuartzCore

/// Shared monochrome tokens. Ciel keeps the same black surface in every appearance.
@MainActor enum Theme {
    static let accent = NSColor(white: 0.92, alpha: 1)
    static let text = NSColor(white: 0.94, alpha: 1)
    static let secondary = NSColor(white: 0.62, alpha: 1)
    static let error = NSColor.systemRed
    static let success = text
    static let surface = NSColor(white: 0.035, alpha: 1)
    static let group = NSColor(white: 0.075, alpha: 1)
    static let selection = NSColor(white: 0.14, alpha: 1)
    static let border = NSColor(white: 0.30, alpha: 1)
    static let rowHeight: CGFloat = 44
    static let panelRadius: CGFloat = 16
    static let groupRadius: CGFloat = 10
    static let statusRadius: CGFloat = 12
    static let rowRadius: CGFloat = 8
    static let hoverDuration: CFTimeInterval = 0.12
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            || !UserDefaults.standard.bool(forKey: "animations")
    }
    static var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }

    static func cg(_ color: NSColor, in view: NSView) -> CGColor {
        var result: CGColor!
        view.effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }
    static func label(
        _ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Theme.text
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}

/// Native button behavior and accessibility, with a neutral switch track.
final class MonochromeSwitch: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        setButtonType(.switch)
        title = ""
        isBordered = false
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 1, dy: 4)
        let outline = NSBezierPath(roundedRect: track, xRadius: 10, yRadius: 10)
        (state == .on ? NSColor(white: isHighlighted ? 0.42 : 0.33, alpha: 1) : Theme.group).setFill()
        outline.fill()
        Theme.border.setStroke()
        outline.lineWidth = 1
        outline.stroke()
        let thumb = NSRect(
            x: state == .on ? track.maxX - 18 : track.minX + 2,
            y: track.midY - 8, width: 16, height: 16)
        (isEnabled ? Theme.text : Theme.secondary).setFill()
        NSBezierPath(ovalIn: thumb).fill()
        if window?.firstResponder === self, window?.isKeyWindow == true {
            Theme.text.setStroke()
            outline.lineWidth = 2
            outline.stroke()
        }
    }
}

/// Opaque preference groups and panels update for appearance and contrast changes.
final class SurfaceView: FlippedView {
    var isGroup = false
    var isFloating = false
    private var observer: NotificationObservation?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        observer = NotificationObservation(
            center: NSWorkspace.shared.notificationCenter,
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        ) { [weak self] in self?.refreshSurface() }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshSurface()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshSurface()
    }
    func refreshSurface() {
        layer?.backgroundColor = Theme.cg(isGroup ? Theme.group : Theme.surface, in: self)
        layer?.cornerRadius = isFloating ? Theme.statusRadius : isGroup ? Theme.groupRadius : 0
        layer?.borderWidth = isGroup || isFloating ? 1 : 0
        layer?.borderColor = Theme.cg(
            Theme.border.withAlphaComponent(Theme.increaseContrast ? 1 : 0.35), in: self)
    }
}
