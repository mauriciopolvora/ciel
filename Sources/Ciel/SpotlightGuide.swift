import AppKit

@MainActor final class SpotlightGuide: NSObject {
    enum Replacement { case offered, replaced, waiting }

    var held: Shortcut?
    weak var owner: PreferencesController?
    /// How long the card says the shortcut is free before it closes and the owner window comes back.
    var hold = Duration.milliseconds(1600)
    let card = SpotlightCard(frame: NSRect(origin: .zero, size: SpotlightCard.size))
    let companion: SettingsCompanion
    private var holding: Task<Void, Never>?
    let heading = Theme.label("", size: 20)
    let note = Theme.label("", size: 12, color: Theme.secondary)
    private let hotKeys: HotKeys
    private let spotlight: SpotlightShortcuts
    private let open: @MainActor (URL) -> Void
    private var rows: [(status: NSTextField, button: NSButton)] = []
    /// The state beside the launcher recorder. The recorder menu offers ⌘Space, so the caption only reports.
    let caption = Theme.label("", size: 12, color: Theme.secondary)

    var replacement: Replacement {
        if held != nil { return .waiting }
        let commandSpace = SpotlightShortcuts.commandSpace
        return hotKeys.shortcut(for: .launcher) == commandSpace && !spotlight.owns(commandSpace)
            ? .replaced : .offered
    }

    init(hotKeys: HotKeys, spotlight: SpotlightShortcuts, open: @escaping @MainActor (URL) -> Void) {
        self.hotKeys = hotKeys
        self.spotlight = spotlight
        self.open = open
        companion = SettingsCompanion(card: card, followsSheet: true)
        super.init()
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 2
    }

    /// The card under System Settings, or nil while it is closed.
    var shownCard: SpotlightCard.State? { companion.isShown ? card.state : nil }

