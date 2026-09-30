import AppKit
import CielCore
import ServiceManagement

// Shared native window and shortcut handling for the two preferences screens.
class PreferencesController: NSWindowController, NSWindowDelegate {
    let hotKeys: HotKeys
    let content: SurfaceView
    private let errorLabel = Theme.label("", size: 12, color: Theme.error)
    private let baseSize: NSSize
    private var recorders: [String: ShortcutRecorder] = [:]
    var onShortcutChange: (() -> Void)?

    init(title: String, size: NSSize, hotKeys: HotKeys) {
        self.hotKeys = hotKeys
        baseSize = size
        content = SurfaceView(frame: NSRect(origin: .zero, size: size))
        let window = NSWindow(
            contentRect: content.frame, styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        content.wantsLayer = true
        content.refreshSurface()
        window.contentView = content
        errorLabel.frame = NSRect(x: 24, y: size.height - 6, width: size.width - 48, height: 40)
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true
        content.addSubview(errorLabel)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    func group(_ frame: NSRect) -> FlippedView {
        let view = SurfaceView(frame: frame)
        view.isGroup = true
        view.refreshSurface()
        content.addSubview(view)
        return view
    }
    func label(
        _ title: String, x: CGFloat = 16, y: CGFloat, width: CGFloat = 246,
        size: CGFloat = 14, color: NSColor = Theme.text, in parent: NSView
    ) {
        let view = Theme.label(title, size: size, color: color)
        view.frame = NSRect(x: x, y: y, width: width, height: 21)
        parent.addSubview(view)
    }
    func addRecorder(_ id: String, label: String, in parent: NSView, frame: NSRect) {
        let recorder = ShortcutRecorder(shortcut: hotKeys.shortcuts[id], onRecord: { _ in })
        recorder.onBegin = { [weak self, weak recorder] in
            self?.hotKeys.recordingHandler = { [weak recorder] shortcut in recorder?.accept(shortcut) }
        }
        recorder.onEnd = { [weak self] in self?.hotKeys.recordingHandler = nil }
        recorder.onRecord = { [weak self, weak recorder] shortcut in
            guard let self else { return }
            guard id != "launcher" || shortcut != nil else {
                self.showMessage("Choose a launcher shortcut.")
                return
            }
            do {
                try self.hotKeys.update(id, shortcut: shortcut)
                recorder?.shortcut = shortcut
                self.showMessage("")
                self.onShortcutChange?()
            } catch { self.showMessage(error.localizedDescription) }
        }
        recorder.frame = frame
        recorder.setAccessibilityLabel(label)
        if id == "launcher" {
            recorder.toolTip = "Click to change the launcher shortcut. Press Escape to cancel."
        }
        parent.addSubview(recorder)
        recorders[id] = recorder
    }
    func showMessage(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = message.isEmpty
        guard let window else { return }
        let height = baseSize.height + (message.isEmpty ? 0 : 48)
        var frame = window.frame
        let size = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: baseSize.width, height: height))
            .size
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        window.setFrame(frame, display: true)
    }
    func refresh() {
        for (id, recorder) in recorders where !recorder.recording {
            recorder.shortcut = hotKeys.shortcuts[id]
        }
    }
    func present() {
        refresh()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func windowDidBecomeKey(_ notification: Notification) { refresh() }
    func windowDidResignKey(_ notification: Notification) { window?.makeFirstResponder(nil) }
    func windowWillClose(_ notification: Notification) { window?.makeFirstResponder(nil) }
}

final class SettingsController: PreferencesController {
    private let permissionLabel = Theme.label("", size: 12, color: Theme.secondary)
    private let permissionButton = NSButton()
    private let login = MonochromeSwitch(frame: .zero)
    private let animations = MonochromeSwitch(frame: .zero)
    private let menuBarIcon = MonochromeSwitch(frame: .zero)
    var onGuide: (() -> Void)?
    var onAbout: (() -> Void)?
    var onMenuBarIconChange: (() -> Void)?

