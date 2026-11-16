import AppKit

/// The Settings layouts that the Design preview switches between. Each returns its content height.
extension SettingsController {
    /// A: grouped rows, with the Spotlight state as a caption under the launcher shortcut label.
    func buildGrouped() -> CGFloat {
        let launcher = launcherRecorder()
        launcher.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        var y = groupedSection(
            "General", at: 24,
            rows: [
                ("Launcher shortcut", [launcher]), ("Launch at login", [login]), ("Animations", [animations]),
                ("Show menu bar icon", [menuBarIcon]), ("Automatically check for updates", [updateChecks]),
            ], caption: (0, spotlightGuide.caption()))
        y = groupedSection(
            "Permissions", at: y, rows: [("Accessibility", [permissionLabel, permissionButton])])
        y = groupedSection(
            "Dictation", at: y,
            rows: [
                ("Speech to text", [speechSwitch]), ("Shortcut", [dictationRecorder]),
                ("Speech model", [modelStatus, modelButton]),
            ])
        y = groupedSection(
            "Design preview", at: y,
            rows: [("Settings", [settingsDesignMenu]), ("Launcher", [launcherDesignMenu])])
        footerButtons(at: y)
        return y + 41
    }

    /// B: the launcher shortcut as large key caps on top, then a flat list with no boxes.
    func buildKeycaps() -> CGFloat {
        tracked("Launcher shortcut", at: 24)
        place(launcherRecorder(style: KeycapRecorder.self), x: 36, top: 48)
        place(spotlightGuide.caption(), x: 36, top: 98)
        content.addSubview(Divider(frame: NSRect(x: 36, y: 128, width: 408, height: 1)))
        var y = flatSection(
            "General", at: 145,
            rows: [
                ("Launch at login", [login]), ("Animations", [animations]),
                ("Show menu bar icon", [menuBarIcon]),
                ("Automatically check for updates", [updateChecks]),
            ])
        y = flatSection("Permissions", at: y, rows: [("Accessibility", [permissionLabel, permissionButton])])
        y = flatSection(
            "Dictation", at: y,
            rows: [
                ("Speech to text", [speechSwitch]), ("Shortcut", [dictationRecorder]),
                ("Speech model", [modelStatus, modelButton]),
            ])
        y = flatSection(
            "Design preview", at: y,
            rows: [("Settings", [settingsDesignMenu]), ("Launcher", [launcherDesignMenu])])
        footerButtons(at: y + 6)
        return y + 47
    }

    /// C: a label column and a control column, with a shortcut menu that offers ⌘Space as the Spotlight replacement.
    func buildColumns() -> CGFloat {
        let launcher = launcherRecorder(style: MenuRecorder.self)
        launcher.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        var y: CGFloat = 20
        column("Launcher shortcut", [launcher, spotlightGuide.caption(compact: true)], at: &y, height: 36)
        rule(at: &y)
        column("General", [switchLine(login, "Launch at login")], at: &y)
        column("", [switchLine(animations, "Animations")], at: &y)
        column("", [switchLine(menuBarIcon, "Show menu bar icon")], at: &y)
        column("", [switchLine(updateChecks, "Automatically check for updates")], at: &y)
        rule(at: &y)
        column("Accessibility", [permissionLabel, permissionButton], at: &y, height: 36)
        rule(at: &y)
        column("Dictation", [switchLine(speechSwitch, "Speech to text")], at: &y)
        column("Shortcut", [dictationRecorder], at: &y, height: 36)
        column("Speech model", [modelStatus, modelButton], at: &y, height: 36)
        rule(at: &y)
        column("Settings design", [settingsDesignMenu], at: &y, height: 36)
        column("Launcher design", [launcherDesignMenu], at: &y, height: 36)
        footerButtons(at: y + 20)
        return y + 61
    }

    private func groupedSection(
        _ title: String, at y: CGFloat, rows: [(String, [NSView])], caption: (row: Int, view: NSView)? = nil
    ) -> CGFloat {
        let header = Theme.label(title, size: 13, weight: .semibold, color: Theme.secondary)
        place(header, x: 36, top: y)
        return self.rows(rows, at: y + 23, caption: caption).frame.maxY + 20
    }

    private func tracked(_ title: String, at y: CGFloat) {
        let header = Theme.label("", size: 11)
        header.attributedStringValue = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: Theme.secondary,
                .kern: 0.8,
            ])
        place(header, x: 36, top: y)
    }

    private func flatSection(_ title: String, at y: CGFloat, rows: [(String, [NSView])]) -> CGFloat {
        tracked(title, at: y)
        for (index, (name, controls)) in rows.enumerated() {
            let center = y + 22 + CGFloat(index) * 36 + 18
            place(Theme.label(name, size: 13), x: 36, centerY: center)
            place(stack(controls), right: 444, centerY: center)
        }
        return y + 22 + CGFloat(rows.count) * 36 + 14
    }

    private func column(_ name: String, _ controls: [NSView], at y: inout CGFloat, height: CGFloat = 36) {
        let center = y + height / 2
        if !name.isEmpty {
            let label = Theme.label(name, size: 13, color: Theme.secondary)
            label.alignment = .right
            place(label, right: 172, centerY: center)
        }
        let line = stack(controls)
        line.alignment = .firstBaseline
        place(line, x: 188, centerY: center)
        y += height
    }

    private func rule(at y: inout CGFloat) {
        content.addSubview(Divider(frame: NSRect(x: 36, y: y + 12, width: 408, height: 1)))
        y += 25
    }

    private func switchLine(_ toggle: MonochromeSwitch, _ name: String) -> NSView {
        let label = TextButton(size: 13, target: toggle, action: #selector(NSButton.performClick(_:)))
        label.text = name
        return stack([toggle, label])
    }

    private func footerButtons(at y: CGFloat) {
        place(guideButton, x: 20, top: y)
        place(aboutButton, right: 460, top: y)
    }

    private func stack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.spacing = 8
        return stack
    }

    private func place(
        _ view: NSView, x: CGFloat? = nil, right: CGFloat? = nil, top: CGFloat? = nil, centerY: CGFloat? = nil
    ) {
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        var constraints: [NSLayoutConstraint] = []
        if let x {
            constraints.append(view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: x))
        }
        if let right {
            constraints.append(
                view.trailingAnchor.constraint(equalTo: content.leadingAnchor, constant: right))
        }
        if let top {
            constraints.append(view.topAnchor.constraint(equalTo: content.topAnchor, constant: top))
        }
        if let centerY {
            constraints.append(view.centerYAnchor.constraint(equalTo: content.topAnchor, constant: centerY))
        }
        NSLayoutConstraint.activate(constraints)
    }
}
