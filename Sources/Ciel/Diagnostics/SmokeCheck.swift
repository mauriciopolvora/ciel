import AppKit
import CielCore
import ImageIO
import UniformTypeIdentifiers

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
            await captureLauncherDesigns(launcher, fieldEditor: fieldEditor, output: output)
            launcher.searchField.stringValue = "half"
            launcher.selectFilter(2)
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
            menu.update()
            let titles = menu.items.map(\.title)
            guard let about = titles.firstIndex(of: "About Ciel…"), titles[about + 1] == "Check for Updates…",
                !menu.items[about + 1].isEnabled
            else {
                print("FAIL Check for Updates menu item")
                exit(1)
            }
            print("PASS Check for Updates menu item, off while the updater is stopped")
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
            captureSettingsDesigns(preferences, speech: speech, output: output)
            captureSpeechStates(preferences, speech: speech, output: output)
            capturePillStates(output: output)
            captureOnboarding(output: output)
            captureSpotlightSheet(speech: speech, output: output)
            captureDragHint(output: output)
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
    /// Writes launcher-design-<design>-<state>-<mode>.png. Only Graphite follows the system, so the A and C light
    /// captures match their dark ones.
    private static func captureLauncherDesigns(
        _ launcher: LauncherView, fieldEditor: MonochromeFieldEditor, output: String
    ) async {
        for design in LauncherDesign.allCases {
            for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                launcher.applyDesign(design, systemDark: appearance == .darkAqua)
                launcher.selectFilter(0)
                for (state, query) in [("empty", ""), ("results", "c"), ("none", "zzzzzzzzzzzz")] {
                    launcher.searchField.stringValue = query
                    launcher.updateResults()
                    fieldEditor.setSelectedRange(NSRange(location: query.count, length: 0))
                    await settleIcons(in: launcher)
                    capture(launcher, "launcher-design-\(design.rawValue)-\(state)-\(mode)", output: output)
                }
            }
        }
        launcher.refreshDesign(force: true)
    }

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

    /// Captures each Settings design as shipped, then with ⌘Space replacing Spotlight in an isolated controller.
    private static func captureSettingsDesigns(
        _ settings: SettingsController, speech: SpeechModelStore, output: String
    ) {
        let preview = DesignPreview()
        let original = preview.settings
        let suite = "ciel.checks.settings-design"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for design in SettingsDesign.allCases {
            preview.settings = design
            settings.show(design)
            guard settings.design == design, settings.recorders[.launcher]?.window === settings.window else {
                print("FAIL Settings did not switch to design \(design.letter)")
                exit(1)
            }
            let name = "settings-design-" + design.rawValue
            captureModes(settings.content, name, output: output)
            defaults.removePersistentDomain(forName: suite)
            let state = CheckSystemState()
            state.symbolicHotKeys = ["64": ["enabled": false]]
            let hotKeys = HotKeys(
                defaults: defaults, registrar: AcceptingRegistrar(), onPress: { _ in }, onChange: {})
            let replaced = SettingsController(
                hotKeys: hotKeys, speech: speech, updater: Updater(),
                spotlight: SpotlightShortcuts { state.symbolicHotKeys }, open: { state.opened.append($0) })
            replaced.present()
            replaced.recorders[.launcher]?.accept(SpotlightShortcuts.commandSpace)
            guard replaced.design == design, replaced.spotlightGuide.replacement == .replaced,
                hotKeys.shortcut(for: .launcher) == SpotlightShortcuts.commandSpace
            else {
                print("FAIL Settings design \(design.letter) did not take ⌘Space from a free Spotlight")
                exit(1)
            }
            captureModes(replaced.content, name + "-spotlight", output: output)
            replaced.close()
        }
        preview.settings = original
        settings.show(original)
        print("PASS settings designs")
    }

    private static func captureModes(_ view: NSView, _ name: String, output: String) {
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            capture(view, name + "-" + mode, output: output)
        }
        NSApp.appearance = NSAppearance(named: .darkAqua)
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
        let bright = speaking.map { bitmap in
            let points = stride(from: 160, to: bitmap.pixelsWide, by: 2).flatMap { x in
                (0..<bitmap.pixelsHigh).map { (x, $0) }
            }
            let lit = points.filter { (bitmap.colorAt(x: $0.0, y: $0.1)?.brightnessComponent ?? 0) > 0.5 }
            return Double(lit.count) / Double(max(points.count, 1))
        }
        guard let bright, bright > 0, bright < 0.25 else {
            print("FAIL dictation pill words are missing or on a light box")
            exit(1)
        }
        pill.transcribe()
        captureLayer(of: pill, "pill-transcribing", output: output)
        print("PASS dictation pill states")
    }

    private static func captureOnboarding(output: String) {
        let suite = "ciel.checks.onboarding"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = CheckSystemState()
        let hotKeys = HotKeys(
            defaults: defaults, registrar: AcceptingRegistrar(), onPress: { _ in }, onChange: {})
        let onboarding = OnboardingController(
            hotKeys: hotKeys, spotlight: SpotlightShortcuts { state.symbolicHotKeys },
            isTrusted: { state.trusted }, open: { state.opened.append($0) })
        var finished = false
        onboarding.onFinish = { finished = true }
        onboarding.present()
        let frames: [(String, () -> Void)] = [
            ("onboarding-shortcut", {}),
            (
                "onboarding-shortcut-spotlight",
                { onboarding.spotlightGuide.choose(SpotlightShortcuts.commandSpace) }
            ),
            (
                "onboarding-shortcut-ready",
                {
                    state.symbolicHotKeys = ["64": ["enabled": false]]
                    onboarding.tick()
                }
            ),
            ("onboarding-access", { onboarding.show(.access) }),
        ]
        for (name, change) in frames {
            change()
            for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                capture(onboarding.content, name + "-" + mode, output: output)
            }
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        guard hotKeys.shortcut(for: .launcher) == SpotlightShortcuts.commandSpace,
            state.opened == [SpotlightShortcuts.keyboardSettings]
        else {
            print("FAIL onboarding did not take ⌘Space after Spotlight let go")
            exit(1)
        }
        state.trusted = true
        onboarding.tick()
        guard finished, onboarding.window?.isVisible == false else {
            print("FAIL onboarding did not finish after access was granted")
            exit(1)
        }
        print("PASS onboarding states")
    }

    private static func captureSpotlightSheet(speech: SpeechModelStore, output: String) {
        let suite = "ciel.checks.settings-spotlight"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = CheckSystemState()
        let hotKeys = HotKeys(
            defaults: defaults, registrar: AcceptingRegistrar(), onPress: { _ in }, onChange: {})
        let settings = SettingsController(
            hotKeys: hotKeys, speech: speech, updater: Updater(),
            spotlight: SpotlightShortcuts { state.symbolicHotKeys }, open: { state.opened.append($0) })
        settings.present()
        settings.recorders[.launcher]?.accept(SpotlightShortcuts.commandSpace)
        guard let sheet = settings.window?.attachedSheet?.contentView else {
            print("FAIL Settings did not open the Spotlight guide for ⌘Space")
            exit(1)
        }
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            capture(sheet, "settings-spotlight-guide-" + mode, output: output)
        }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        state.symbolicHotKeys = ["64": ["enabled": false]]
        settings.spotlightGuide.tick()
        guard hotKeys.shortcut(for: .launcher) == SpotlightShortcuts.commandSpace,
            state.opened == [SpotlightShortcuts.keyboardSettings], settings.spotlightGuide.held == nil
        else {
            print("FAIL Settings did not take ⌘Space after Spotlight let go")
            exit(1)
        }
        settings.close()
        print("PASS settings Spotlight guide")
    }

    private static func captureDragHint(output: String) {
        let card = DragCard(frame: NSRect(origin: .zero, size: DragCard.size))
        let trail = DragTrail(
            frame: NSRect(x: 0, y: 0, width: DragCard.iconFrame.width, height: DragTrail.height))
        for view in [card, trail] { view.appearance = NSAppearance(named: .darkAqua) }
        guard let cardImage = captureLayer(of: card, "onboarding-drag-card", output: output),
            let trailLayer = trail.layer
        else {
            print("FAIL drag hint card")
            exit(1)
        }
        let icon = DragCard.iconFrame
        let base = DragCard.size.height - icon.maxY
        let size = NSSize(width: DragCard.size.width, height: base + DragTrail.height)
        let count = 36
        let images = (0..<count).compactMap { index -> CGImage? in
            trail.show(at: Double(index) / Double(count))
            guard
                let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap)
            else { return nil }
            let cg = context.cgContext
            cg.scaleBy(x: 2, y: 2)
            cg.setFillColor(Theme.cg(Theme.selection, in: card))
            cg.fill(CGRect(origin: .zero, size: size))
            NSGraphicsContext.current = context
            cardImage.draw(in: NSRect(origin: .zero, size: DragCard.size))
            NSGraphicsContext.current = nil
            cg.translateBy(x: icon.minX, y: base)
            trailLayer.render(in: cg)
            return bitmap.cgImage
        }
        let url = URL(fileURLWithPath: output + "/onboarding-drag.gif") as CFURL
        guard images.count == count,
            let gif = CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString, count, nil)
        else {
            print("FAIL drag hint frames")
            exit(1)
        }
        let delay = DragTrail.cycle / Double(count)
        CGImageDestinationSetProperties(
            gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for image in images {
            CGImageDestinationAddImage(
                gif, image,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else {
            print("FAIL drag hint GIF")
            exit(1)
        }
        print("PASS drag hint animation")
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

    /// Renders the layer tree, since the pill draws its bars in sublayers that `cacheDisplay` skips, then draws the
    /// subviews over it.
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
        NSGraphicsContext.current = context
        for subview in view.subviews where !subview.isHidden {
            guard
                let image = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(subview.bounds.width * 2),
                    pixelsHigh: Int(subview.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                    bitsPerPixel: 0)
            else { continue }
            image.size = subview.bounds.size
            subview.cacheDisplay(in: subview.bounds, to: image)
            let frame = subview.frame
            image.draw(
                in: NSRect(
                    x: frame.minX, y: view.isFlipped ? view.bounds.height - frame.maxY : frame.minY,
                    width: frame.width, height: frame.height), from: .zero, operation: .sourceOver,
                fraction: 1,
                respectFlipped: false, hints: nil)
        }
        NSGraphicsContext.current = nil
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: output + "/" + name + ".png"))
        }
        return bitmap
    }

    /// Renders at 2x, since CI displays run at 1x and the docs screenshots come from these captures.
    @discardableResult
    private static func capture(_ view: NSView, _ name: String, output: String) -> NSBitmapImageRep? {
        view.layoutSubtreeIfNeeded()
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
                pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: output + "/" + name + ".png"))
        }
        return bitmap
    }
}

@MainActor private final class CheckSystemState {
    var symbolicHotKeys: [String: Any]?
    var trusted = false
    var opened: [URL] = []
}

@MainActor private struct AcceptingRegistrar: HotKeyRegistrar {
    func register(_ shortcut: Shortcut, handler: @escaping @MainActor (HotKeyEvent) -> Void) throws -> Cleanup
    {
        Cleanup {}
    }
}