    init(hotKeys: HotKeys) {
        super.init(title: "Ciel Settings", size: NSSize(width: 480, height: 418), hotKeys: hotKeys)
        label("Ciel", x: 28, y: 17, width: 260, size: 23, in: content)
        label(
            "App launcher and window controls", x: 28, y: 48, width: 400, size: 12, color: Theme.secondary,
            in: content)
        let general = group(NSRect(x: 20, y: 88, width: 440, height: 192))
        label("Launcher shortcut", y: 14, in: general)
        addRecorder(
            "launcher", label: "Launcher shortcut", in: general,
            frame: NSRect(x: 280, y: 8, width: 144, height: 32))
        label("Launch at login", y: 62, in: general)
        login.frame = NSRect(x: 386, y: 59, width: 38, height: 28)
        login.target = self
        login.action = #selector(toggleLogin)
        login.setAccessibilityLabel("Launch at login")
        general.addSubview(login)
        label("Animations", y: 110, in: general)
        animations.frame = NSRect(x: 386, y: 107, width: 38, height: 28)
        animations.target = self
        animations.action = #selector(toggleAnimations)
        animations.setAccessibilityLabel("Animations")
        general.addSubview(animations)

        label("Show menu bar icon", y: 158, in: general)
        menuBarIcon.frame = NSRect(x: 386, y: 155, width: 38, height: 28)
        menuBarIcon.target = self
        menuBarIcon.action = #selector(toggleMenuBarIcon)
        menuBarIcon.setAccessibilityLabel("Show menu bar icon")
        menuBarIcon.toolTip = "You can still open Settings from the launcher with Command–Comma."
        general.addSubview(menuBarIcon)

        let access = group(NSRect(x: 20, y: 296, width: 440, height: 72))
        label("Window management", y: 13, in: access)
        permissionLabel.frame = NSRect(x: 16, y: 36, width: 260, height: 20)
        access.addSubview(permissionLabel)
        permissionButton.title = "Allow Access…"
        permissionButton.bezelStyle = .rounded
        permissionButton.font = .systemFont(ofSize: 12)
        permissionButton.frame = NSRect(x: 288, y: 21, width: 136, height: 30)
        permissionButton.target = self
        permissionButton.action = #selector(requestPermission)
        access.addSubview(permissionButton)
        let guide = NSButton(title: "Keyboard Guide…", target: self, action: #selector(openGuide))
        guide.bezelStyle = .inline
        guide.font = .systemFont(ofSize: 12)
        guide.frame = NSRect(x: 24, y: 382, width: 140, height: 24)
        content.addSubview(guide)
        let about = NSButton(title: "About Ciel…", target: self, action: #selector(openAbout))
        about.bezelStyle = .inline
        about.font = .systemFont(ofSize: 12)
        about.frame = NSRect(x: 352, y: 382, width: 104, height: 24)
        content.addSubview(about)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func openGuide() { onGuide?() }
    @objc private func openAbout() { onAbout?() }

    override func refresh() {
        super.refresh()
        let trusted = WindowController.isTrusted
        permissionLabel.stringValue = trusted ? "Access enabled" : "Access required to move windows"
        permissionLabel.textColor = trusted ? Theme.success : Theme.secondary
        permissionButton.isHidden = trusted
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        animations.state = UserDefaults.standard.bool(forKey: "animations") ? .on : .off
        menuBarIcon.state = UserDefaults.standard.bool(forKey: "showMenuBarIcon") ? .on : .off
    }
    @objc private func requestPermission() { WindowController.requestPermission() }
    @objc private func toggleAnimations() {
        UserDefaults.standard.set(animations.state == .on, forKey: "animations")
    }
    @objc private func toggleMenuBarIcon() {
        UserDefaults.standard.set(menuBarIcon.state == .on, forKey: "showMenuBarIcon")
        onMenuBarIconChange?()
    }
    @objc private func toggleLogin() {
        do {
            if login.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            if SMAppService.mainApp.status == .requiresApproval {
                showMessage("Approve Ciel in System Settings → General → Login Items.")
                SMAppService.openSystemSettingsLoginItems()
            } else {
                showMessage("")
            }
        } catch { showMessage(error.localizedDescription) }
        refresh()
    }
}

final class WindowShortcutsController: PreferencesController {
    init(hotKeys: HotKeys) {
        super.init(title: "Window Shortcuts", size: NSSize(width: 480, height: 452), hotKeys: hotKeys)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 440, height: 412))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        let list = FlippedView(
            frame: NSRect(x: 0, y: 0, width: 426, height: CGFloat(WindowAction.allCases.count) * 44))
        for (index, action) in WindowAction.allCases.enumerated() {
            let y = CGFloat(index) * 44
            label(action.title, x: 8, y: y + 12, width: 250, size: 13, in: list)
            addRecorder(
                "window." + action.rawValue, label: action.title + " shortcut", in: list,
                frame: NSRect(x: 270, y: y + 6, width: 148, height: 32))
        }
        scroll.documentView = list
        content.addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }
}
