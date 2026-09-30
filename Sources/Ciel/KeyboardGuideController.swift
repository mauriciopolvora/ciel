import AppKit

final class KeyboardGuideController: PreferencesController {
    private let launcherShortcut = Theme.label("", size: 13, weight: .medium, color: Theme.accent)
    init(hotKeys: HotKeys) {
        super.init(title: "Ciel Keyboard Guide", size: NSSize(width: 480, height: 380), hotKeys: hotKeys)
        label("Keyboard guide", x: 28, y: 22, width: 400, size: 20, in: content)
        label(
            "Open Ciel, then type an app or window command.", x: 28, y: 54,
            width: 424, size: 12, color: Theme.secondary, in: content)
        let rows = [
            ("", "Show or hide Ciel"), ("↑  ↓", "Select a result"), ("↩", "Open or run the selected result"),
            ("⌘1 … ⌘9", "Run one of the first nine results"), ("⇥  /  ⇧⇥", "Change search category"),
            ("⎋", "Close Ciel"), ("⌘,", "Open Settings"),
        ]
        let list = group(NSRect(x: 20, y: 88, width: 440, height: 7 * 36))
        for (index, row) in rows.enumerated() {
            let y = CGFloat(index) * 36 + 8
            if index == 0 {
                launcherShortcut.frame = NSRect(x: 16, y: y, width: 132, height: 21)
                list.addSubview(launcherShortcut)
            } else {
                label(row.0, y: y, width: 132, size: 13, color: Theme.accent, in: list)
            }
            label(row.1, x: 154, y: y, width: 270, size: 13, in: list)
        }
        label(
            "Hold Command to show result shortcuts.", x: 28, y: 350,
            width: 424, size: 12, color: Theme.secondary, in: content)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func refresh() {
        super.refresh()
        launcherShortcut.stringValue = hotKeys.shortcuts["launcher"]?.display ?? "Not available"
    }
}
