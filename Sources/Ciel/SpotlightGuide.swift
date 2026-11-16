import AppKit

@MainActor final class SpotlightGuide: NSObject {
    enum Replacement { case offered, replaced, waiting }

    /// The launcher shortcut line under or beside the recorder, so replacing Spotlight reads as part of the shortcut.
    final class Caption: NSStackView {
        let status = Theme.label("", size: 12, color: Theme.secondary)
        let link: TextButton
        let compact: Bool

        init(compact: Bool, target: SpotlightGuide) {
            self.compact = compact
            link = TextButton(target: target, action: #selector(SpotlightGuide.act))
            super.init(frame: .zero)
            spacing = 6
            alignment = .firstBaseline
            setViews([status, link], in: .leading)
        }
        required init?(coder: NSCoder) { fatalError() }
        override var firstBaselineOffsetFromTop: CGFloat {
            (arrangedSubviews.first { !$0.isHidden } ?? status).firstBaselineOffsetFromTop
        }
    }

    var held: Shortcut?
    weak var owner: PreferencesController?
    let heading = Theme.label("", size: 20)
    let note = Theme.label("", size: 12, color: Theme.secondary)
    private let hotKeys: HotKeys
    private let spotlight: SpotlightShortcuts
    private let open: @MainActor (URL) -> Void
    private var rows: [(status: NSTextField, button: NSButton)] = []
    private var captions: [Caption] = []

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

    /// A compact caption shows only the state, for a recorder whose menu already offers ⌘Space.
    func caption(compact: Bool = false) -> Caption {
        let caption = Caption(compact: compact, target: self)
        captions.append(caption)
        return caption
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
        captions.removeAll { $0.window == nil }
        let offer = "Replace Spotlight with " + SpotlightShortcuts.commandSpace.display
        for caption in captions {
            caption.status.stringValue =
                switch replacement {
                case .offered: ""
                case .replaced: "Replaces Spotlight"
                case .waiting:
                    caption.compact ? "Used by Spotlight" : "Spotlight still uses " + (held?.display ?? "")
                }
            caption.status.isHidden = replacement == .offered
            caption.link.text = replacement == .waiting ? "Open Settings…" : offer
            caption.link.isHidden = caption.compact || replaced
        }
    }

    @objc fileprivate func act() {
        if held == nil {
            choose(SpotlightShortcuts.commandSpace)
        } else {
            open(SpotlightShortcuts.keyboardSettings)
        }
    }
}
