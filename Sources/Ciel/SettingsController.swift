import AppKit
import CielCore
import ServiceManagement

class PreferencesController: NSWindowController, NSWindowDelegate {
    let hotKeys: HotKeys
    let content: SurfaceView
    let errorLabel = Theme.label("", size: 12, color: Theme.error)
    private var baseSize: NSSize
    private(set) var recorders: [HotKeyCommand: ShortcutRecorder] = [:]

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

    func group(_ frame: NSRect, in parent: NSView? = nil) -> FlippedView {
        let view = SurfaceView(frame: frame)
        view.isGroup = true
        view.refreshSurface()
        (parent ?? content).addSubview(view)
        return view
    }
    static func status() -> NSTextField {
        let label = Theme.label("", size: 12, color: Theme.secondary)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.alignment = .right
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
    func rows(_ rows: [(String, [NSView])], at y: CGFloat, in parent: NSView? = nil) -> NSView {
        let box = group(
            NSRect(x: 20, y: y, width: 440, height: CGFloat(rows.count) * Theme.rowHeight), in: parent)
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
        return box
    }
    @discardableResult
    func footer(_ title: String, _ action: Selector, top: CGFloat, in parent: NSView) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: parent.topAnchor, constant: top),
            button.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -20),
        ])
        return button
    }
    func label(
        _ title: String, x: CGFloat = 16, y: CGFloat, width: CGFloat = 246,
        size: CGFloat = 14, color: NSColor = Theme.text, in parent: NSView
    ) {
        let view = Theme.label(title, size: size, color: color)
        view.frame = NSRect(x: x, y: y, width: width, height: 21)
        parent.addSubview(view)
    }
    func recorder(
        _ command: HotKeyCommand, label: String, style: ShortcutRecorder.Type = ShortcutRecorder.self
    ) -> ShortcutRecorder {
        let recorder = style.init(shortcut: hotKeys.shortcut(for: command), onRecord: { _ in })
        wire(recorder, command, label: label)
        return recorder
    }
    func wire(_ recorder: ShortcutRecorder, _ command: HotKeyCommand, label: String) {
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
    func resize(toHeight height: CGFloat) {
        baseSize.height = height
        errorLabel.frame.origin.y = height - 6
        showMessage(errorLabel.stringValue)
    }
    func refresh() {
        for (command, recorder) in recorders where !recorder.recording {
            recorder.shortcut = hotKeys.shortcut(for: command)
        }
    }
    /// Centers the window on `screen`, unless it is already showing there, then presents it.
    func present(on screen: NSScreen) {
        if let window, !(window.isVisible && window.screen?.frame == screen.frame) {
            window.setFrame(Self.centered(window.frame.size, in: screen.visibleFrame), display: false)
        }
        present()
    }
    static func centered(_ size: NSSize, in area: NSRect) -> NSRect {
        NSRect(
            x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded(),
            width: size.width, height: size.height)
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
    static let controlWidth: CGFloat = 120
    let permissionLabel = SettingsController.status()
    let permissionButton = NSButton(title: "Allow Access…", target: nil, action: nil)
    let login = MonochromeSwitch(frame: .zero)
    let animations = MonochromeSwitch(frame: .zero)
    let menuBarIcon = MonochromeSwitch(frame: .zero)
    let updateChecks = MonochromeSwitch(frame: .zero)
    let speechSwitch = MonochromeSwitch(frame: .zero)
    let modelStatus = SettingsController.status()
    let modelButton = NSButton(title: "", target: nil, action: nil)
    let guideButton = NSButton(title: "Keyboard Guide…", target: nil, action: nil)
    let aboutButton = NSButton(title: "About Ciel…", target: nil, action: nil)
    let updateButton: NSButton
    let dictationRecorder: ShortcutRecorder
    private var canCheckObservation: NSKeyValueObservation?
    private let speech: SpeechModelStore
    private let updater: Updater
    let spotlightGuide: SpotlightGuide
    private let spotlightSheet = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 222), styleMask: [.titled], backing: .buffered,
        defer: true)
    private var poll: Task<Void, Never>?
    private var showsAccessMessage = false
    var onGuide: (() -> Void)?
    var onAbout: (() -> Void)?
    var onMenuBarIconChange: (() -> Void)?
    var onSpeechChange: (() -> Void)?

    init(
        hotKeys: HotKeys, speech: SpeechModelStore, updater: Updater, spotlight: SpotlightShortcuts = .system,
        open: @escaping @MainActor (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
    ) {
        self.speech = speech
        self.updater = updater
        spotlightGuide = SpotlightGuide(hotKeys: hotKeys, spotlight: spotlight, open: open)
        dictationRecorder = ShortcutRecorder(shortcut: hotKeys.shortcut(for: .dictation), onRecord: { _ in })
        updateButton = updater.checkButton()
        super.init(title: "Ciel Settings", size: NSSize(width: 480, height: 696), hotKeys: hotKeys)
        spotlightGuide.owner = self
        for (toggle, name, action) in [
            (login, "Launch at login", #selector(toggleLogin)),
            (animations, "Animations", #selector(toggleAnimations)),
            (menuBarIcon, "Show menu bar icon", #selector(toggleMenuBarIcon)),
            (updateChecks, "Automatically check for updates", #selector(toggleUpdateChecks)),
            (speechSwitch, "Speech to text", #selector(toggleSpeech)),
        ] {
            toggle.target = self
            toggle.action = action
            toggle.setAccessibilityLabel(name)
        }
        menuBarIcon.toolTip = "You can still open Settings from the launcher with Command–Comma."
        for (button, action) in [
            (permissionButton, #selector(requestPermission)), (modelButton, #selector(modelAction)),
            (guideButton, #selector(openGuide)), (aboutButton, #selector(openAbout)),
        ] {
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 12)
            button.target = self
            button.action = action
        }
        wire(dictationRecorder, .dictation, label: "Dictation shortcut")
        dictationRecorder.acceptsModifierKey = true
        let launcher = recorder(.launcher, label: "Launcher shortcut", style: MenuRecorder.self)
        launcher.onRecord = { [weak self] shortcut in self?.spotlightGuide.choose(shortcut) }
        for control in [launcher, dictationRecorder, permissionButton, modelButton] {
            control.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        }
        canCheckObservation = updater.observeCanCheck { [weak self] can in
            self?.updateButton.isEnabled = can
        }
        buildSpotlightSheet()
        resize(toHeight: layout(launcher))
        refresh()
        window?.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func openGuide() { onGuide?() }
    @objc private func openAbout() { onAbout?() }

    private func layout(_ launcher: ShortcutRecorder) -> CGFloat {
        var y: CGFloat = 20
        column("Launcher shortcut", [launcher, spotlightGuide.caption], at: &y)
        rule(at: &y)
        column("General", [switchLine(login, "Launch at login")], at: &y)
        column("", [switchLine(animations, "Animations")], at: &y)
        column("", [switchLine(menuBarIcon, "Show menu bar icon")], at: &y)
        column("", [switchLine(updateChecks, "Automatically check for updates")], at: &y)
        column("", [updateButton], at: &y)
        rule(at: &y)
        column("Accessibility", [permissionLabel, permissionButton], at: &y)
        rule(at: &y)
        column("Dictation", [switchLine(speechSwitch, "Speech to text")], at: &y)
        column("Shortcut", [dictationRecorder], at: &y)
        column("Speech model", [modelStatus, modelButton], at: &y)
        place(guideButton, x: 20, top: y + 20)
        place(aboutButton, right: 460, top: y + 20)
        return y + 61
    }

    private func buildSpotlightSheet() {
        let sheet = SurfaceView(frame: .zero)
        spotlightSheet.appearance = NSAppearance(named: .darkAqua)
        spotlightSheet.contentView = sheet
        spotlightGuide.heading.frame = NSRect(x: 36, y: 24, width: 408, height: 26)
        sheet.addSubview(spotlightGuide.heading)
        let guideRows = rows([("Replace Spotlight", spotlightGuide.row())], at: 66, in: sheet)
        spotlightGuide.note.frame = NSRect(x: 36, y: guideRows.frame.maxY + 12, width: 408, height: 32)
        sheet.addSubview(spotlightGuide.note)
        footer("Cancel", #selector(cancelSpotlight), top: 170, in: sheet).keyEquivalent = "\u{1b}"
    }

    private func showSpotlightSheet() {
        if spotlightGuide.held != nil, poll == nil, let window, window.isVisible {
            window.beginSheet(spotlightSheet)
            poll = Task { [weak self] in
                while true {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, !Task.isCancelled else { return }
                    spotlightGuide.tick()
                }
            }
        } else if spotlightGuide.held == nil, let poll {
            poll.cancel()
            self.poll = nil
            window?.endSheet(spotlightSheet)
        }
    }

    @objc func cancelSpotlight() {
        guard let held = spotlightGuide.held, let kept = hotKeys.shortcut(for: .launcher) else { return }
        spotlightGuide.held = nil
        showMessage("Kept \(kept.display). \(held.display) is still used by Spotlight.")
        refresh()
    }

    override func windowWillClose(_ notification: Notification) {
        super.windowWillClose(notification)
        spotlightGuide.held = nil
        refresh()
    }

    override func refresh() {
        hotKeys.retryUnregistered()
        super.refresh()
        spotlightGuide.refresh()
        showSpotlightSheet()
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
        updateChecks.state = updater.automaticallyChecks ? .on : .off
        let speechEnabled = Preferences().speechEnabled
        speechSwitch.state = speechEnabled ? .on : .off
        dictationRecorder.isEnabled = speechEnabled
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
        if speechSwitch.state == .on {
            do {
                try hotKeys.assignIfUnset(.dictation, to: .modifier(.rightCommand))
            } catch { showMessage(error.localizedDescription) }
        }
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
    @objc private func toggleUpdateChecks() { updater.automaticallyChecks = updateChecks.state == .on }
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
