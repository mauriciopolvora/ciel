import AppKit

@MainActor final class AccessibilityHelper {
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    let card = DragCard(frame: NSRect(origin: .zero, size: DragCard.size))
    let trail = DragTrail(
        frame: NSRect(x: 0, y: 0, width: DragCard.iconFrame.width, height: DragTrail.height))
    private let companion: SettingsCompanion
    private let trailPanel: NSPanel
    var isShown: Bool { companion.isShown }

    init() {
        companion = SettingsCompanion(card: card)
        trailPanel = SettingsCompanion.panel(trail)
        trailPanel.ignoresMouseEvents = true
        companion.onPlace = { [weak self] cardFrame in self?.placeTrail(above: cardFrame) }
    }

    func show() { companion.show() }

    func close() { companion.close() }

    private func placeTrail(above cardFrame: NSRect?) {
        guard let cardFrame else {
            trail.stop()
            trailPanel.orderOut(nil)
            return
        }
        let icon = DragCard.iconFrame
        let trailFrame = NSRect(
            x: cardFrame.minX + icon.minX, y: cardFrame.maxY - icon.maxY, width: icon.width,
            height: DragTrail.height)
        if trailPanel.frame != trailFrame { trailPanel.setFrame(trailFrame, display: true) }
        guard !trailPanel.isVisible else { return }
        trailPanel.orderFrontRegardless()
        trail.start()
    }
}

/// Starts a drag of Ciel's bundle, which System Settings adds to the list it is dropped on.
final class DragCard: SurfaceView, NSDraggingSource {
    static let size = NSSize(width: 300, height: 72)
    static let iconFrame = NSRect(x: 16, y: 16, width: 40, height: 40)
    static let title = "Drag Ciel into the list above"

    override init(frame: NSRect) {
        super.init(frame: frame)
        isFloating = true
        refreshSurface()
        let icon = NSImageView(frame: Self.iconFrame)
        icon.image = NSApplication.shared.applicationIconImage
        addSubview(icon)
        let title = Theme.label(Self.title, size: 13, weight: .medium)
        title.frame = NSRect(x: 68, y: 16, width: 216, height: 18)
        let detail = Theme.label("Then turn it on", size: 12, color: Theme.secondary)
        detail.frame = NSRect(x: 68, y: 36, width: 216, height: 16)
        for label in [title, detail] { addSubview(label) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(Self.title)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        beginDraggingSession(with: [draggingItem()], event: event, source: self)
    }

    func draggingItem() -> NSDraggingItem {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(Self.iconFrame, contents: NSApplication.shared.applicationIconImage)
        return item
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}

final class DragTrail: NSView {
    static let height: CGFloat = 150
    static let cycle: CFTimeInterval = 2.4
    private static let riseShare = 0.6
    private static let fadeInShare = 0.15
    private static let fadeOutShare = 0.3
    private let ghost = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ghost.frame = NSRect(origin: .zero, size: DragCard.iconFrame.size)
        ghost.contents = NSApplication.shared.applicationIconImage.cgImage(
            forProposedRect: nil, context: nil, hints: nil)
        ghost.contentsGravity = .resizeAspect
        ghost.opacity = 0
        layer?.addSublayer(ghost)
    }
    required init?(coder: NSCoder) { fatalError() }

    static func pose(at cycleFraction: Double) -> (transform: CATransform3D, opacity: Float) {
        let p = min(cycleFraction / riseShare, 1)
        let eased = 1 - pow(1 - p, 3)
        let rise = CGFloat(eased) * (height - DragCard.iconFrame.height)
        let scale = 1 - 0.2 * CGFloat(eased)
        let opacity = p < 1 ? min(p / fadeInShare, 1) * min((1 - p) / fadeOutShare, 1) * 0.85 : 0
        let transform = CATransform3DScale(CATransform3DMakeTranslation(0, rise, 0), scale, scale, 1)
        return (transform, Float(opacity))
    }

    func show(at cycleFraction: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let pose = Self.pose(at: cycleFraction)
        ghost.transform = pose.transform
        ghost.opacity = pose.opacity
        CATransaction.commit()
    }

    func start() {
        guard !Theme.reduceMotion, ghost.animation(forKey: "drag") == nil else { return }
        let times = (0...30).map { Double($0) / 30 }
        let poses = times.map(Self.pose)
        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = poses.map { NSValue(caTransform3D: $0.transform) }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = poses.map(\.opacity)
        for animation in [transform, opacity] { animation.keyTimes = times.map { $0 as NSNumber } }
        let group = CAAnimationGroup()
        group.animations = [transform, opacity]
        group.duration = Self.cycle
        group.repeatCount = .infinity
        ghost.add(group, forKey: "drag")
    }

    func stop() { ghost.removeAllAnimations() }
}
