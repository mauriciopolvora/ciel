import AppKit

extension PreferencesController {
    static let nameEdge: CGFloat = 172
    static let controlEdge: CGFloat = 188

    func column(
        _ name: String, _ controls: [NSView], at y: inout CGFloat, height: CGFloat = 36,
        in parent: NSView? = nil
    ) {
        let center = y + height / 2
        if !name.isEmpty {
            let label = Theme.label(name, size: 13, color: Theme.secondary)
            label.alignment = .right
            place(label, right: Self.nameEdge, centerY: center, in: parent)
        }
        let line = stack(controls)
        line.alignment = .firstBaseline
        place(line, x: Self.controlEdge, centerY: center, in: parent)
        line.trailingAnchor.constraint(lessThanOrEqualTo: (parent ?? content).leadingAnchor, constant: 444)
            .isActive = true
        y += height
    }

    func rule(at y: inout CGFloat, in parent: NSView? = nil) {
        (parent ?? content).addSubview(Divider(frame: NSRect(x: 36, y: y + 12, width: 408, height: 1)))
        y += 25
    }

    func switchLine(_ toggle: MonochromeSwitch, _ name: String) -> NSView {
        let label = TextButton(size: 13, target: toggle, action: #selector(NSButton.performClick(_:)))
        label.text = name
        return stack([toggle, label])
    }

    func stack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.spacing = 8
        return stack
    }

    func place(
        _ view: NSView, x: CGFloat? = nil, right: CGFloat? = nil, top: CGFloat? = nil,
        centerY: CGFloat? = nil,
        in parent: NSView? = nil
    ) {
        let parent = parent ?? content
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
        var constraints: [NSLayoutConstraint] = []
        if let x {
            constraints.append(view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: x))
        }
        if let right {
            constraints.append(view.trailingAnchor.constraint(equalTo: parent.leadingAnchor, constant: right))
        }
        if let top {
            constraints.append(view.topAnchor.constraint(equalTo: parent.topAnchor, constant: top))
        }
        if let centerY {
            constraints.append(view.centerYAnchor.constraint(equalTo: parent.topAnchor, constant: centerY))
        }
        NSLayoutConstraint.activate(constraints)
    }
}
