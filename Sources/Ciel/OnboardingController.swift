import AppKit

final class OnboardingController: PreferencesController {
    enum Step: Int { case shortcut, access }
    private static let heights: [Step: CGFloat] = [.shortcut: 288, .access: 208]

    var onFinish: (() -> Void)?
    private(set) var step = Step.shortcut
    let spotlightGuide: SpotlightGuide
    let helper = AccessibilityHelper()
    private let isTrusted: @MainActor () -> Bool
    private let open: @MainActor (URL) -> Void
    private var pages: [FlippedView] = []
    private let accessStatus = OnboardingController.status()
    private let accessButton = NSButton(title: "Open Settings…", target: nil, action: nil)
    private var poll: Task<Void, Never>?

    init(
        hotKeys: HotKeys, spotlight: SpotlightShortcuts = .system,
        isTrusted: @escaping @MainActor () -> Bool = { WindowController.isTrusted },
        open: @escaping @MainActor (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
    ) {
        spotlightGuide = SpotlightGuide(hotKeys: hotKeys, spotlight: spotlight, open: open)
        self.isTrusted = isTrusted
        self.open = open
        super.init(
            title: "Set Up Ciel", size: NSSize(width: 480, height: Self.heights[.shortcut]!), hotKeys: hotKeys
        )
        spotlightGuide.owner = self
        if let current = hotKeys.shortcut(for: .launcher), spotlight.owns(current) {
            spotlightGuide.held = current
        }
        let launcher = recorder(.launcher, label: "Launcher shortcut")
        launcher.onRecord = { [weak self] shortcut in self?.spotlightGuide.choose(shortcut) }
        accessButton.bezelStyle = .rounded
        accessButton.font = .systemFont(ofSize: 12)
        accessButton.target = self
        accessButton.action = #selector(allowAccess)
        for control in [launcher, accessButton] {
            control.widthAnchor.constraint(equalToConstant: 120).isActive = true
        }

        let shortcut = page("Choose a shortcut", "Press it in any app to open Ciel.")
        let shortcutRows = rows(
            [("Shortcut", [launcher]), ("Replace Spotlight", spotlightGuide.row())], at: 88, in: shortcut)
        spotlightGuide.note.frame = NSRect(x: 36, y: shortcutRows.frame.maxY + 12, width: 408, height: 32)
        shortcut.addSubview(spotlightGuide.note)
        footer("Continue", #selector(advance), top: 236, in: shortcut)

        let access = page(
            "Allow window control", "Ciel needs Accessibility access to move windows and paste dictation.")
        let accessRows = rows([("Accessibility", [accessStatus, accessButton])], at: 88, in: access)
        footer("Not Now", #selector(NSWindowController.close), top: accessRows.frame.maxY + 24, in: access)
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

    override func refresh() {
        super.refresh()
        for (index, page) in pages.enumerated() { page.isHidden = index != step.rawValue }
        spotlightGuide.refresh()
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

    func tick() {
        spotlightGuide.tick()
        guard step == .access, isTrusted() else { return }
        hotKeys.retryUnregistered()
        close()
    }

    func show(_ step: Step) {
        self.step = step
        resize(toHeight: Self.heights[step]!)
        refresh()
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
