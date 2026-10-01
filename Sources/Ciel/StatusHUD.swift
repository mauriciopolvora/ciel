import AppKit

@MainActor final class StatusHUD {
    private var panel: NSPanel?
    private var dismiss: Task<Void, Never>?
    func show(_ message: String, error: Bool = false) {
        dismiss?.cancel()
        panel?.orderOut(nil)
        let width: CGFloat = min(570, max(280, CGFloat(message.count) * 6.5 + 65))
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 54),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.appearance = NSAppearance(named: .darkAqua)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.ignoresMouseEvents = true
        let view = SurfaceView(frame: NSRect(x: 0, y: 0, width: width, height: 54))
        view.isFloating = true
        view.refreshSurface()
        view.layer?.masksToBounds = true
        let icon = NSImageView(frame: NSRect(x: 17, y: 17, width: 20, height: 20))
        icon.image = NSImage(
            systemSymbolName: error ? "exclamationmark.circle.fill" : "checkmark.circle.fill",
            accessibilityDescription: nil)
        icon.contentTintColor = error ? Theme.error : Theme.success
        view.addSubview(icon)
        let label = Theme.label(message, size: 12, weight: .medium)
        label.frame = NSRect(x: 47, y: 18, width: width - 60, height: 18)
        view.addSubview(label)
        p.contentView = view
        let screen =
            NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: frame.midX - width / 2, y: frame.minY + 90))
        }
        panel = p
        p.alphaValue = Theme.reduceMotion ? 1 : 0
        p.orderFrontRegardless()
        if !Theme.reduceMotion {
            NSAnimationContext.runAnimationGroup {
                $0.duration = 0.16
                p.animator().alphaValue = 1
            }
        }
        dismiss = Task { @MainActor [weak self, weak p] in
            do {
                try await Task.sleep(for: .seconds(error ? 4 : 1.6))
            } catch { return }
            guard let p else { return }
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = Theme.reduceMotion ? 0 : Theme.hoverDuration
                    p.animator().alphaValue = 0
                },
                completionHandler: { [weak self, weak p] in
                    Task { @MainActor [weak self, weak p] in
                        guard let p else { return }
                        p.orderOut(nil)
                        if self?.panel === p { self?.panel = nil }
                    }
                })
        }
    }
}
