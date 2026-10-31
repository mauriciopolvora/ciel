import AppKit
import CielCore
import ServiceManagement

class PreferencesController: NSWindowController, NSWindowDelegate {
    let hotKeys: HotKeys
    let content: SurfaceView
    private let errorLabel = Theme.label("", size: 12, color: Theme.error)
    private let baseSize: NSSize
    private var recorders: [HotKeyCommand: ShortcutRecorder] = [:]

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
    @discardableResult
    func addRecorder(_ command: HotKeyCommand, label: String, in parent: NSView, frame: NSRect)
        -> ShortcutRecorder
    {
        let recorder = ShortcutRecorder(shortcut: hotKeys.shortcut(for: command), onRecord: { _ in })
        recorder.onBegin = { [weak self, weak recorder] in
            self?.hotKeys.recordingHandler = { [weak recorder] shortcut in recorder?.accept(shortcut) }
        }
        recorder.onEnd = { [weak self] in self?.hotKeys.recordingHandler = nil }
        recorder.onRecord = { [weak self, weak recorder] shortcut in
            guard let self else { return }
            do {
                try self.hotKeys.update(command, to: shortcut)
                recorder?.shortcut = shortcut
                self.showMessage("")
            } catch { self.showMessage(error.localizedDescription) }
        }
        recorder.frame = frame
        recorder.setAccessibilityLabel(label)
        if command == .launcher {
            recorder.toolTip = "Click to change the launcher shortcut. Press Escape to cancel."
        }
        parent.addSubview(recorder)
        recorders[command] = recorder
        return recorder
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
        for (command, recorder) in recorders where !recorder.recording {
            recorder.shortcut = hotKeys.shortcut(for: command)
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
    private let speechSwitch = MonochromeSwitch(frame: .zero)
    private let modelStatus = Theme.label("", size: 12, color: Theme.secondary)
    private let modelButton = NSButton()
    private let speech: SpeechModelStore
    private var dictationRecorder: ShortcutRecorder?
    private var showsAccessMessage = false
    var onGuide: (() -> Void)?
    var onAbout: (() -> Void)?
    var onMenuBarIconChange: (() -> Void)?
    var onSpeechChange: (() -> Void)?

    init(hotKeys: HotKeys, speech: SpeechModelStore) {
        self.speech = speech
        super.init(title: "Ciel Settings", size: NSSize(width: 480, height: 602), hotKeys: hotKeys)
        label("Ciel", x: 28, y: 17, width: 260, size: 23, in: content)
        label(
            "App launcher and window controls", x: 28, y: 48, width: 400, size: 12, color: Theme.secondary,
            in: content)
        let general = group(NSRect(x: 20, y: 88, width: 440, height: 192))
        label("Launcher shortcut", y: 14, in: general)
        addRecorder(
            .launcher, label: "Launcher shortcut", in: general,
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

        let speechGroup = group(NSRect(x: 20, y: 384, width: 440, height: 168))
        label("Speech to text", y: 14, in: speechGroup)
        speechSwitch.frame = NSRect(x: 386, y: 11, width: 38, height: 28)
        speechSwitch.target = self
        speechSwitch.action = #selector(toggleSpeech)
        speechSwitch.setAccessibilityLabel("Speech to text")
        speechGroup.addSubview(speechSwitch)
        label("Dictation shortcut", y: 62, in: speechGroup)
        dictationRecorder = addRecorder(
            .dictation, label: "Dictation shortcut", in: speechGroup,
            frame: NSRect(x: 280, y: 56, width: 144, height: 32))
        dictationRecorder?.acceptsModifierKey = true
        label("Speech model", y: 109, in: speechGroup)
        modelStatus.frame = NSRect(x: 16, y: 132, width: 260, height: 20)
        speechGroup.addSubview(modelStatus)
        modelButton.bezelStyle = .rounded
        modelButton.font = .systemFont(ofSize: 12)
        modelButton.frame = NSRect(x: 288, y: 117, width: 136, height: 30)
        modelButton.target = self
        modelButton.action = #selector(modelAction)
        speechGroup.addSubview(modelButton)
        let guide = NSButton(title: "Keyboard Guide…", target: self, action: #selector(openGuide))
        guide.bezelStyle = .inline
        guide.font = .systemFont(ofSize: 12)
        guide.frame = NSRect(x: 24, y: 566, width: 140, height: 24)
        content.addSubview(guide)
        let about = NSButton(title: "About Ciel…", target: self, action: #selector(openAbout))
        about.bezelStyle = .inline
        about.font = .systemFont(ofSize: 12)
        about.frame = NSRect(x: 352, y: 566, width: 104, height: 24)
        content.addSubview(about)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func openGuide() { onGuide?() }
    @objc private func openAbout() { onAbout?() }

    override func refresh() {
        hotKeys.retryUnregistered()
        super.refresh()
        let waiting = hotKeys.shortcut(for: .dictation) != nil && !hotKeys.isLive(.dictation)
        if waiting != showsAccessMessage {
            showsAccessMessage = waiting
            showMessage(waiting ? HotKeyError.needsAccess.localizedDescription : "")
        }
        let trusted = WindowController.isTrusted
        permissionLabel.stringValue = trusted ? "Access enabled" : "Access required to move windows"
        permissionLabel.textColor = trusted ? Theme.success : Theme.secondary
        permissionButton.isHidden = trusted
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        animations.state = Preferences().animations ? .on : .off
        menuBarIcon.state = Preferences().showMenuBarIcon ? .on : .off
        let speechEnabled = Preferences().speechEnabled
        speechSwitch.state = speechEnabled ? .on : .off
        dictationRecorder?.isEnabled = speechEnabled && speech.state == .ready
        switch speech.state {
        case .notDownloaded:
            showModel("Not downloaded", color: Theme.secondary, action: "Download")
        case .downloading(let fraction):
            showModel("Downloading \(Int(fraction * 100))%", color: Theme.secondary, action: "Cancel")
        case .ready:
            showModel("Ready", color: Theme.success, action: "Remove")
        case .failed(let message):
            showModel(message, color: Theme.error, action: "Download")
        }
    }
    private func showModel(_ status: String, color: NSColor, action: String) {
        modelStatus.stringValue = status
        modelStatus.textColor = color
        modelButton.title = action
    }
    @objc private func toggleSpeech() {
        Preferences().speechEnabled = speechSwitch.state == .on
        onSpeechChange?()
        refresh()
    }
    @objc private func modelAction() {
        switch speech.state {
        case .notDownloaded, .failed: speech.download()
        case .downloading: speech.cancel()
        case .ready: speech.remove()
        }
    }
    @objc private func requestPermission() { WindowController.requestPermission() }
    @objc private func toggleAnimations() { Preferences().animations = animations.state == .on }
    @objc private func toggleMenuBarIcon() {
        Preferences().showMenuBarIcon = menuBarIcon.state == .on
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
                .window(action), label: action.title + " shortcut", in: list,
                frame: NSRect(x: 270, y: y + 6, width: 148, height: 32))
        }
        scroll.documentView = list
        content.addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }
}
