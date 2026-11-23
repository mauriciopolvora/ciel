import AppKit
import CielCore

@MainActor final class IntegrationCheck {
    private static let minimumSizeCommandLimit = 2 * WindowOperationEngine.frameBudget - 0.15
    private let controller = WindowController()
    private var child = Process()
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ciel-check-" + UUID().uuidString)
    private var steps: [(WindowAction, CGRect)] = []
    private var failures = 0
    private var launchedSettings = false
    private var enhancedFixture: (any WindowAccess)?
    private var minimumSizeFixture = false
    private var dictationKey: Cleanup?
    private var dictationEvents: [HotKeyEvent] = []
    private var dictationMessage: String?
    private var fixtureDirectory: URL {
        minimumSizeFixture ? directory.appendingPathComponent("minimum") : directory
    }

    func run() {
        guard WindowController.isTrusted else {
            print("SKIP: the test process has no Accessibility access")
            exit(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) { [weak self] in self?.finish(timeout: true) }
        NSApp.activate(ignoringOtherApps: true)
        startFixture()
    }

    private func startFixture() {
        if child.isRunning { child.terminate() }
        enhancedFixture = nil
        child = Process()
        child.executableURL = Bundle.main.executableURL!
        child.arguments =
            LaunchMode.processCheck(.fixture(output: fixtureDirectory.path, minimumSize: minimumSizeFixture))
            .arguments
        do {
            try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
            try child.run()
        } catch {
            failures += 1
            print("FAIL fixture: \(error)")
            finish()
            return
        }
        poll(
            readFrame, within: 3, until: { $0 != nil },
            then: { [self] original in
                guard let original else {
                    finish(timeout: true)
                    return
                }
                fixtureStarted(original: original)
            })
    }

    private func readFrame() -> CGRect? {
        guard let data = try? Data(contentsOf: fixtureDirectory.appendingPathComponent("frame.json")),
            let frame = try? JSONDecoder().decode(CGRect.self, from: data)
        else { return nil }
        return frame
    }

    private func readMinimized() -> Bool {
        let data = try? Data(contentsOf: directory.appendingPathComponent("minimized.json"))
        return data.flatMap { try? JSONDecoder().decode(Bool.self, from: $0) } ?? false
    }

    private func poll<Value>(
        _ read: @escaping () -> Value, within seconds: TimeInterval, until done: @escaping (Value) -> Bool,
        then body: @escaping (Value) -> Void
    ) {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        Task {
            var value = read()
            while !done(value), ProcessInfo.processInfo.systemUptime < deadline {
                try? await Task.sleep(for: .milliseconds(10))
                value = read()
            }
            body(value)
        }
    }

    private func fixtureStarted(original: CGRect) {
        let displays = DisplaySnapshot.current()
        guard let index = WindowGeometry.displayIndex(for: original, displays: displays.map(\.full)) else {
            failures += 1
            print("FAIL fixture frame \(original) is on no display")
            finish()
            return
        }
        let visible = displays[index].visible
        if minimumSizeFixture {
            checkMinimumSize(original: original, visible: visible)
            return
        }
        let left = WindowAction.leftHalf.frame(in: visible, current: original)
        let right = WindowAction.rightHalf.frame(in: visible, current: left)
        let centered = WindowAction.centerThreeFourths.frame(in: visible, current: right)
        let maximized = WindowAction.maximize.frame(in: visible, current: right)
        steps = [
            (.leftHalf, left), (.rightHalf, right), (.maximize, maximized),
            (.leftHalf, left), (.restore, maximized), (.rightHalf, right),
            (.centerThreeFourths, centered), (.restore, right),
        ]
        if displays.count > 1 {
            steps.append(
                (
                    .nextDisplay,
                    WindowGeometry.move(
                        right, from: visible, to: displays[(index + 1) % displays.count].visible)
                ))
            steps.append((.restore, right))
        }
        if let window = SystemWindowAccessibility().focusedWindow(pid: child.processIdentifier) {
            do {
                try window.setEnhancedUI(true, timeout: 0.25)
                enhancedFixture = window
            } catch {
                print("SKIP fixture Enhanced UI mode: \(error)")
            }
        } else {
            print("SKIP fixture Enhanced UI mode: no focused fixture window")
        }
        checkBackgroundDictation { [self] in
            next(on: controller.capture(ForeignProcess(child.processIdentifier)))
        }
    }

    private func checkBackgroundDictation(then body: @escaping () -> Void) {
        let hud = StatusHUD()
        let speech = SpeechModelStore(folder: directory)
        speech.showForCheck(.downloading(fraction: 0.37))
        let dictation = Dictation(
            recorder: SilentRecorder(),
            transcriber: {
                throw DictationError.blocking(speechEnabled: true, model: speech.state) ?? .notReady
            },
            deliver: { _ in },
            fail: { [weak self] message in
                self?.dictationMessage = message
                hud.show(message, error: true)
            })
        do {
            dictationKey = try SystemHotKeyRegistrar().register(.modifier(.rightCommand)) {
                [weak self] event in
                self?.dictationEvents.append(event)
                switch event {
                case .pressed: dictation.press()
                case .released: dictation.release()
                case .cancelled: dictation.cancel()
                }
            }
        } catch {
            failures += 1
            print("FAIL Background dictation: register Right ⌘: \(error.localizedDescription)")
            return body()
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Self.postRightCommand(down: true)
        Task { [self] in
            try? await Task.sleep(for: .milliseconds(50))
            Self.postRightCommand(down: false)
            poll(
                { [self] in
                    dictationEvents == [.pressed, .released] && dictationMessage?.contains("37%") == true
                        && Self.showsOwnWindow()
                },
                within: 2, until: { $0 },
                then: { [self] passed in
                    if !passed { failures += 1 }
                    print(
                        "\(passed ? "PASS" : "FAIL") Background dictation: events=\(dictationEvents), message=\(dictationMessage ?? "none"), hudOnScreen=\(Self.showsOwnWindow()), cielActive=\(NSApp.isActive), frontmostIsCiel=\(frontmost == getpid())"
                    )
                    dictationKey = nil
                    body()
                })
        }
    }

    private static func postRightCommand(down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(
            keyboardEventSource: source, virtualKey: CGKeyCode(ModifierKey.rightCommand.rawValue),
            keyDown: down)
        event?.type = .flagsChanged
        event?.flags =
            down
            ? CGEventFlags(
                rawValue: CGEventFlags.maskCommand.rawValue | UInt64(ModifierKey.rightCommand.flag))
            : []
        event?.post(tap: .cghidEventTap)
    }

    private static func showsOwnWindow() -> Bool {
        let windows =
            CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { $0[kCGWindowOwnerPID as String] as? pid_t == getpid() }
    }

    private func next(on target: WindowTarget) {
        guard !steps.isEmpty else {
            checkMinimize(on: target)
            return
        }
        let (action, expected) = steps.removeFirst()
        let started = ProcessInfo.processInfo.systemUptime
        controller.perform(action, on: target) { [self] result in
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            switch result {
            case .failure(let error):
                failures += 1
                print("FAIL \(action.title): \(error.localizedDescription) [\(error)]")
                next(on: target)
            case .success:
                if let window = enhancedFixture, (try? window.enhancedUI(timeout: 0.25)) != true {
                    failures += 1
                    print("FAIL \(action.title): Enhanced UI mode not restored")
                }
                poll(
                    readFrame, within: 1, until: { Self.matches($0, expected) },
                    then: { [self] frame in
                        let actual = frame ?? .zero
                        let matches = Self.matches(frame, expected)
                        if !matches { failures += 1 }
                        print(
                            "\(matches ? "PASS" : "FAIL") \(action.title): actual=\(actual), expected=\(expected), command=\(Int(elapsed)) ms"
                        )
                        next(on: target)
                    })
            }
        }
    }

    private static func matches(_ actual: CGRect?, _ expected: CGRect) -> Bool {
        guard let actual else { return false }
        return abs(actual.minX - expected.minX) <= 2 && abs(actual.minY - expected.minY) <= 2
            && abs(actual.width - expected.width) <= 2 && abs(actual.height - expected.height) <= 2
    }

    private func checkMinimize(on target: WindowTarget) {
        controller.perform(.minimize, on: target) { [self] result in
            switch result {
            case .failure(let error):
                failures += 1
                print("FAIL Minimize: \(error)")
                finish()
            case .success:
                poll(
                    readMinimized, within: 1, until: { $0 },
                    then: { [self] minimized in
                        if !minimized { failures += 1 }
                        print("\(minimized ? "PASS" : "FAIL") Minimize: fixture miniaturized=\(minimized)")
                        minimumSizeFixture = true
                        startFixture()
                    })
            }
        }
    }

    private func checkMinimumSize(original: CGRect, visible: CGRect) {
        let target = controller.capture(ForeignProcess(child.processIdentifier))
        let started = ProcessInfo.processInfo.systemUptime
        controller.perform(.rightHalf, on: target) { [self] result in
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            switch result {
            case .failure(let error):
                failures += 1
                print("FAIL Minimum size: \(error)")
                finish()
            case .success(let outcome):
                let reachable = { (frame: CGRect) in
                    frame.minX >= visible.minX - 3 && frame.maxX <= visible.maxX + 3
                        && frame.minY >= visible.minY - 3 && frame.maxY <= visible.maxY + 3
                }
                let settled = { (frame: CGRect?) in
                    frame.map {
                        $0.width >= visible.width * 0.75 - 3 && abs($0.maxX - visible.maxX) <= 3
                            && reachable($0)
                    } ?? false
                }
                poll(readFrame, within: 1, until: settled) { [self] frame in
                    let actual = frame ?? .zero
                    let matches =
                        outcome == .sizeLimited && settled(frame)
                        && elapsed < Self.minimumSizeCommandLimit
                    if !matches { failures += 1 }
                    print(
                        "\(matches ? "PASS" : "FAIL") Minimum size: actual=\(actual), original=\(original), reachable=\(reachable(actual)), command=\(Int(elapsed * 1000)) ms, outcome=\(outcome)"
                    )
                    if child.isRunning { child.terminate() }
                    checkSpotlightGuide { [self] in finish() }
                }
            }
        }
    }

    private func checkSpotlightGuide(then body: @escaping () -> Void) {
        let suite = "ciel.checks.window-spotlight"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let spotlight = SpotlightState()
        let hotKeys = HotKeys(
            defaults: defaults, registrar: AcceptingRegistrar(), onPress: { _ in }, onChange: {})
        let guide = SpotlightGuide(
            hotKeys: hotKeys, spotlight: SpotlightShortcuts { spotlight.symbolicHotKeys },
            open: { _ = NSWorkspace.shared.open($0) })
        launchedSettings =
            NSRunningApplication.runningApplications(
                withBundleIdentifier: SettingsCompanion.systemSettings
            ).isEmpty
        let done = { [self] (passed: Bool, detail: String) in
            if !passed { failures += 1 }
            print("\(passed ? "PASS" : "FAIL") Spotlight guide: \(detail)")
            guide.dismiss()
            defaults.removePersistentDomain(forName: suite)
            body()
        }
        NSApp.activate(ignoringOtherApps: true)
        guide.choose(SpotlightShortcuts.commandSpace)
        poll(
            { Self.cardPlacement(guide.companion) }, within: 10, until: { $0?.placed == true },
            then: { [self] placement in
                guard let placement, placement.placed else {
                    return done(
                        false,
                        "card not on screen under System Settings, frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"), window=\(placement.map { "\($0.window)" } ?? "none"), card=\(guide.companion.panel.frame), visible=\(guide.companion.panel.isVisible)"
                    )
                }
                let action = "Show Spotlight search"
                poll(
                    { Self.settingsShows(action) }, within: 5, until: { $0 },
                    then: { [self] found in
                        let version = ProcessInfo.processInfo.operatingSystemVersion
                        let english = Locale.preferredLanguages.first?.hasPrefix("en") == true
                        let os = "macOS \(version.majorVersion).\(version.minorVersion)"
                        if version.majorVersion >= 27, english, !found {
                            return done(false, "the ?Spotlight anchor did not show \(action) on \(os)")
                        }
                        print("INFO Spotlight anchor on \(os): \(action) \(found ? "found" : "not found")")
                        if found,
                            SettingsCompanion.settingsWindow(front: true)
                                == SettingsCompanion.settingsWindow()
                        {
                            return done(
                                false, "\(action) is showing, but no sheet is the front window to follow")
                        }
                        spotlight.symbolicHotKeys = ["64": ["enabled": false]]
                        guide.tick()
                        guard hotKeys.shortcut(for: .launcher) == SpotlightShortcuts.commandSpace,
                            guide.shownCard == .freed(shortcut: SpotlightShortcuts.commandSpace.display)
                        else {
                            return done(
                                false,
                                "after Spotlight let go, launcher=\(hotKeys.shortcut(for: .launcher)?.display ?? "none"), card=\(String(describing: guide.shownCard))"
                            )
                        }
                        poll(
                            { guide.shownCard == nil && !guide.companion.panel.isVisible }, within: 4,
                            until: { $0 },
                            then: { closed in
                                done(
                                    closed,
                                    "card at \(placement.window.debugDescription) placement, freed then \(closed ? "closed" : "still open") after the hold"
                                )
                            })
                    })
            })
    }

    private static func cardPlacement(_ companion: SettingsCompanion) -> (window: CGRect, placed: Bool)? {
        guard let window = SettingsCompanion.settingsWindow(front: true), let frame = companion.placement()
        else { return nil }
        let panel = companion.panel
        let windows =
            CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let onScreen = windows.contains { $0[kCGWindowNumber as String] as? Int == panel.windowNumber }
        return (window, onScreen && panel.frame == frame)
    }

    private static func settingsShows(_ name: String) -> Bool {
        guard
            let pid = NSRunningApplication.runningApplications(
                withBundleIdentifier: SettingsCompanion.systemSettings
            ).first?.processIdentifier
        else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var queue = [app]
        var index = 0
        while index < queue.count, index < 6000, ProcessInfo.processInfo.systemUptime < deadline {
            let element = queue[index]
            index += 1
            for attribute in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                    value as? String == name
                {
                    return true
                }
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
                == .success,
                let list = children as? [AXUIElement]
            {
                queue += list
            }
        }
        return false
    }

    private func finish(timeout: Bool = false) {
        if child.isRunning { child.terminate() }
        if launchedSettings {
            for app in NSRunningApplication.runningApplications(
                withBundleIdentifier: SettingsCompanion.systemSettings)
            { app.terminate() }
        }
        if timeout {
            failures += 1
            print("FAIL fixture timed out")
        }
        try? FileManager.default.removeItem(at: directory)
        print("Window integration: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}

@MainActor private final class SpotlightState {
    var symbolicHotKeys: [String: Any]?
}

@MainActor private final class SilentRecorder: AudioRecorder {
    func start() throws {}
    func recorded(from start: Int) -> AudioClip { AudioClip(samples: []) }
    func stop() -> AudioClip { AudioClip(samples: []) }
}

@MainActor final class WindowFixture: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private let output: URL
    private let minimumSize: Bool
    private var parentExit: (any DispatchSourceProcess)?

    init(output: String, minimumSize: Bool) {
        self.output = URL(fileURLWithPath: output).appendingPathComponent("frame.json")
        self.minimumSize = minimumSize
    }

    func run() {
        exitWithParent()
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(
            contentRect: NSRect(x: 180, y: 180, width: 700, height: 470),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Ciel temporary window test"
        if minimumSize, let screen = NSScreen.screens.first {
            window.contentMinSize = CGSize(width: screen.visibleFrame.width * 0.75, height: 200)
            window.setContentSize(CGSize(width: screen.visibleFrame.width * 0.85, height: 470))
            window.setFrameOrigin(
                CGPoint(x: screen.visibleFrame.minX + 30, y: screen.visibleFrame.minY + 100))
            window.title = "Ciel temporary minimum-size test"
        }
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.saveFrame() }
    }

    private func exitWithParent() {
        let parent = getppid()
        let launchd: pid_t = 1
        if parent == launchd { exit(0) }
        let source = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .main)
        source.setEventHandler { exit(0) }
        source.resume()
        parentExit = source
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidMiniaturize(_ notification: Notification) {
        if let data = try? JSONEncoder().encode(window.isMiniaturized) {
            try? data.write(
                to: output.deletingLastPathComponent().appendingPathComponent("minimized.json"),
                options: .atomic)
        }
    }
    private func saveFrame() {
        guard let window, window.isVisible else { return }
        let frame = WindowGeometry.accessibilityRect(
            window.frame, primaryHeight: NSScreen.screens.first!.frame.height)
        if let data = try? JSONEncoder().encode(frame) { try? data.write(to: output, options: .atomic) }
    }
}