    func row() -> [NSView] {
        let status = PreferencesController.status()
        let button = NSButton(title: "", target: self, action: #selector(act))
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        button.widthAnchor.constraint(equalToConstant: 120).isActive = true
        rows.append((status, button))
        return [status, button]
    }

    func choose(_ shortcut: Shortcut?) {
        guard let shortcut else {
            owner?.showMessage(HotKeyError.required.localizedDescription)
            return
        }
        holding?.cancel()
        holding = nil
        if spotlight.owns(shortcut) {
            held = shortcut
            owner?.showMessage("")
            open(SpotlightShortcuts.settingsURL)
            card.state = .turnOff(
                action: spotlight.action(holding: shortcut) ?? "", shortcut: shortcut.display)
            companion.show()
        } else {
            dismiss()
            take(shortcut)
        }
        owner?.refresh()
    }

    /// Binds the held shortcut once Spotlight lets it go, and says so on the card before it closes.
    func tick() {
        guard let held, !spotlight.owns(held) else { return }
        self.held = nil
        let taken = take(held)
        owner?.refresh()
        guard taken, companion.isShown else { return finish() }
        card.state = .freed(shortcut: held.display)
        holding = Task { [weak self, hold] in
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        dismiss()
        if owner?.window?.isVisible == true { owner?.present() }
    }

    /// Drops the held shortcut and closes the card, also during the success hold.
    func dismiss() {
        held = nil
        holding?.cancel()
        holding = nil
        companion.close()
    }

    @discardableResult private func take(_ shortcut: Shortcut) -> Bool {
        do {
            try hotKeys.update(.launcher, to: shortcut)
            owner?.showMessage("")
            return true
        } catch {
            owner?.showMessage(error.localizedDescription)
            return false
        }
    }

    func refresh() {
        let replacement = self.replacement
        let replaced = replacement == .replaced
        note.isHidden = held == nil
        if let held, let action = spotlight.action(holding: held) {
            heading.stringValue = "Free \(held.display) from Spotlight"
            note.stringValue =
                "In Keyboard Shortcuts, select Spotlight and turn off \(action). Ciel switches when \(held.display) is free."
        }
        for (status, button) in rows {
            button.isHidden = replaced
            button.title = held == nil ? "Use " + SpotlightShortcuts.commandSpace.display : "Open Settings…"
            status.stringValue = held != nil ? "Used by Spotlight" : replaced ? "Replaced" : ""
            status.textColor = held == nil ? Theme.success : Theme.secondary
        }
        caption.stringValue =
            switch replacement {
            case .offered: ""
            case .replaced: "Replaces Spotlight"
            case .waiting: "Used by Spotlight"
            }
    }

    @objc private func act() { choose(held ?? SpotlightShortcuts.commandSpace) }
}

/// Floats under System Settings with a miniature of the row to change, then says when the shortcut is free.
final class SpotlightCard: SurfaceView {
    enum State: Equatable {
        case turnOff(action: String, shortcut: String)
        case freed(shortcut: String)
    }

    static let size = NSSize(width: 300, height: 112)
    static let cycle: CFTimeInterval = 2.4
    private static let rowFrame = NSRect(x: 16, y: 16, width: 268, height: 32)
    private static let boxFrame = NSRect(x: 10, y: 9, width: 14, height: 14)
    var state = State.turnOff(action: "", shortcut: "") { didSet { refresh() } }
    private let row = CALayer()
    private let box = CALayer()
    private let fill = CALayer()
    private let tick = CAShapeLayer()
    private let action = Theme.label("", size: 12)
    private let shortcut = Theme.label("", size: 12, weight: .medium, color: Theme.secondary)
    private let title = Theme.label("", size: 13, weight: .medium)
    private let detail = Theme.label("", size: 12, color: Theme.secondary)

    override init(frame: NSRect) {
        super.init(frame: frame)
        isFloating = true
        row.frame = Self.rowFrame
        row.cornerRadius = Theme.rowRadius
        box.frame = Self.boxFrame
        box.cornerRadius = 4
        box.borderWidth = 1
        fill.frame = box.bounds
        fill.cornerRadius = 4
        let mark = CGMutablePath()
        mark.move(to: CGPoint(x: 3.5, y: 7.5))
        mark.addLine(to: CGPoint(x: 6, y: 10))
        mark.addLine(to: CGPoint(x: 10.5, y: 4))
        tick.path = mark
        tick.fillColor = nil
        tick.lineWidth = 1.75
        tick.lineCap = .round
        tick.lineJoin = .round
        fill.addSublayer(tick)
        box.addSublayer(fill)
        row.addSublayer(box)
        layer?.addSublayer(row)
        let rowLabel = NSRect(
            x: Self.rowFrame.minX + 30, y: Self.rowFrame.minY + 8, width: Self.rowFrame.width - 38, height: 16
        )
        action.frame = rowLabel
        shortcut.frame = rowLabel
        shortcut.alignment = .right
        title.frame = NSRect(x: 16, y: 60, width: 268, height: 18)
        detail.frame = NSRect(x: 16, y: 80, width: 268, height: 16)
        for label in [action, shortcut, title, detail] {
            label.setAccessibilityElement(false)
            addSubview(label)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        refreshSurface()
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func refreshSurface() {
        super.refreshSurface()
        row.backgroundColor = Theme.cg(Theme.group, in: self)
        box.borderColor = Theme.cg(Theme.border, in: self)
        fill.backgroundColor = Theme.cg(Theme.accent, in: self)
        tick.strokeColor = Theme.cg(Theme.selectedText, in: self)
    }

    /// The press on the checkbox, then the tick fading out, then the tick coming back for the next cycle.
    static func pose(at cycleFraction: Double) -> (scale: CGFloat, ticked: Float) {
        func eased(_ from: Double, _ to: Double) -> Double {
            1 - pow(1 - min(max((cycleFraction - from) / (to - from), 0), 1), 3)
        }
        let press = eased(0.30, 0.38)
        let release = eased(0.38, 0.46)
        let scale = 1 - 0.12 * (press - release)
        let ticked = 1 - release + eased(0.88, 0.96)
        return (CGFloat(scale), Float(ticked))
    }

    func show(at cycleFraction: Double) {
        stop()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let pose = Self.pose(at: cycleFraction)
        box.transform = CATransform3DMakeScale(pose.scale, pose.scale, 1)
        fill.opacity = pose.ticked
        CATransaction.commit()
    }

    private func refresh() {
        switch state {
        case .turnOff(let name, let keys):
            action.stringValue = name
            shortcut.stringValue = keys
            title.stringValue = "Turn off \(name)"
            detail.stringValue = "In Keyboard Shortcuts, under Spotlight"
            show(at: 0)
            start()
        case .freed(let keys):
            shortcut.stringValue = keys
            title.stringValue = "\(keys) now opens Ciel"
            detail.stringValue = "You can close System Settings"
            show(at: 0.5)
        }
        action.frame.size.width = shortcut.frame.width - shortcut.intrinsicContentSize.width - 4
        setAccessibilityLabel(title.stringValue + ". " + detail.stringValue)
    }

    private func start() {
        guard !Theme.reduceMotion else { return }
        let times = (0...48).map { Double($0) / 48 }
        let poses = times.map(Self.pose)
        let scale = CAKeyframeAnimation(keyPath: "transform")
        scale.values = poses.map { NSValue(caTransform3D: CATransform3DMakeScale($0.scale, $0.scale, 1)) }
        let ticked = CAKeyframeAnimation(keyPath: "opacity")
        ticked.values = poses.map(\.ticked)
        for (layer, animation) in [(box, scale), (fill, ticked)] {
            animation.keyTimes = times.map { $0 as NSNumber }
            animation.duration = Self.cycle
            animation.repeatCount = .infinity
            layer.add(animation, forKey: "untick")
        }
    }

    private func stop() {
        box.removeAnimation(forKey: "untick")
        fill.removeAnimation(forKey: "untick")
    }
}
