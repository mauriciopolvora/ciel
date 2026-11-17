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

    /// Plays a scripted dictation through the pill: transcript passes every 0.5 s like the live engine, and levels
    /// from a fixed speech-shaped curve, since the check has no microphone. Writes stills and a GIF of the run.
    private static func capturePillStates(output: String) {
        let pill = PillView()
        let words =
            ("Send the quarterly report to Maria and ask her to check the numbers before Friday, then book a room"
            + " for the review with the whole team and share the notes afterwards so everyone knows what"
            + " changed since last quarter and who owns each follow up").split(separator: " ")
        let passes = [
            (120, 0, 2), (170, 2, 5), (220, 5, 10), (270, 10, 17), (320, 17, 25), (370, 25, 33),
            (420, 33, words.count),
        ]
        let stills = [100: "pill-listening", 215: "pill-short", 465: "pill-long"]
        let block = 512.0 / 48_000
        var heard = 0.0
        var frames: [CGImage] = []
        for step in 0...570 {
            let time = Double(step) / 100
            if step == 0 { pill.listen(reduceMotion: false) }
            if let pass = passes.first(where: { $0.0 == step }) {
                pill.text(
                    committed: words[..<pass.1].joined(separator: " "),
                    tentative: words[pass.1..<pass.2].joined(separator: " "))
            }
            if step == 470 { pill.transcribe() }
            if step == 520 { pill.text(committed: words.joined(separator: " "), tentative: "") }
            if step == 530 { pill.hide() }
            while heard + 8 * block <= time {
                pill.hear((0..<8).map { speechLevel(at: heard + Double($0) * block) }, every: block)
                heard += 8 * block
            }
            pill.advance(by: 0.01)
            if step % 4 == 0, let frame = renderPill(pill)?.cgImage { frames.append(frame) }
            guard let name = stills[step] else { continue }
            for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                guard let image = renderPill(pill), checkPill(pill, name, image) else {
                    print("FAIL dictation pill \(name) in \(mode) appearance")
                    exit(1)
                }
                try? image.representation(using: .png, properties: [:])?.write(
                    to: URL(fileURLWithPath: output + "/" + name + "-" + mode + ".png"))
            }
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        guard pill.visibility == 0, writeGIF(frames, delay: 0.04, to: output + "/pill-dictation.gif") else {
            print("FAIL dictation pill animation")
            exit(1)
        }
        print("PASS dictation pill states")
    }

    /// A check fixture shaped like speech: syllable bursts under a slower phrase envelope, then silence.
    private static func speechLevel(at time: Double) -> Float {
        guard time < 4.7 else { return 0.003 }
        return Float(
            0.003 + 0.09 * abs(sin(2 * .pi * 2.3 * time)) * (0.55 + 0.45 * sin(2 * .pi * 0.4 * time)))
    }

    /// Bars must be lit while listening. The transcript must hold light words on its dark surface, one line when
    /// short, and at the cap with older lines fading once it overflows.
    private static func checkPill(_ pill: PillView, _ name: String, _ image: NSBitmapImageRep) -> Bool {
        let canvas = PillLayout.canvas
        let waveform = CGRect(
            x: (canvas.width - PillLayout.waveform.width) / 2, y: PillLayout.margin,
            width: PillLayout.waveform.width, height: PillLayout.waveform.height)
        let bars = litFraction(image, in: waveform.insetBy(dx: 4, dy: 2))
        let words = litFraction(image, in: pill.transcriptFrame.insetBy(dx: 4, dy: 2))
        let height = pill.transcriptFrame.height
        switch name {
        case "pill-listening": return bars > 0.02 && !pill.showsTranscript
        case "pill-short":
            return bars > 0.02 && pill.lineCount == 1 && abs(height - 32) < 0.5 && words > 0 && words < 0.25
        default:
            return pill.lineCount > PillLayout.maxLines && abs(height - 64) < 0.5
                && pill.olderLinesFade > 0.95
                && words > 0 && words < 0.25
        }
    }

    private static func litFraction(_ image: NSBitmapImageRep, in rect: CGRect) -> Double {
        let height = PillLayout.canvas.height
        var lit = 0
        var total = 0
        for x in stride(from: Int(rect.minX * 2), to: Int(rect.maxX * 2), by: 2) {
            for y in stride(from: Int((height - rect.maxY) * 2), to: Int((height - rect.minY) * 2), by: 2) {
                total += 1
                if (image.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.5 { lit += 1 }
            }
        }
        return Double(lit) / Double(max(total, 1))
    }

    /// The pill's layer tree at 2x over a gray backdrop, since the panel itself is clear.
    private static func renderPill(_ pill: PillView) -> NSBitmapImageRep? {
        let size = pill.bounds.size
        guard let layer = pill.layer,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        let cg = context.cgContext
        cg.scaleBy(x: 2, y: 2)
        cg.setFillColor(Theme.cg(Theme.selection, in: pill))
        cg.fill(CGRect(origin: .zero, size: size))
        layer.render(in: cg)
        return bitmap
    }

    private static func writeGIF(_ images: [CGImage], delay: Double, to path: String) -> Bool {
        guard !images.isEmpty,
            let gif = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, images.count, nil)
        else { return false }
        CGImageDestinationSetProperties(
            gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for image in images {
            CGImageDestinationAddImage(
                gif, image,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        return CGImageDestinationFinalize(gif)
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
        guard images.count == count,
            writeGIF(images, delay: DragTrail.cycle / Double(count), to: output + "/onboarding-drag.gif")
        else {
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

    /// Renders the layer tree, since sublayers drawn outside `draw(_:)` are skipped by `cacheDisplay`, then draws
    /// the subviews over it.
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
