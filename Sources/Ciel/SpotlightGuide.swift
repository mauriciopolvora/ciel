import AppKit

@MainActor final class SpotlightGuide: NSObject {
    enum Replacement { case offered, replaced, waiting }

    var held: Shortcut?
    weak var owner: PreferencesController?
    let heading = Theme.label("", size: 20)
    let note = Theme.label("", size: 12, color: Theme.secondary)
    private let hotKeys: HotKeys
    private let spotlight: SpotlightShortcuts
    private let open: @MainActor (URL) -> Void
    private var rows: [(status: NSTextField, button: NSButton)] = []
    /// The state beside the launcher recorder. The recorder menu offers ⌘Space, so the caption only reports.
    let caption = Theme.label("", size: 12, color: Theme.secondary)

    var replacement: Replacement {
        if held != nil { return .waiting }
        let commandSpace = SpotlightShortcuts.commandSpace
        return hotKeys.shortcut(for: .launcher) == commandSpace && !spotlight.owns(commandSpace)
            ? .replaced : .offered
    }

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
        let replacement = self.replacement
        let replaced = replacement == .replaced
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
        caption.stringValue =
            switch replacement {
            case .offered: ""
            case .replaced: "Replaces Spotlight"
            case .waiting: "Used by Spotlight"
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
