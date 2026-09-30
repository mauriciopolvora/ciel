import AppKit

/// Use the app's explicit surface and text colors for readable credits.
final class AboutController: NSWindowController {
    init() {
        let content = SurfaceView(frame: NSRect(x: 0, y: 0, width: 420, height: 388))
        let window = NSWindow(
            contentRect: content.frame, styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "About Ciel"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = content
        super.init(window: window)
        content.refreshSurface()

        let icon = NSImageView(frame: NSRect(x: 178, y: 24, width: 64, height: 64))
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Ciel app icon")
        content.addSubview(icon)

        func label(
            _ text: String, y: CGFloat, height: CGFloat, size: CGFloat = 13,
            color: NSColor = Theme.text, centered: Bool = false,
            weight: NSFont.Weight = .regular
        ) {
            let view = Theme.label(text, size: size, weight: weight, color: color)
            view.frame = NSRect(x: 30, y: y, width: 360, height: height)
            view.maximumNumberOfLines = 0
            view.lineBreakMode = .byWordWrapping
            view.cell?.wraps = true
            view.alignment = centered ? .center : .left
            content.addSubview(view)
        }

        label("Ciel", y: 104, height: 30, size: 23, centered: true, weight: .semibold)
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        label(
            "Version \(version) (\(build))", y: 140, height: 20,
            color: Theme.secondary, centered: true)
        label("App launcher and window controls for macOS.", y: 188, height: 38)
        label(
            "Made by Mauricio Polvora.\nOriginal generated cloud artwork, inspired by Monet.\nSearch uses FuzzyMatch 1.4.0 (Apache 2.0).",
            y: 244, height: 76, color: Theme.secondary)
        let copyright = info["NSHumanReadableCopyright"] as? String ?? ""
        label(copyright, y: 340, height: 20, size: 11, centered: true)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
