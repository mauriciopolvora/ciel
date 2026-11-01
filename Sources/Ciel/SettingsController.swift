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
    func recorder(_ command: HotKeyCommand, label: String) -> ShortcutRecorder {
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
        recorder.setAccessibilityLabel(label)
        if command == .launcher {
            recorder.toolTip = "Click to change the launcher shortcut. Press Escape to cancel."
        }
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
    private static let controlWidth: CGFloat = 120
    private let permissionLabel = SettingsController.status()
    private let permissionButton = NSButton(title: "Allow Access…", target: nil, action: nil)
    private let login = MonochromeSwitch(frame: .zero)
    private let animations = MonochromeSwitch(frame: .zero)
    private let menuBarIcon = MonochromeSwitch(frame: .zero)
    private let speechSwitch = MonochromeSwitch(frame: .zero)
    private let modelStatus = SettingsController.status()
    private let modelButton = NSButton(title: "", target: nil, action: nil)
    private let speech: SpeechModelStore
    private var dictationRecorder: ShortcutRecorder?
    private var showsAccessMessage = false
    var onGuide: (() -> Void)?
    var onAbout: (() -> Void)?
    var onMenuBarIconChange: (() -> Void)?
    var onSpeechChange: (() -> Void)?

    init(hotKeys: HotKeys, speech: SpeechModelStore) {
        self.speech = speech
        super.init(title: "Ciel Settings", size: NSSize(width: 480, height: 608), hotKeys: hotKeys)
        let title = Theme.label("Ciel", size: 23)
        title.frame = NSRect(x: 36, y: 20, width: 408, height: 28)
        let subtitle = Theme.label(
            "App launcher, window controls and dictation", size: 12, color: Theme.secondary)
        subtitle.frame = NSRect(x: 36, y: 50, width: 408, height: 16)
        content.addSubview(title)
        content.addSubview(subtitle)
        for (toggle, name, action) in [
            (login, "Launch at login", #selector(toggleLogin)),
            (animations, "Animations", #selector(toggleAnimations)),
            (menuBarIcon, "Show menu bar icon", #selector(toggleMenuBarIcon)),
            (speechSwitch, "Speech to text", #selector(toggleSpeech)),
        ] {
            toggle.target = self
            toggle.action = action
            toggle.setAccessibilityLabel(name)
        }
        menuBarIcon.toolTip = "You can still open Settings from the launcher with Command–Comma."
        for (button, action) in [
            (permissionButton, #selector(requestPermission)), (modelButton, #selector(modelAction)),
        ] {
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 12)
            button.target = self
            button.action = action
        }
        let launcher = recorder(.launcher, label: "Launcher shortcut")
        let dictation = recorder(.dictation, label: "Dictation shortcut")
        dictation.acceptsModifierKey = true
        dictationRecorder = dictation
        for control in [launcher, dictation, permissionButton, modelButton] {
            control.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        }
        var y = section(
            "General", at: 86,
            rows: [
                ("Launcher shortcut", [launcher]), ("Launch at login", [login]), ("Animations", [animations]),
                ("Show menu bar icon", [menuBarIcon]),
            ])
        y = section("Permissions", at: y, rows: [("Accessibility", [permissionLabel, permissionButton])])
        y = section(
            "Dictation", at: y,
            rows: [
                ("Speech to text", [speechSwitch]), ("Shortcut", [dictation]),
                ("Speech model", [modelStatus, modelButton]),
            ])
        let guide = NSButton(title: "Keyboard Guide…", target: self, action: #selector(openGuide))
        let about = NSButton(title: "About Ciel…", target: self, action: #selector(openAbout))
        for button in [guide, about] {
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 12)
            button.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(button)
            button.topAnchor.constraint(equalTo: content.topAnchor, constant: y).isActive = true
        }
        NSLayoutConstraint.activate([
            guide.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            about.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func openGuide() { onGuide?() }
    @objc private func openAbout() { onAbout?() }

    private static func status() -> NSTextField {
        let label = Theme.label("", size: 12, color: Theme.secondary)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.alignment = .right
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func section(_ title: String, at y: CGFloat, rows: [(String, [NSView])]) -> CGFloat {
        let header = Theme.label(title, size: 13, weight: .semibold, color: Theme.secondary)
        header.frame = NSRect(x: 36, y: y, width: 408, height: 17)
        content.addSubview(header)
        let box = group(NSRect(x: 20, y: y + 23, width: 440, height: CGFloat(rows.count) * Theme.rowHeight))
        for (index, (name, controls)) in rows.enumerated() {
            let top = CGFloat(index) * Theme.rowHeight
            if index > 0 { box.addSubview(Divider(frame: NSRect(x: 16, y: top, width: 408, height: 1))) }
            let label = Theme.label(name, size: 14)
            let stack = NSStackView(views: controls)
            stack.spacing = 8
            stack.setHuggingPriority(.defaultHigh, for: .horizontal)
            for view in [label, stack] {
                view.translatesAutoresizingMaskIntoConstraints = false
                box.addSubview(view)
                view.centerYAnchor.constraint(equalTo: box.topAnchor, constant: top + Theme.rowHeight / 2)
                    .isActive = true
            }
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
            ])
        }
        return box.frame.maxY + 20
    }

    override func refresh() {
        hotKeys.retryUnregistered()
        super.refresh()
        let waiting = hotKeys.shortcut(for: .dictation) != nil && !hotKeys.isLive(.dictation)
        if waiting != showsAccessMessage {
            showsAccessMessage = waiting
            showMessage(waiting ? HotKeyError.needsAccess.localizedDescription : "")
        }
        let trusted = WindowController.isTrusted
        permissionLabel.stringValue = trusted ? "Allowed" : "Not allowed"
        permissionLabel.textColor = trusted ? Theme.success : Theme.secondary
        permissionButton.isHidden = trusted
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        animations.state = Preferences().animations ? .on : .off
        menuBarIcon.state = Preferences().showMenuBarIcon ? .on : .off
        let speechEnabled = Preferences().speechEnabled
        speechSwitch.state = speechEnabled ? .on : .off
        dictationRecorder?.isEnabled = speechEnabled && speech.state == .ready
        let status = speech.state.status
        modelStatus.stringValue = status.text
        modelStatus.toolTip = status.text
        modelStatus.textColor =
            switch status.tone {
            case .quiet: Theme.secondary
            case .ready: Theme.success
            case .error: Theme.error
            }
        modelButton.title = status.action.rawValue
    }
    @objc private func toggleSpeech() {
        Preferences().speechEnabled = speechSwitch.state == .on
        onSpeechChange?()
        refresh()
    }
    @objc private func modelAction() {
        switch speech.state.status.action {
        case .download: speech.download()
        case .cancel: speech.cancel()
        case .remove: speech.remove()
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
            let recorder = self.recorder(.window(action), label: action.title + " shortcut")
            recorder.frame = NSRect(x: 270, y: y + 6, width: 148, height: 32)
            list.addSubview(recorder)
        }
        scroll.documentView = list
        content.addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }
}
