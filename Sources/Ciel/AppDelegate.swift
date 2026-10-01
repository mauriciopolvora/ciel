import AppKit
import CielCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let catalog = AppCatalog()
    private let windows = WindowController()
    private let hotKeys = HotKeys()
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
    private var observers: [NotificationObservation] = []
    private var opening = false
    private var executing = false
    private var checkFinished = false
    private let uiCheck = CommandLine.arguments.contains("--ui-test")
    private let smoke = CommandLine.arguments.contains("--smoke-test")
    private let performanceCheck = CommandLine.arguments.contains("--performance-test")
    private var integrationCheck: IntegrationCheck?
    private var catalogCheck: CatalogCheck?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        UserDefaults.standard.register(defaults: ["animations": true, "showMenuBarIcon": true])
        if CommandLine.arguments.contains("--window-test") {
            integrationCheck = IntegrationCheck()
            integrationCheck?.run()
            return
        }
        if CommandLine.arguments.contains("--catalog-test") {
            catalogCheck = CatalogCheck()
            catalogCheck?.run()
            return
        }
        NSApp.setActivationPolicy(.accessory)
        setupMenu()
        setupPanel()
        hotKeys.bind("launcher") { [weak self] in self?.toggle() }
        for action in WindowAction.allCases {
            hotKeys.bind("window." + action.rawValue) { [weak self] in self?.runDirect(action) }
        }
        catalog.onChange = { [weak self] in
            self?.reloadEntries()
        }
        catalog.onIconsInvalidated = { [weak self] paths in self?.launcher.invalidateIcons(paths: paths) }
        catalog.onRefreshFinished = { [weak self] in
            if self?.smoke == true { self?.finishSmokeTest() }
            if self?.uiCheck == true { self?.finishUICheck() }
            if self?.performanceCheck == true { self?.finishPerformanceCheck() }
        }
        reloadEntries()
        catalog.refresh()
        for name in [
            NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
            NSWorkspace.didWakeNotification,
        ] {
            observers.append(
                NotificationObservation(center: NSWorkspace.shared.notificationCenter, name: name) {
                    [weak self] in self?.catalog.refresh()
                })
        }
        if !smoke && !uiCheck && !performanceCheck {
            if !hotKeys.registrationErrors.isEmpty {
                hud.show(
                    "Launcher shortcut unavailable. Open Ciel from Applications, then press Command–Comma to change it.",
                    error: true)
            }
            // Launch-at-login stays quiet; a manual open presents the launcher.
            let event = NSAppleEventManager.shared().currentAppleEvent
            let loginLaunch =
                event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
            if !loginLaunch { present() }
        }
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cloud", accessibilityDescription: "Ciel")
        statusItem.button?.toolTip = "Ciel · \(hotKeys.shortcuts["launcher"]?.display ?? "")"
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
        statusItem.isVisible = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
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

    private func reloadEntries() {
        let entries =
            catalog.entries + SearchEntry.commands + [
                SearchEntry(
                    id: "settings", title: "Ciel Settings", subtitle: "Preferences", kind: .utility,
                    keywords: "hotkey shortcut permission accessibility login"),
                SearchEntry(
                    id: "rescan", title: "Rescan Applications", subtitle: "Ciel", kind: .utility,
                    keywords: "refresh index apps"),
            ]
        launcher.update(entries: entries, usage: history.counts, lastUsed: history.lastUsed)
    }
    @objc private func menuOpen() { present() }
    private func toggle() { if panel.isVisible { dismiss() } else { present() } }
    private func present() {
        guard !panel.isDragging else { return }
        let front = NSWorkspace.shared.frontmostApplication
        // Each queued window command retains its captured target. Opening a new
        // launcher session cannot redirect a command that is already running.
        windows.capture(
            pid: front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
                ? nil : front?.processIdentifier)
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

    private func recordUsage(_ entry: SearchEntry) {
        history.record(entry.id)
        launcher.updateUsage(history.counts, lastUsed: history.lastUsed)
    }
    private func execute(_ entry: SearchEntry) {
        if let action = entry.action {
            run(action, entry: entry)
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
                        self?.recordUsage(entry)
                    }
                }
            }
        } else if entry.id == "settings" {
            showSettings()
        } else if entry.id == "rescan" {
            dismiss()
            rescan()
        }
    }
    private func runDirect(_ action: WindowAction) {
        guard !executing else { return }
        if !panel.isVisible {
            windows.capture(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        }
        run(action, entry: SearchEntry.commands.first { $0.action == action }!)
    }
    private func run(_ action: WindowAction, entry: SearchEntry) {
        guard !executing else { return }
        guard WindowController.isTrusted else {
            dismiss()
            showSettings()
            WindowController.requestPermission()
            return
        }
        let displays = DisplaySnapshot.current()
        executing = true
        dismiss()
        windows.perform(action, displays: displays) { [weak self] result in
            guard let self else { return }
            self.executing = false
            switch result {
            case .success(let message):
                self.recordUsage(entry)
                // Successful snaps stay quiet. Explain only application-imposed limits.
                if message != action.title { self.hud.show(message) }
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
            settings?.onShortcutChange = { [weak self] in
                self?.statusItem.button?.toolTip =
                    "Ciel · \(self?.hotKeys.shortcuts["launcher"]?.display ?? "")"
            }
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

    private func finishUICheck() {
        guard !checkFinished else { return }
        checkFinished = true
        present()
        LauncherCheck.run(launcher: launcher, panel: panel, entries: catalog.entries)
    }

    private func finishPerformanceCheck() {
        guard !checkFinished else { return }
        checkFinished = true
        present()
        PerformanceCheck.run(
            launcher: launcher, panel: panel, startupMilliseconds: AppPerformance.startupMilliseconds)
    }

    private func finishSmokeTest() {
        guard !checkFinished else { return }
        checkFinished = true
        present()
        SmokeCheck.run(
            launcher: launcher, fieldEditor: fieldEditor, catalog: catalog, hotKeys: hotKeys,
            menu: statusItem.menu,
            showSettings: { [self] in
                showSettings()
                return settings
            },
            windowShortcuts: { [self] in windowShortcuts },
            showGuide: { [self] in
                showGuide()
                return keyboardGuide
            })
    }
}
