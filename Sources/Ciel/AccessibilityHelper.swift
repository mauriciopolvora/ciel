import AppKit
import CielCore

@MainActor final class AccessibilityHelper {
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    private static let systemSettings = "com.apple.systempreferences"
    let card = DragCard(frame: NSRect(origin: .zero, size: DragCard.size))
    let trail = DragTrail(
        frame: NSRect(x: 0, y: 0, width: DragCard.iconFrame.width, height: DragTrail.height))
    private let cardPanel: NSPanel
    private let trailPanel: NSPanel
    private var follow: Task<Void, Never>?
    var isShown: Bool { follow != nil }

    init() {
        cardPanel = Self.panel(card)
        trailPanel = Self.panel(trail)
        trailPanel.ignoresMouseEvents = true
    }

    func show() {
        guard follow == nil else { return }
        follow = Task { [weak self] in
            while !Task.isCancelled {
                self?.place()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func close() {
        follow?.cancel()
        follow = nil
        hide()
    }

    private func hide() {
        trail.stop()
        cardPanel.orderOut(nil)
        trailPanel.orderOut(nil)
    }

    private func place() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.systemSettings,
            let window = Self.settingsWindow()
        else { return hide() }
        let screen = NSScreen.screens.first { $0.frame.intersects(window) }?.visibleFrame ?? window
        let size = DragCard.size
        let x = min(
            max(window.minX + window.width * 0.62 - size.width / 2, screen.minX + 8),
            screen.maxX - size.width - 8)
        let below = window.minY - 16 - size.height
        let cardFrame = NSRect(
            origin: NSPoint(x: x, y: below >= screen.minY + 8 ? below : window.minY + 16), size: size)
        let icon = DragCard.iconFrame
        let trailFrame = NSRect(
            x: cardFrame.minX + icon.minX, y: cardFrame.maxY - icon.maxY, width: icon.width,
            height: DragTrail.height)
        if cardPanel.frame != cardFrame { cardPanel.setFrame(cardFrame, display: true) }
        if trailPanel.frame != trailFrame { trailPanel.setFrame(trailFrame, display: true) }
        guard !cardPanel.isVisible else { return }
        cardPanel.orderFrontRegardless()
        trailPanel.orderFrontRegardless()
        trail.start()
    }

    private static func settingsWindow() -> NSRect? {
        guard
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: systemSettings).first?
                .processIdentifier,
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return
            windows
            .filter {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                    && ($0[kCGWindowLayer as String] as? Int) == 0
            }
            .compactMap {
                ($0[kCGWindowBounds as String] as? NSDictionary).flatMap {
                    CGRect(dictionaryRepresentation: $0)
                }
            }
            .max { $0.width * $0.height < $1.width * $1.height }
            .map { WindowGeometry.accessibilityRect($0, primaryHeight: primaryHeight) }
    }

    private static func panel(_ view: NSView) -> NSPanel {
        let panel = NSPanel(
            contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: true)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = view is DragCard
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = view
        return panel
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
