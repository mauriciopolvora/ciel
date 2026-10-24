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
    private var enhancedFixture: (any WindowAccess)?
    private var minimumSizeFixture = false
    private var fixtureDirectory: URL {
        minimumSizeFixture ? directory.appendingPathComponent("minimum") : directory
    }

    func run() {
        guard WindowController.isTrusted else {
            print("SKIP: the test process has no Accessibility access")
            exit(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.finish(timeout: true) }
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
        next(on: controller.capture(ForeignProcess(child.processIdentifier)))
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
                    finish()
                }
            }
        }
    }

    private func finish(timeout: Bool = false) {
        if child.isRunning { child.terminate() }
        if timeout {
            failures += 1
            print("FAIL fixture timed out")
        }
        try? FileManager.default.removeItem(at: directory)
        print("Window integration: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
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
