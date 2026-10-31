import AppKit
import CielCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let catalog = AppCatalog()
    private let windows = WindowController()
    private let hud = StatusHUD()
    private let pill = DictationPill()
    private let history = UsageHistory()
    private let speech = SpeechModelStore()
    private var transcriber: TranscribeCppTranscriber?
    private lazy var hotKeys = HotKeys(
        registrar: SystemHotKeyRegistrar(),
        onPress: { [weak self] command in self?.hotKeyPressed(command) },
        onRelease: { [weak self] command in if command == .dictation { self?.dictation.release() } },
        onCancel: { [weak self] command in if command == .dictation { self?.dictation.cancel() } },
        onChange: { [weak self] in self?.updateToolTip() })
    private lazy var dictation = Dictation(
        recorder: Microphone(onLevel: { [weak self] level in self?.pill.level(level) }),
        transcriber: { [weak self] in
            guard let self else { throw DictationError.off }
            return try self.speechTranscriber()
        },
        deliver: { [weak self] text in
            if !TextPaster.paste(text) { self?.hud.show("Copied. Allow window access in Settings to paste.") }
        },
        fail: { [weak self] message in self?.hud.show(message, error: true) },
        onActivity: { [weak self] activity in self?.pill.show(activity) })
    private lazy var panel = LauncherPanel()
    private var statusItem: NSStatusItem!
    private var settings: SettingsController?
    private var windowShortcuts: WindowShortcutsController?
    private var keyboardGuide: KeyboardGuideController?
    private var about: AboutController?
    private var observers: [Cleanup] = []
    private var session: WindowTarget?
    private var pendingCheck: (@MainActor (CheckHandles) -> Void)?

    init(check: (@MainActor (CheckHandles) -> Void)?) {
        pendingCheck = check
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.accessory)
        setupMenu()
        panel.launcher.onExecute = { [weak self] entry in self?.execute(entry) }
        panel.onSettings = { [weak self] in self?.showSettings() }
        catalog.onUpdate = { [weak self] update in self?.catalogUpdated(update) }
        speech.onChange = { [weak self] in self?.speechChanged() }
        reloadEntries()
        catalog.refresh()
        observers = [
            NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
            NSWorkspace.didWakeNotification,
        ].map { name in
            NSWorkspace.shared.notificationCenter.observe(name) { [weak self] in self?.catalog.refresh() }
        }
        guard pendingCheck == nil else { return }
        let accessLost = Preferences().windowAccessLost(trusted: WindowController.isTrusted)
        if !hotKeys.isLive(.launcher) {
            hud.show(
                "Launcher shortcut unavailable. Open Ciel from Applications, then press Command–Comma to change it.",
                error: true)
        } else if accessLost {
            hud.show(
                "An update reset window access. Remove Ciel in Accessibility settings, then add it again.",
                error: true)
        } else if hotKeys.shortcut(for: .dictation) != nil, !hotKeys.isLive(.dictation) {
            hud.show(HotKeyError.needsAccess.localizedDescription, error: true)
        }
        if !NSAppleEventManager.shared().launchedAsLoginItem { present() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        present()
        return false
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cloud", accessibilityDescription: "Ciel")
        updateToolTip()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Ciel", action: #selector(menuOpen), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "About Ciel…", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Keyboard Guide…", action: #selector(showGuide), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "License Notices…", action: #selector(showNotices), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(
            NSMenuItem(title: "Window Shortcuts…", action: #selector(showWindowShortcuts), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Rescan Applications", action: #selector(rescan), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Ciel", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        updateMenuBarIcon()
    }

    private func updateMenuBarIcon() {
        statusItem.isVisible = Preferences().showMenuBarIcon
    }

    private func updateToolTip() {
        statusItem.button?.toolTip = "Ciel · \(hotKeys.shortcut(for: .launcher)?.display ?? "")"
    }

    private func hotKeyPressed(_ command: HotKeyCommand) {
        switch command {
        case .launcher: if panel.isVisible { panel.dismiss() } else { present() }
        case .window(let action): run(action)
        case .dictation: dictation.press()
        }
    }

    private func speechTranscriber() throws -> TranscribeCppTranscriber {
        guard Preferences().speechEnabled else { throw DictationError.off }
        guard speech.state == .ready else { throw DictationError.notReady }
        if let transcriber { return transcriber }
        let loaded = TranscribeCppTranscriber(modelURL: speech.fileURL)
        transcriber = loaded
        return loaded
    }

    /// Dropping the transcriber frees the loaded model.
    private func speechChanged() {
        if !Preferences().speechEnabled || speech.state != .ready { transcriber = nil }
        settings?.refresh()
    }

    private func catalogUpdated(_ update: CatalogUpdate) {
        panel.launcher.invalidateIcons(paths: update.invalidatedIconPaths)
        if update.entriesChanged { reloadEntries() }
        if let check = pendingCheck {
            pendingCheck = nil
            start(check)
        }
    }

    private func reloadEntries() {
        let entries = catalog.entries + SearchEntry.commands + SearchEntry.utilities
        panel.launcher.update(entries: entries, usage: history.counts, lastUsed: history.lastUsed)
    }

    private func recordUsage(_ id: SearchEntry.ID) {
        history.record(id)
        panel.launcher.updateUsage(history.counts, lastUsed: history.lastUsed)
    }

    @objc private func menuOpen() { present() }

    private func present() {
        guard !panel.isDragging else { return }
        session = windows.capture(.frontmost)
        panel.present()
    }

    private func execute(_ entry: SearchEntry) {
        if let action = entry.action {
            run(action)
            return
        }
        if let path = entry.path {
            panel.dismiss()
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config) {
                [weak self] app, error in
                DispatchQueue.main.async {
                    if let error {
                        self?.hud.show(error.localizedDescription, error: true)
                        self?.catalog.refresh()
                    } else {
                        self?.recordUsage(entry.id)
                    }
                }
            }
        } else if let utility = entry.utility {
            switch utility {
            case .settings: showSettings()
            case .rescan:
                panel.dismiss()
                rescan()
            }
        }
    }

    private func run(_ action: WindowAction) {
        guard !windows.isBusy else { return }
        guard WindowController.isTrusted else {
            panel.dismiss()
            showSettings()
            WindowController.requestPermission()
            return
        }
        Preferences().hadWindowAccess = true
        let target = (panel.isVisible ? session : nil) ?? windows.capture(.frontmost)
        panel.dismiss()
        windows.perform(action, on: target) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let outcome):
                self.recordUsage(action.id)
                if let notice = outcome.notice { self.hud.show(notice) }
            case .failure(let error): self.hud.show(error.localizedDescription, error: true)
            }
        }
    }

    @objc private func showSettings() {
        panel.dismiss()
        if settings == nil {
            settings = SettingsController(hotKeys: hotKeys, speech: speech)
            settings?.onMenuBarIconChange = { [weak self] in self?.updateMenuBarIcon() }
            settings?.onSpeechChange = { [weak self] in self?.speechChanged() }
            settings?.onGuide = { [weak self] in self?.showGuide() }
            settings?.onAbout = { [weak self] in self?.showAbout() }
        }
        settings?.present()
    }

    @objc private func showWindowShortcuts() {
        panel.dismiss()
        if windowShortcuts == nil {
            windowShortcuts = WindowShortcutsController(hotKeys: hotKeys)
        }
        windowShortcuts?.present()
    }

    @objc private func showGuide() {
        panel.dismiss()
        if keyboardGuide == nil { keyboardGuide = KeyboardGuideController(hotKeys: hotKeys) }
        keyboardGuide?.present()
    }

    @objc private func showAbout() {
        panel.dismiss()
        if about == nil { about = AboutController() }
        about?.present()
    }

    @objc private func showNotices() {
        if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func rescan() {
        catalog.refresh()
        hud.show("Refreshing applications")
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func start(_ check: @MainActor (CheckHandles) -> Void) {
        present()
        check(
            CheckHandles(
                launcher: panel.launcher, panel: panel, fieldEditor: panel.fieldEditor, catalog: catalog,
                hotKeys: hotKeys, speech: speech,
                menu: statusItem.menu,
                showSettings: { [self] in
                    showSettings()
                    return settings
                },
                windowShortcuts: { [self] in windowShortcuts },
                showGuide: { [self] in
                    showGuide()
                    return keyboardGuide
                }))
    }
}

extension NSAppleEventManager {
    fileprivate var launchedAsLoginItem: Bool {
        currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == keyAELaunchedAsLogInItem
    }
}
