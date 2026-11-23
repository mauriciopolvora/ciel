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
    static let selectedText = NSColor(white: 0.07, alpha: 1)
    static let selectedSecondary = NSColor(white: 0.36, alpha: 1)
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

final class TextButton: NSButton {
    private let size: CGFloat
    private let color: NSColor

    init(size: CGFloat = 12, color: NSColor = Theme.text, target: AnyObject?, action: Selector?) {
        self.size = size
        self.color = color
        super.init(frame: .zero)
        isBordered = false
        self.target = target
        self.action = action
    }
    required init?(coder: NSCoder) { fatalError() }

    var text: String {
        get { title }
        set {
            attributedTitle = NSAttributedString(
                string: newValue,
                attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color])
        }
    }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

final class MenuRecorder: ShortcutRecorder {
    required init(shortcut: Shortcut?, onRecord: @escaping (Shortcut?) -> Void) {
        super.init(shortcut: shortcut, onRecord: onRecord)
        image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)
        imagePosition = .imageTrailing
        imageHugsTitle = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func start() {
        let menu = NSMenu()
        var choices = [SpotlightShortcuts.commandSpace, Shortcut.launcher]
        if let shortcut, !choices.contains(shortcut) { choices.insert(shortcut, at: 0) }
        for choice in choices {
            let item = NSMenuItem(title: choice.display, action: #selector(pick), keyEquivalent: "")
            if choice == SpotlightShortcuts.commandSpace {
                let title = NSMutableAttributedString(
                    string: choice.display, attributes: [.font: NSFont.menuFont(ofSize: 0)])
                title.append(
                    NSAttributedString(
                        string: "  Replaces Spotlight",
                        attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: Theme.secondary]))
                item.attributedTitle = title
            }
            item.target = self
            item.representedObject = choice
            item.state = choice == shortcut ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Record Shortcut…", action: #selector(record), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.height + 4 : -4), in: self)
    }
    @objc private func pick(_ item: NSMenuItem) { onRecord?(item.representedObject as? Shortcut) }
    @objc private func record() { super.start() }
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
