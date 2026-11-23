import AppKit
import CielCore

@MainActor final class SettingsCompanion {
    static let systemSettings = "com.apple.systempreferences"
    let panel: NSPanel
    var onPlace: ((NSRect?) -> Void)?
    private var follow: Task<Void, Never>?
    private let followsSheet: Bool
    var isShown: Bool { follow != nil }
    static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == systemSettings
    }

    init(card: NSView, followsSheet: Bool = false) {
        self.followsSheet = followsSheet
        panel = Self.panel(card)
        panel.hasShadow = true
    }

    func show() {
        guard follow == nil else { return }
        follow = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                place()
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
        panel.orderOut(nil)
        onPlace?(nil)
    }

    private func place() {
        guard let frame = placement() else { return hide() }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        onPlace?(frame)
    }

    func placement() -> NSRect? {
        guard Self.isFrontmost, let window = Self.settingsWindow(front: followsSheet)
        else { return nil }
        return Self.frame(of: panel.frame.size, under: window)
    }

    /// Whole points, since a panel rounds its frame.
    static func frame(of size: NSSize, under window: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(window) }?.visibleFrame ?? window
        let x = min(
            max(window.minX + window.width * 0.62 - size.width / 2, screen.minX + 8),
            screen.maxX - size.width - 8)
        let below = window.minY - 16 - size.height
        let y = below >= screen.minY + 8 ? below : window.minY + 16
        return NSRect(origin: NSPoint(x: x.rounded(), y: y.rounded()), size: size)
    }

    static func settingsWindow(front: Bool = false) -> NSRect? {
        guard
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: systemSettings).first?
                .processIdentifier,
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frames =
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
        return (front ? frames.first : frames.max { $0.width * $0.height < $1.width * $1.height })
            .map { WindowGeometry.accessibilityRect($0, primaryHeight: primaryHeight) }
    }

    static func panel(_ view: NSView) -> NSPanel {
        let panel = NSPanel(
            contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: true)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = view
        return panel
    }
}
