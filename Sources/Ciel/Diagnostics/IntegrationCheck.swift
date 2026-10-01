import AppKit
import ApplicationServices
import CielCore

/// Explicit test mode. The fixture is a separate process, as real target apps are.
@MainActor final class IntegrationCheck {
    private let controller = WindowController()
    private var child = Process()
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ciel-check-" + UUID().uuidString)
    private var steps: [(WindowAction, CGRect)] = []
    private var failures = 0
    private var attempts = 0
    private var enhancedFixture: AXUIElement?
    private var minimumSizeFixture = false
    private var fixtureDirectory: URL {
        minimumSizeFixture ? directory.appendingPathComponent("minimum") : directory
    }

    func run() {
        guard WindowController.isTrusted else {
            print("SKIP: the test process has no Accessibility access")
            exit(2)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            child.executableURL = Bundle.main.executableURL!
            child.arguments = ["--window-fixture", directory.path]
            try child.run()
        } catch {
            print("FAIL fixture: \(error)")
            exit(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.finish(timeout: true) }
        waitForFixture()
    }

    private func readFrame() -> CGRect? {
        guard let data = try? Data(contentsOf: fixtureDirectory.appendingPathComponent("frame.json")),
            let frame = try? JSONDecoder().decode(CGRect.self, from: data)
        else { return nil }
        return frame
    }
    private func waitForFixture() {
        guard let original = readFrame() else {
            attempts += 1
            if attempts > 30 {
                finish(timeout: true)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.waitForFixture() }
            return
        }
        let displays = DisplaySnapshot.current()
        guard let index = WindowGeometry.displayIndex(for: original, displays: displays.map(\.full)) else {
            finish(timeout: true)
            return
        }
        let visible = displays[index].visible
        if minimumSizeFixture {
            checkMinimumSize(original: original, visible: visible)
            return
        }
        let left = WindowAction.leftHalf.frame(in: visible, current: original)
        let right = WindowAction.rightHalf.frame(in: visible, current: left)
        let thirds = WindowAction.centerTwoThirds.frame(in: visible, current: right)
        let maximized = WindowAction.maximize.frame(in: visible, current: right)
        steps = [
            (.leftHalf, left), (.rightHalf, right), (.maximize, maximized),
            (.leftHalf, left), (.restore, maximized), (.rightHalf, right),
            (.centerTwoThirds, thirds), (.restore, right),
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
        // Exercise the app's animated AX mode and verify that window commands
        // restore it. This changes only the temporary fixture process.
        let app = AXUIElementCreateApplication(child.processIdentifier)
        if AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            == .success
        {
            enhancedFixture = app
        } else {
            print("SKIP fixture Enhanced UI mode: unsupported")
        }
        controller.capture(pid: child.processIdentifier)
        next()
    }
    private func next() {
        guard !steps.isEmpty else {
            checkMinimize()
            return
        }
        let (action, expected) = steps.removeFirst()
        let started = ProcessInfo.processInfo.systemUptime
        controller.perform(action, displays: DisplaySnapshot.current()) { [self] result in
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            switch result {
            case .failure(let error):
                failures += 1
                print("FAIL \(action.title): \(error.localizedDescription) [\(error)]")
                next()
            case .success:
                if let app = enhancedFixture {
                    var enabled: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(
                        app, "AXEnhancedUserInterface" as CFString, &enabled)
                    if result != .success || enabled as? Bool != true {
                        failures += 1
                        print("FAIL \(action.title): Enhanced UI mode not restored")
                    }
                }
                // The fixture writes its AppKit frame on move/resize notifications.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let actual = self.readFrame() ?? .zero
                    let matches =
                        abs(actual.minX - expected.minX) <= 2 && abs(actual.minY - expected.minY) <= 2
                        && abs(actual.width - expected.width) <= 2
                        && abs(actual.height - expected.height) <= 2
                    if !matches { self.failures += 1 }
                    print(
                        "\(matches ? "PASS" : "FAIL") \(action.title): actual=\(actual), expected=\(expected), command=\(Int(elapsed)) ms"
                    )
                    self.next()
                }
            }
        }
    }
    private func checkMinimize() {
        controller.perform(.minimize, displays: DisplaySnapshot.current()) { [self] result in
            switch result {
            case .failure(let error):
                failures += 1
                print("FAIL Minimize: \(error)")
                finish()
            case .success:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    let data = try? Data(contentsOf: self.directory.appendingPathComponent("minimized.json"))
                    let minimized = data.flatMap { try? JSONDecoder().decode(Bool.self, from: $0) } ?? false
                    if !minimized { self.failures += 1 }
                    print("\(minimized ? "PASS" : "FAIL") Minimize: fixture miniaturized=\(minimized)")
                    self.startMinimumSizeFixture()
                }
            }
        }
    }
    private func startMinimumSizeFixture() {
        if child.isRunning { child.terminate() }
        enhancedFixture = nil
        minimumSizeFixture = true
        attempts = 0
        child = Process()
        child.executableURL = Bundle.main.executableURL!
        child.arguments = ["--window-fixture", fixtureDirectory.path, "--window-fixture-minimum"]
        do {
            try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
            try child.run()
            waitForFixture()
        } catch {
            failures += 1
            print("FAIL minimum-size fixture: \(error)")
            finish()
        }
    }
    private func checkMinimumSize(original: CGRect, visible: CGRect) {
        controller.capture(pid: child.processIdentifier)
        let started = ProcessInfo.processInfo.systemUptime
        controller.perform(.rightHalf, displays: DisplaySnapshot.current()) { [self] result in
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            switch result {
            case .failure(let error):
                failures += 1
                print("FAIL Minimum size: \(error)")
                finish()
            case .success(let message):
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let actual = self.readFrame() ?? .zero
                    let expectedWidth = visible.width * 0.75
                    let reachable =
                        actual.minX >= visible.minX - 3
                        && actual.maxX <= visible.maxX + 3
                        && actual.minY >= visible.minY - 3
                        && actual.maxY <= visible.maxY + 3
                    // The frame polling budget is 500 ms. Allow native IPC and
                    // scheduling overhead, while detecting the former two waits.
                    let matches =
                        message == "The app limited the window size."
                        && actual.width >= expectedWidth - 3 && reachable && elapsed < 0.85
                    if !matches { self.failures += 1 }
                    print(
                        "\(matches ? "PASS" : "FAIL") Minimum size: actual=\(actual), original=\(original), reachable=\(reachable), command=\(Int(elapsed * 1000)) ms, message=\(message)"
                    )
                    self.finish()
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
    init(output: String) { self.output = URL(fileURLWithPath: output).appendingPathComponent("frame.json") }
    func run() {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(
            contentRect: NSRect(x: 180, y: 180, width: 700, height: 470),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Ciel temporary window test"
        if CommandLine.arguments.contains("--window-fixture-minimum"), let screen = NSScreen.screens.first {
            window.contentMinSize = CGSize(width: screen.visibleFrame.width * 0.75, height: 200)
            window.setContentSize(CGSize(width: screen.visibleFrame.width * 0.85, height: 470))
            window.setFrameOrigin(
                CGPoint(x: screen.visibleFrame.minX + 30, y: screen.visibleFrame.minY + 100))
            window.title = "Ciel temporary minimum-size test"
        }
        window.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "Testing window commands. This window closes automatically.")
        label.frame = NSRect(x: 30, y: 200, width: 620, height: 30)
        window.contentView?.addSubview(label)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.saveFrame() }
        // A failed parent must not leave a test window running.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { exit(0) }
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
