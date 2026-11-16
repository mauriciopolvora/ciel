import AppKit

/// Walks a new user through the launcher shortcut, then window access. It opens System Settings at the right pane,
/// but only the user changes a system setting. Polling sees the change and moves on.
final class OnboardingController: PreferencesController {
    enum Step: Int { case shortcut, access }
    private static let heights: [Step: CGFloat] = [.shortcut: 288, .access: 208]

    var onFinish: (() -> Void)?
    private(set) var step = Step.shortcut
    /// A shortcut that Spotlight still holds. The previous launcher shortcut stays live until Spotlight lets go.
    private(set) var waiting: Shortcut?
    let helper = AccessibilityHelper()
    private let spotlight: SpotlightShortcuts
    private let isTrusted: @MainActor () -> Bool
    private let open: @MainActor (URL) -> Void
    private var pages: [FlippedView] = []
    private let spotlightStatus = OnboardingController.status()
    private let spotlightButton = NSButton(title: "", target: nil, action: nil)
    private let spotlightNote = Theme.label(
        "In Keyboard Shortcuts, select Spotlight and turn off Show Spotlight search. Ciel switches when ⌘Space is free.",
        size: 12, color: Theme.secondary)
    private let accessStatus = OnboardingController.status()
    private let accessButton = NSButton(title: "Open Settings…", target: nil, action: nil)
    private var poll: Task<Void, Never>?

    init(
        hotKeys: HotKeys, spotlight: SpotlightShortcuts = .system,
        isTrusted: @escaping @MainActor () -> Bool = { WindowController.isTrusted },
        open: @escaping @MainActor (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
    ) {
        self.spotlight = spotlight
        self.isTrusted = isTrusted
        self.open = open
        super.init(
            title: "Set Up Ciel", size: NSSize(width: 480, height: Self.heights[.shortcut]!), hotKeys: hotKeys
        )
        if let current = hotKeys.shortcut(for: .launcher), spotlight.owns(current) { waiting = current }
        let launcher = recorder(.launcher, label: "Launcher shortcut")
        launcher.onRecord = { [weak self] shortcut in self?.choose(shortcut) }
        for (button, action) in [
            (spotlightButton, #selector(spotlightAction)), (accessButton, #selector(allowAccess)),
        ] {
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 12)
            button.target = self
            button.action = action
        }
        for control in [launcher, spotlightButton, accessButton] {
            control.widthAnchor.constraint(equalToConstant: 120).isActive = true
        }

        let shortcut = page("Choose a shortcut", "Press it in any app to open Ciel.")
        let bottom = rows(
            [("Shortcut", [launcher]), ("Replace Spotlight", [spotlightStatus, spotlightButton])], at: 88,
            in: shortcut)
        spotlightNote.frame = NSRect(x: 36, y: bottom + 12, width: 408, height: 32)
        spotlightNote.lineBreakMode = .byWordWrapping
        spotlightNote.maximumNumberOfLines = 2
        shortcut.addSubview(spotlightNote)
        footer("Continue", #selector(advance), top: 236, in: shortcut)

        let access = page(
            "Allow window control", "Ciel needs Accessibility access to move windows and paste dictation.")
        let accessBottom = rows([("Accessibility", [accessStatus, accessButton])], at: 88, in: access)
        footer("Not Now", #selector(NSWindowController.close), top: accessBottom + 24, in: access)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func page(_ title: String, _ subtitle: String) -> FlippedView {
        let page = FlippedView(frame: content.bounds)
        page.autoresizingMask = [.width, .height]
        let heading = Theme.label(title, size: 20)
        heading.frame = NSRect(x: 36, y: 24, width: 408, height: 26)
        let detail = Theme.label(subtitle, size: 12, color: Theme.secondary)
        detail.frame = NSRect(x: 36, y: 56, width: 408, height: 16)
        for label in [heading, detail] { page.addSubview(label) }
        content.addSubview(page)
        pages.append(page)
        return page
    }

    private func footer(_ title: String, _ action: Selector, top: CGFloat, in page: NSView) {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: page.topAnchor, constant: top),
            button.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -20),
        ])
    }

    override func refresh() {
        super.refresh()
        for (index, page) in pages.enumerated() { page.isHidden = index != step.rawValue }
        spotlightNote.isHidden = waiting == nil
        spotlightButton.isHidden =
            waiting == nil && hotKeys.shortcut(for: .launcher) == SpotlightShortcuts.commandSpace
        spotlightButton.title =
            waiting == nil ? "Use " + SpotlightShortcuts.commandSpace.display : "Open Settings…"
        spotlightStatus.stringValue =
            waiting != nil ? "Used by Spotlight" : spotlightButton.isHidden ? "Replaced" : ""
        spotlightStatus.textColor = waiting == nil ? Theme.success : Theme.secondary
        let trusted = isTrusted()
        accessStatus.stringValue = trusted ? "Allowed" : "Not allowed"
        accessStatus.textColor = trusted ? Theme.success : Theme.secondary
        accessButton.isHidden = trusted
    }

    override func present() {
        super.present()
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.tick()
            }
        }
    }

    /// Saves a shortcut only once macOS no longer handles it first. Otherwise opens Keyboard settings and waits.
    func choose(_ shortcut: Shortcut?) {
        guard let shortcut else { return showMessage(HotKeyError.required.localizedDescription) }
        if spotlight.owns(shortcut) {
            waiting = shortcut
            showMessage("")
            open(SpotlightShortcuts.keyboardSettings)
        } else {
            waiting = nil
            do {
                try hotKeys.update(.launcher, to: shortcut)
                showMessage("")
            } catch { showMessage(error.localizedDescription) }
        }
        refresh()
    }

    func tick() {
        if let waiting, !spotlight.owns(waiting) {
            choose(waiting)
            if window?.isVisible == true { present() }
        }
        guard step == .access, isTrusted() else { return }
        hotKeys.retryUnregistered()
        close()
    }

    func show(_ step: Step) {
        self.step = step
        resize(toHeight: Self.heights[step]!)
        refresh()
    }

    @objc private func spotlightAction() {
        if waiting == nil {
            choose(SpotlightShortcuts.commandSpace)
        } else {
            open(SpotlightShortcuts.keyboardSettings)
        }
    }

    @objc private func advance() {
        if isTrusted() { close() } else { show(.access) }
    }

    @objc private func allowAccess() {
        open(AccessibilityHelper.settingsURL)
        helper.show()
    }

    override func windowWillClose(_ notification: Notification) {
        super.windowWillClose(notification)
        poll?.cancel()
        poll = nil
        helper.close()
        onFinish?()
    }
}
