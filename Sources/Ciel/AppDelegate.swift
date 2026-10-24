import AppKit
import CielCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let catalog = AppCatalog()
    private let windows = WindowController()
    private lazy var hotKeys = HotKeys(
        registrar: CarbonHotKeyRegistrar(),
        onPress: { [weak self] command in self?.hotKeyPressed(command) },
        onChange: { [weak self] in self?.updateToolTip() })
    private let hud = StatusHUD()
    private var panel: LauncherPanel!
    private var launcher: LauncherView!
    private let fieldEditor = MonochromeFieldEditor()
    private let placements = LauncherPlacementStore()
    private let guides = LauncherGuides()
    private var launcherAnchor: CGPoint?
    private var statusItem: NSStatusItem!
    private var settings: SettingsController?
    private var windowShortcuts: WindowShortcutsController?
    private var keyboardGuide: KeyboardGuideController?
    private var about: AboutController?
    private let history = UsageHistory()
    private var observers: [Cleanup] = []
    private var opening = false
    private var session: WindowTarget?
    private var pendingCheck: (@MainActor (CheckHandles) -> Void)?

    init(check: (@MainActor (CheckHandles) -> Void)?) {
        pendingCheck = check
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.accessory)
        setupMenu()
        setupPanel()
        catalog.onUpdate = { [weak self] update in self?.catalogUpdated(update) }
        reloadEntries()
        catalog.refresh()
        observers = [
            NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
            NSWorkspace.didWakeNotification,
        ].map { name in
            NSWorkspace.shared.notificationCenter.observe(name) { [weak self] in self?.catalog.refresh() }
        }
        guard pendingCheck == nil else { return }
        if !hotKeys.registrationErrors.isEmpty {
            hud.show(
                "Launcher shortcut unavailable. Open Ciel from Applications, then press Command–Comma to change it.",
                error: true)
        }
        if !NSAppleEventManager.shared().launchedAsLoginItem { present() }
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
        case .launcher: toggle()
        case .window(let action): run(action, on: panel.isVisible ? session : nil)
        }
    }

    private func setupPanel() {
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: LauncherView.width, height: LauncherView.initialHeight),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Ciel"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.delegate = self
        fieldEditor.isFieldEditor = true
        fieldEditor.insertionPointColor = Theme.text
        fieldEditor.selectedTextAttributes = [
            .backgroundColor: Theme.selection, .foregroundColor: Theme.text,
        ]
        launcher = LauncherView(
            frame: NSRect(x: 0, y: 0, width: LauncherView.width, height: LauncherView.initialHeight))
        panel.contentView = launcher
        launcher.onExecute = { [weak self] entry in self?.execute(entry) }
        launcher.onDismiss = { [weak self] in self?.dismiss() }
        launcher.onHeightChange = { [weak self] height in
            guard let self, let panel = self.panel, panel.frame.height != height else { return }
            var frame = panel.frame
            frame.origin.y += frame.height - height
            frame.size.height = height
            if let anchor = self.launcherAnchor, let screen = panel.screen ?? NSScreen.main {
                frame = LauncherPlacement.frame(anchor: anchor, size: frame.size, screen: screen.visibleFrame)
            }
            panel.setFrame(frame, display: true)
        }
        panel.onDragEnd = { [weak self] moved in
            guard let self else { return }
            self.guides.hide()
            if moved, let screen = self.panel.screen ?? NSScreen.main {
                let snap = LauncherPlacement.snap(
                    self.panel.frame, screen: screen.visibleFrame,
                    headerHeight: LauncherView.initialHeight,
                    enabled: !NSEvent.modifierFlags.contains(.option))
                self.panel.setFrame(snap.frame, display: true)
                self.launcherAnchor = CGPoint(x: snap.frame.minX, y: snap.frame.maxY)
                self.placements.save(
                    LauncherPlacement(
                        frame: snap.frame, screen: screen.visibleFrame,
                        headerHeight: LauncherView.initialHeight), for: LauncherGuides.displayID(screen))
            }
            self.panel.makeFirstResponder(self.launcher.searchField)
        }
        panel.onDragModifiersChange = { [weak self] in
            guard let self else { return }
            self.guides.update(for: self.panel)
        }
        panel.onModifiers = { [weak self] command in self?.launcher.setQuickKeys(command) }
        panel.onEscape = { [weak self] in self?.dismiss() }
        panel.onSettings = { [weak self] in self?.showSettings() }
        panel.onQuickOpen = { [weak self] index in self?.launcher.execute(at: index) }
    }

    private func catalogUpdated(_ update: CatalogUpdate) {
        // Invalidate first, so the cells a reload configures miss the stale icons.
        launcher.invalidateIcons(paths: update.invalidatedIconPaths)
        if update.entriesChanged { reloadEntries() }
        if let check = pendingCheck {
            pendingCheck = nil
            start(check)
        }
    }

    private func reloadEntries() {
        let entries = catalog.entries + SearchEntry.commands + SearchEntry.utilities
        launcher.update(entries: entries, usage: history.counts, lastUsed: history.lastUsed)
    }
    @objc private func menuOpen() { present() }
    private func toggle() { if panel.isVisible { dismiss() } else { present() } }
    private func present() {
        guard !panel.isDragging else { return }
        session = windows.capture(.frontmost)
        launcher.reset()
        let screen =
            NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        if let area = screen?.visibleFrame {
            let frame: CGRect
            if let screen, let saved = placements.placement(for: LauncherGuides.displayID(screen)) {
                frame = saved.frame(
                    size: panel.frame.size, screen: area, headerHeight: LauncherView.initialHeight)
            } else {
                frame = CGRect(
                    x: area.midX - panel.frame.width / 2,
                    y: area.minY + (area.height - panel.frame.height) * 0.62,
                    width: panel.frame.width, height: panel.frame.height)
            }
            panel.setFrame(frame, display: true)
            launcherAnchor = CGPoint(x: frame.minX, y: frame.maxY)
        }
        opening = true
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(launcher.searchField)
        opening = false
    }
    private func dismiss() {
        guides.hide()
        panel.orderOut(nil)
    }
    func windowDidMove(_ notification: Notification) {
        if panel.isDragging { guides.update(for: panel) }
    }
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        sender === panel && (client as? NSTextField) === launcher.searchField ? fieldEditor : nil
    }
    func windowDidResignKey(_ notification: Notification) { if !opening && !panel.isDragging { dismiss() } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        present()
        return false
    }

    private func recordUsage(_ id: SearchEntry.ID) {
        history.record(id)
        launcher.updateUsage(history.counts, lastUsed: history.lastUsed)
    }
    private func execute(_ entry: SearchEntry) {
        if let action = entry.action {
            run(action, on: session)
            return
        }
        if let path = entry.path {
            dismiss()
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
                dismiss()
                rescan()
            }
        }
    }
    /// A nil target captures the frontmost app, after the checks that can drop the command.
    private func run(_ action: WindowAction, on target: WindowTarget?) {
        guard !windows.isBusy else { return }
        guard WindowController.isTrusted else {
            dismiss()
            showSettings()
            WindowController.requestPermission()
            return
        }
        let target = target ?? windows.capture(.frontmost)
        dismiss()
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
        dismiss()
        if settings == nil {
            settings = SettingsController(hotKeys: hotKeys)
            settings?.onMenuBarIconChange = { [weak self] in self?.updateMenuBarIcon() }
            settings?.onGuide = { [weak self] in self?.showGuide() }
            settings?.onAbout = { [weak self] in self?.showAbout() }
        }
        settings?.present()
    }
    @objc private func showWindowShortcuts() {
        dismiss()
        if windowShortcuts == nil {
            windowShortcuts = WindowShortcutsController(hotKeys: hotKeys)
        }
        windowShortcuts?.present()
    }
    @objc private func showGuide() {
        dismiss()
        if keyboardGuide == nil { keyboardGuide = KeyboardGuideController(hotKeys: hotKeys) }
        keyboardGuide?.present()
    }
    @objc private func showAbout() {
        dismiss()
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
                launcher: launcher, panel: panel, fieldEditor: fieldEditor, catalog: catalog,
                hotKeys: hotKeys,
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
