import AppKit
import QuartzCore

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
    static let guide = NSColor.white
    static let rowHeight: CGFloat = 44
    static let panelRadius: CGFloat = 16
    static let groupRadius: CGFloat = 10
    static let statusRadius: CGFloat = 12
    static let rowRadius: CGFloat = 8
    static let hoverDuration: CFTimeInterval = 0.12
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            || !Preferences().animations
    }
    static var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    static var hairline: NSColor { border.withAlphaComponent(increaseContrast ? 1 : 0.35) }

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

final class MonochromeSwitch: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        setButtonType(.switch)
        title = ""
        isBordered = false
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 38, height: 28) }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 4, left: 1, bottom: 4, right: 1) }
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

class SurfaceView: FlippedView {
    var isGroup = false
    var isFloating = false
    var isCapsule = false
    private var observer: Cleanup?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        observer = NSWorkspace.shared.notificationCenter.observe(
            NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
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
        layer?.cornerRadius =
            isCapsule ? bounds.height / 2 : isFloating ? Theme.statusRadius : isGroup ? Theme.groupRadius : 0
        layer?.borderWidth = isGroup || isFloating ? 1 : 0
        layer?.borderColor = Theme.cg(Theme.hairline, in: self)
    }
}

final class Divider: SurfaceView {
    override func refreshSurface() { layer?.backgroundColor = Theme.cg(Theme.hairline, in: self) }
}

/// The grays of one launcher design. Only Graphite has a light palette, since it is the design that follows the
/// system appearance. Light hint grays stay at 0.42 or darker to keep 4.5:1 on the light surface.
@MainActor struct LauncherPalette {
    var surfaceTop: NSColor
    var surfaceBottom: NSColor
    var highlight: NSColor?
    var ring: NSColor
    var divider: NSColor
    var title: NSColor
    var selectedTitle: NSColor
    var muted: NSColor
    var selectedMuted: NSColor
    var selectionFill: NSColor
    var selectionRing: NSColor?
    var selectionShadow: NSColor?
    var bar: NSColor?
    var hover: NSColor
    var ink = Theme.text
    var textHighlight = Theme.selection

    static let inverse = LauncherPalette(
        surfaceTop: Theme.surface, surfaceBottom: Theme.surface, ring: Theme.border.withAlphaComponent(0.55),
        divider: Theme.border.withAlphaComponent(0.22), title: Theme.text,
        selectedTitle: NSColor(white: 0.07, alpha: 1), muted: Theme.secondary,
        selectedMuted: NSColor(white: 0.36, alpha: 1), selectionFill: Theme.accent,
        hover: Theme.selection.withAlphaComponent(0.7))

    static let graphiteDark = LauncherPalette(
        surfaceTop: NSColor(white: 0.115, alpha: 1), surfaceBottom: NSColor(white: 0.078, alpha: 1),
        highlight: NSColor(white: 1, alpha: 0.07), ring: NSColor(white: 1, alpha: 0.14),
        divider: NSColor(white: 1, alpha: 0.07), title: NSColor(white: 0.86, alpha: 1),
        selectedTitle: NSColor(white: 0.97, alpha: 1), muted: NSColor(white: 0.60, alpha: 1),
        selectedMuted: NSColor(white: 0.70, alpha: 1), selectionFill: NSColor(white: 0.195, alpha: 1),
        selectionRing: NSColor(white: 1, alpha: 0.09), selectionShadow: NSColor(white: 0, alpha: 0.45),
        hover: NSColor(white: 0.15, alpha: 1), ink: NSColor(white: 0.97, alpha: 1),
        textHighlight: NSColor(white: 0.30, alpha: 1))

    static let graphiteLight = LauncherPalette(
        surfaceTop: NSColor(white: 0.99, alpha: 1), surfaceBottom: NSColor(white: 0.95, alpha: 1),
        ring: NSColor(white: 0, alpha: 0.13), divider: NSColor(white: 0, alpha: 0.08),
        title: NSColor(white: 0.16, alpha: 1), selectedTitle: NSColor(white: 0.08, alpha: 1),
        muted: NSColor(white: 0.42, alpha: 1), selectedMuted: NSColor(white: 0.38, alpha: 1),
        selectionFill: NSColor(white: 1, alpha: 1), selectionRing: NSColor(white: 0, alpha: 0.08),
        selectionShadow: NSColor(white: 0, alpha: 0.14), hover: NSColor(white: 0.915, alpha: 1),
        ink: NSColor(white: 0.10, alpha: 1), textHighlight: NSColor(white: 0.80, alpha: 1))

    static let console = LauncherPalette(
        surfaceTop: NSColor(white: 0.012, alpha: 1), surfaceBottom: NSColor(white: 0.012, alpha: 1),
        ring: Theme.border.withAlphaComponent(0.4), divider: Theme.border.withAlphaComponent(0.3),
        title: Theme.secondary, selectedTitle: Theme.text, muted: NSColor(white: 0.50, alpha: 1),
        selectedMuted: Theme.secondary, selectionFill: NSColor(white: 0.10, alpha: 1), bar: Theme.accent,
        hover: NSColor(white: 0.055, alpha: 1))

    /// Opaque edges for Increase Contrast.
    func contrasted(dark: Bool) -> LauncherPalette {
        var palette = self
        let edge = dark ? Theme.border : NSColor(white: 0.45, alpha: 1)
        palette.ring = edge
        palette.divider = edge
        palette.selectionRing = edge
        return palette
    }
}
