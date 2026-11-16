import AppKit

@MainActor final class SpotlightGuide: NSObject {
    var held: Shortcut?
    weak var owner: PreferencesController?
    let heading = Theme.label("", size: 20)
    let note = Theme.label("", size: 12, color: Theme.secondary)
    private let hotKeys: HotKeys
    private let spotlight: SpotlightShortcuts
    private let open: @MainActor (URL) -> Void
    private var rows: [(status: NSTextField, button: NSButton)] = []

    init(hotKeys: HotKeys, spotlight: SpotlightShortcuts, open: @escaping @MainActor (URL) -> Void) {
        self.hotKeys = hotKeys
        self.spotlight = spotlight
        self.open = open
        super.init()
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 2
    }

    func row() -> [NSView] {
        let status = PreferencesController.status()
        let button = NSButton(title: "", target: self, action: #selector(act))
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        button.widthAnchor.constraint(equalToConstant: 120).isActive = true
        rows.append((status, button))
        return [status, button]
    }

    func choose(_ shortcut: Shortcut?) {
        guard let shortcut else {
            owner?.showMessage(HotKeyError.required.localizedDescription)
            return
        }
        if spotlight.owns(shortcut) {
            held = shortcut
            owner?.showMessage("")
            open(SpotlightShortcuts.keyboardSettings)
        } else {
            held = nil
            do {
                try hotKeys.update(.launcher, to: shortcut)
                owner?.showMessage("")
            } catch { owner?.showMessage(error.localizedDescription) }
        }
        owner?.refresh()
    }

    func tick() {
        guard let held, !spotlight.owns(held) else { return }
        choose(held)
        if owner?.window?.isVisible == true { owner?.present() }
    }

    func refresh() {
        let replaced =
            held == nil && hotKeys.shortcut(for: .launcher) == SpotlightShortcuts.commandSpace
            && !spotlight.owns(SpotlightShortcuts.commandSpace)
        note.isHidden = held == nil
        if let held, let action = spotlight.action(holding: held) {
            heading.stringValue = "Free \(held.display) from Spotlight"
            note.stringValue =
                "In Keyboard Shortcuts, select Spotlight and turn off \(action). Ciel switches when \(held.display) is free."
        }
        for (status, button) in rows {
            button.isHidden = replaced
            button.title = held == nil ? "Use " + SpotlightShortcuts.commandSpace.display : "Open Settings…"
            status.stringValue = held != nil ? "Used by Spotlight" : replaced ? "Replaced" : ""
            status.textColor = held == nil ? Theme.success : Theme.secondary
        }
    }

    @objc private func act() {
        if held == nil {
            choose(SpotlightShortcuts.commandSpace)
        } else {
            open(SpotlightShortcuts.keyboardSettings)
        }
    }
}
