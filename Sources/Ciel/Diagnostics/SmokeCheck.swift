import AppKit
import CielCore

@MainActor enum SmokeCheck {
    static func run(
        launcher: LauncherView, fieldEditor: MonochromeFieldEditor, catalog: AppCatalog, hotKeys: HotKeys,
        speech: SpeechModelStore, menu: NSMenu?, showSettings: @escaping () -> SettingsController?,
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
            guard windowShortcuts() == nil else {
                print("FAIL Window Shortcuts controller created before its menu action")
                exit(1)
            }
            guard let menu, let index = menu.items.firstIndex(where: { $0.title == "Window Shortcuts…" })
            else {
                print("FAIL Window Shortcuts menu item")
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
            captureSpeechStates(preferences, speech: speech, output: output)
            capturePillStates(output: output)
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

    /// Runs under the checks bundle id, so it changes only the checks defaults and never touches model files.
    private static func captureSpeechStates(
        _ settings: SettingsController, speech: SpeechModelStore, output: String
    ) {
        let preferences = Preferences()
        let wasEnabled = preferences.speechEnabled
        let original = speech.state
        preferences.speechEnabled = true
        for (name, state) in [
            ("not-downloaded", ModelState.notDownloaded), ("downloading", .downloading(fraction: 0.37)),
            ("ready", .ready), ("failed", .failed(ModelDownloadError.mismatch.localizedDescription)),
        ] {
            speech.showForCheck(state)
            settings.refresh()
            capture(settings.content, "settings-speech-" + name, output: output)
        }
        speech.showForCheck(original)
        preferences.speechEnabled = wasEnabled
        settings.refresh()
        print("PASS speech settings states")
    }

    private static func capturePillStates(output: String) {
        let pill = PillView()
        pill.appearance = NSAppearance(named: .darkAqua)
        pill.listen()
        for level: Float in [0.02, 0.06, 0.12, 0.04, 0.09] { pill.level(level) }
        captureLayer(of: pill, "pill-listening", output: output)
        pill.text(
            committed: "Send the quarterly report to Maria and ask her to", tentative: "check the numbers")
        pill.setFrameSize(NSSize(width: pill.fittingWidth, height: PillView.size.height))
        pill.layoutSubtreeIfNeeded()
        let speaking = captureLayer(of: pill, "pill-speaking", output: output)
        let shown = speaking.map { bitmap in
            stride(from: 160, to: bitmap.pixelsWide, by: 2).contains { x in
                (0..<bitmap.pixelsHigh).contains {
                    (bitmap.colorAt(x: x, y: $0)?.brightnessComponent ?? 0) > 0.5
                }
            }
        }
        guard shown == true else {
            print("FAIL dictation pill shows no words")
            exit(1)
        }
        pill.transcribe()
        captureLayer(of: pill, "pill-transcribing", output: output)
        print("PASS dictation pill states")
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

    /// Renders the layer tree, since the pill draws its bars in sublayers that `cacheDisplay` skips.
    @discardableResult
    private static func captureLayer(of view: NSView, _ name: String, output: String) -> NSBitmapImageRep? {
        guard let layer = view.layer,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
                pixelsHigh: Int(view.bounds.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        context.cgContext.scaleBy(x: 2, y: 2)
        layer.render(in: context.cgContext)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: output + "/" + name + ".png"))
        }
        return bitmap
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
