import AppKit
import CielCore
import ColorSync

final class LauncherGuideView: NSView {
    var xGuide: CGFloat?
    var yGuide: CGFloat?
    override func draw(_ dirtyRect: NSRect) {
        for fraction in LauncherPlacement.guideFractions {
            let x = bounds.width * fraction
            let y = bounds.height * fraction
            line(
                from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: bounds.height),
                active: xGuide.map { abs($0 - x) < 1 } ?? false)
            line(
                from: CGPoint(x: 0, y: y), to: CGPoint(x: bounds.width, y: y),
                active: yGuide.map { abs($0 - y) < 1 } ?? false)
        }
    }
    private func line(from start: CGPoint, to end: CGPoint, active: Bool) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        NSColor.white.withAlphaComponent(active ? 0.7 : 0.18).setStroke()
        path.lineWidth = active ? 1.5 : 1
        path.stroke()
    }
}

@MainActor final class LauncherGuides {
    private var panel: NSPanel?
    private var view: LauncherGuideView?

    static func displayID(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        if let number, let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return number?.stringValue ?? "main"
    }

    func update(for launcher: LauncherPanel) {
        guard let screen = launcher.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        if panel?.frame != area {
            hide()
            let panel = NSPanel(
                contentRect: area, styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let view = LauncherGuideView(frame: NSRect(origin: .zero, size: area.size))
            panel.contentView = view
            self.panel = panel
            self.view = view
        }
        let snap = LauncherPlacement.snap(
            launcher.frame, screen: area, headerHeight: LauncherView.initialHeight,
            enabled: !NSEvent.modifierFlags.contains(.option))
        view?.xGuide = snap.xGuide.map { $0 - area.minX }
        view?.yGuide = snap.yGuide.map { $0 - area.minY }
        view?.needsDisplay = true
        panel?.order(.below, relativeTo: launcher.windowNumber)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        view = nil
    }
}
