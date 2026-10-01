import AppKit
import CielCore

/// Captures native surfaces and checks real menu actions in an isolated test app.
@MainActor enum SmokeCheck {
    static func run(
        launcher: LauncherView, fieldEditor: MonochromeFieldEditor, catalog: AppCatalog, hotKeys: HotKeys,
        menu: NSMenu?, showSettings: @escaping () -> SettingsController?,
        windowShortcuts: @escaping () -> WindowShortcutsController?,
        showGuide: @escaping () -> KeyboardGuideController?
    ) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            let output =
                ProcessInfo.processInfo.environment["CIEL_SMOKE_OUTPUT"] ?? NSTemporaryDirectory()
                + "ciel-smoke"
            try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
            capture(launcher, "launcher-empty", output: output)
            launcher.searchField.stringValue = "calclator"
            launcher.updateResults()
            fieldEditor.setSelectedRange(NSRange(location: launcher.searchField.stringValue.count, length: 0))
            await settleIcons(in: launcher)
            capture(launcher, "launcher-search", output: output)
            launcher.searchField.stringValue = "half"
            launcher.selectFilter(2)
            capture(launcher, "launcher", output: output)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                capture(launcher, "launcher-" + name, output: output)
            }
            NSApp.appearance = NSAppearance(named: .darkAqua)
            let preferences = showSettings()
            // Exercise the real menu action while keeping this controller lazy in normal use.
            guard windowShortcuts() == nil, let menu,
                let index = menu.items.firstIndex(where: { $0.title == "Window Shortcuts…" })
            else {
                print("FAIL window-shortcut menu setup")
                exit(1)
            }
            menu.performActionForItem(at: index)
            guard let preferences, let shortcuts = windowShortcuts(), shortcuts.window?.isVisible == true
            else {
                print("FAIL window-shortcut menu action")
                exit(1)
            }
            print("PASS separate Window Shortcuts menu action")
            guard let guide = showGuide(), guide.window?.isVisible == true else {
                print("FAIL keyboard guide")
                exit(1)
            }
            print("PASS keyboard guide")
            for (name, controller) in [
                ("settings", preferences as PreferencesController),
                ("window-shortcuts", shortcuts as PreferencesController),
                ("keyboard-guide", guide as PreferencesController),
            ] {
                capture(controller.content, name, output: output)
                for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    NSApp.appearance = NSAppearance(named: appearance)
                    capture(controller.content, name + "-" + mode, output: output)
                }
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
            let report: [String: Any] = [
                "applicationCount": catalog.entries.count, "commandCount": SearchEntry.commands.count,
                "visibleResults": launcher.results.count, "accessibilityGranted": WindowController.isTrusted,
                "hotkeyErrors": hotKeys.registrationErrors,
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
            ]
            if let data = try? JSONSerialization.data(
                withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            {
                try? data.write(to: URL(fileURLWithPath: output + "/report.json"))
                print(String(data: data, encoding: .utf8)!)
            }
            NSApp.terminate(nil)
        }
    }

    private static func settleIcons(in launcher: LauncherView) async {
        launcher.layoutSubtreeIfNeeded()
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while launcher.pendingIconCount > 0 {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                print("FAIL smoke icon loads timed out")
                exit(1)
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func capture(_ view: NSView, _ name: String, output: String) {
        view.layoutSubtreeIfNeeded()
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: output + "/" + name + ".png"))
            }
        }
    }
}
