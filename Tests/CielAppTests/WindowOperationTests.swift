import ApplicationServices
import CielCore
import Foundation
import Testing

@testable import CielApp

@Suite("Window operations")
struct WindowOperationTests {
    private let screen = CGRect(x: 0, y: 30, width: 1200, height: 800)
    private let original = CGRect(x: 150, y: 160, width: 800, height: 500)

    private var displays: [DisplaySnapshot] { [DisplaySnapshot(full: screen, visible: screen)] }

    @Test("The normal path writes size-position-size without waiting")
    func immediateSequence() throws {
        let fixture = fixture()
        let expected = WindowAction.leftHalf.frame(in: screen, current: original)
        let message = try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        #expect(message == WindowAction.leftHalf.title)
        #expect(fixture.window.currentFrame == expected)
        #expect(
            fixture.window.writes == [.size(expected.size), .position(expected.origin), .size(expected.size)])
        #expect(fixture.clock.now == 0)
    }

    @Test("The second size write repairs clamping at the old position")
    func repairsOldPositionClamp() throws {
        let fixture = fixture()
        fixture.window.currentFrame = CGRect(x: 1100, y: 160, width: 80, height: 300)
        fixture.window.sizeHandler = { size in
            fixture.window.currentFrame.size = CGSize(
                width: min(size.width, max(80, self.screen.maxX - fixture.window.currentFrame.minX)),
                height: size.height)
        }
        let expected = WindowAction.leftHalf.frame(in: screen, current: fixture.window.currentFrame)
        _ = try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        #expect(fixture.window.currentFrame == expected)
        #expect(fixture.clock.now == 0)
    }

    @Test("A changed, repeated minimum-size response settles before the full deadline")
    func minimumSizeAndBounds() throws {
        let fixture = fixture()
        fixture.window.sizeHandler = { size in
            fixture.window.currentFrame.size = CGSize(width: max(size.width, 900), height: size.height)
        }
        let message = try fixture.engine.perform(.rightHalf, selection: fixture.selection, displays: displays)
        #expect(message == "The app limited the window size.")
        #expect(fixture.clock.now >= 0.24)
        #expect(fixture.clock.now < 0.35)
        #expect(fixture.window.currentFrame == CGRect(x: 300, y: 30, width: 900, height: 800))
        #expect(screen.contains(fixture.window.currentFrame))
        let restored = try fixture.engine.perform(.restore, selection: fixture.selection, displays: displays)
        #expect(restored == "The app limited the window size.")
    }

    @Test("An already-minimum-size window reserves time for a visibility correction")
    func unchangedMinimumSizeRemainsVisible() throws {
        let fixture = fixture()
        fixture.window.currentFrame = CGRect(x: 0, y: 30, width: 900, height: 800)
        fixture.window.sizeHandler = { _ in }
        let message = try fixture.engine.perform(.rightHalf, selection: fixture.selection, displays: displays)
        #expect(message == "The app limited the window size.")
        #expect(fixture.clock.now >= 0.44)
        #expect(fixture.clock.now <= 0.5)
        #expect(fixture.window.currentFrame == CGRect(x: 300, y: 30, width: 900, height: 800))
        #expect(screen.contains(fixture.window.currentFrame))
    }

    @Test("An unchanged size can be a delayed response, not a minimum size")
    func delayedSize() throws {
        let fixture = fixture()
        var requestedSize: CGSize?
        fixture.window.sizeHandler = { requestedSize = $0 }
        fixture.window.readHandler = {
            if fixture.clock.now >= 0.35, let requestedSize {
                fixture.window.currentFrame.size = requestedSize
            }
        }
        let message = try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        #expect(message == WindowAction.leftHalf.title)
        #expect(fixture.clock.now >= 0.35)
        #expect(fixture.clock.now <= 0.5)
    }

    @Test("Changing animation frames are polled until they reach the target")
    func delayedAnimatedSize() throws {
        let fixture = fixture()
        var requestedSize = original.size
        fixture.window.sizeHandler = { requestedSize = $0 }
        fixture.window.readHandler = {
            let progress = min(1, floor(fixture.clock.now / 0.04) * 0.04 / 0.4)
            fixture.window.currentFrame.size = CGSize(
                width: self.original.width + (requestedSize.width - self.original.width) * progress,
                height: self.original.height + (requestedSize.height - self.original.height) * progress)
        }
        let message = try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        #expect(message == WindowAction.leftHalf.title)
        #expect(fixture.clock.now >= 0.4)
        #expect(fixture.clock.now <= 0.5)
    }

    @Test("Ignoring a change produces one timeout and no false restore history")
    func ignoredWrite() throws {
        let fixture = fixture()
        fixture.window.sizeHandler = { _ in }
        fixture.window.positionHandler = { _ in }
        #expect(throws: WindowError.timedOut) {
            try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        }
        #expect(fixture.clock.now == 0.5)
        #expect(throws: WindowError.noHistory) {
            try fixture.engine.perform(.restore, selection: fixture.selection, displays: displays)
        }
        #expect(fixture.clock.now == 0.5)
    }

    @Test("Rejected writes retain their error and restore Enhanced UI")
    func rejectedWriteRestoresEnhancedUI() throws {
        let fixture = fixture()
        fixture.window.enhanced = true
        fixture.window.sizeHandler = { _ in throw WindowError.rejected(AXError.cannotComplete.rawValue) }
        #expect(throws: WindowError.rejected(AXError.cannotComplete.rawValue)) {
            try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        }
        #expect(fixture.window.enhanced == true)
        #expect(fixture.window.writes.first == .enhancedUI(false))
        #expect(fixture.window.writes.last == .enhancedUI(true))
    }

    @Test("Successful commands restore Enhanced UI; unsupported mode is optional")
    func enhancedUIOnSuccess() throws {
        let fixture = fixture()
        fixture.window.enhanced = true
        _ = try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        #expect(fixture.window.enhanced == true)
        #expect(fixture.window.writes.first == .enhancedUI(false))
        #expect(fixture.window.writes.last == .enhancedUI(true))

        fixture.window.writes.removeAll()
        fixture.window.enhanced = nil
        _ = try fixture.engine.perform(.rightHalf, selection: fixture.selection, displays: displays)
        #expect(!fixture.window.writes.contains(.enhancedUI(false)))
        #expect(!fixture.window.writes.contains(.enhancedUI(true)))
    }

    @Test("Timeout errors also restore Enhanced UI")
    func timeoutRestoresEnhancedUI() throws {
        let fixture = fixture()
        fixture.window.enhanced = true
        fixture.window.sizeHandler = { _ in }
        fixture.window.positionHandler = { _ in }
        #expect(throws: WindowError.timedOut) {
            try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        }
        #expect(fixture.window.enhanced == true)
        #expect(fixture.window.writes.last == .enhancedUI(true))
    }

    @Test("Permission and full-screen errors perform no writes")
    func preconditions() throws {
        let fixture = fixture()
        fixture.accessibility.isTrusted = false
        #expect(throws: WindowError.permission) {
            try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        }
        fixture.accessibility.isTrusted = true
        fixture.window.fullScreen = true
        #expect(throws: WindowError.fullScreen) {
            try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        }
        #expect(fixture.window.writes.isEmpty)
    }

    @Test("A nonresizable window can center, but cannot snap to a new size")
    func unsupportedResize() throws {
        let fixture = fixture()
        fixture.window.resizable = false
        #expect(throws: WindowError.unsupported) {
            try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        }
        #expect(fixture.window.writes.isEmpty)
        #expect(
            try fixture.engine.perform(.center, selection: fixture.selection, displays: displays) == "Center")
        #expect(fixture.window.currentFrame.size == original.size)
    }

    @Test("Capture selections remain pinned when a later capture changes the focused window")
    func capturePinning() throws {
        let fixture = fixture()
        let another = FakeWindow(frame: CGRect(x: 300, y: 300, width: 400, height: 300))
        fixture.accessibility.window = another
        let later = fixture.engine.capture(pid: 42)
        _ = try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        #expect(another.writes.isEmpty)
        #expect(fixture.window.currentFrame == WindowAction.leftHalf.frame(in: screen, current: original))
        _ = try fixture.engine.perform(.rightHalf, selection: later, displays: displays)
        #expect(
            another.currentFrame == WindowAction.rightHalf.frame(in: screen, current: another.currentFrame))
    }

    @Test("Cross-display commands and restore keep their geometry")
    func crossDisplayAndRestore() throws {
        let fixture = fixture()
        let other = CGRect(x: -1600, y: -1000, width: 1600, height: 1000)
        let both = displays + [DisplaySnapshot(full: other, visible: other)]
        let expected = WindowGeometry.move(original, from: screen, to: other)
        #expect(
            try fixture.engine.perform(.nextDisplay, selection: fixture.selection, displays: both)
                == "Move to Next Display")
        #expect(fixture.window.currentFrame == expected)
        #expect(
            try fixture.engine.perform(.restore, selection: fixture.selection, displays: both)
                == "Restore Previous Size")
        #expect(fixture.window.currentFrame == original)
        #expect(fixture.clock.now == 0)
    }

    @Test("Disconnected-display restore keeps the old window reachable")
    func disconnectedDisplayRestore() throws {
        let fixture = fixture()
        let other = CGRect(x: -1600, y: -1000, width: 1600, height: 1000)
        let both = displays + [DisplaySnapshot(full: other, visible: other)]
        _ = try fixture.engine.perform(.nextDisplay, selection: fixture.selection, displays: both)
        _ = try fixture.engine.perform(.maximize, selection: fixture.selection, displays: both)
        _ = try fixture.engine.perform(.restore, selection: fixture.selection, displays: displays)
        #expect(screen.contains(fixture.window.currentFrame))
    }

    @Test("Single-display and missing-window errors remain explicit")
    func missingTargets() throws {
        let fixture = fixture()
        #expect(throws: WindowError.oneDisplay) {
            try fixture.engine.perform(.nextDisplay, selection: fixture.selection, displays: displays)
        }
        let missing = fixture.engine.capture(pid: nil)
        #expect(throws: WindowError.noWindow) {
            try fixture.engine.perform(.leftHalf, selection: missing, displays: displays)
        }
    }

    @Test("Minimize permits a delayed Dock response and has a single budget")
    func delayedMinimize() throws {
        let fixture = fixture()
        fixture.window.minimizeHandler = {}
        fixture.window.minimizedHandler = { fixture.clock.now >= 0.8 }
        #expect(
            try fixture.engine.perform(.minimize, selection: fixture.selection, displays: displays)
                == "Minimize")
        #expect(fixture.clock.now >= 0.8)
        #expect(fixture.clock.now <= 1)
    }

    @Test("Minimize retries transient Dock state-read failures within its total budget")
    func transientMinimizeReads() throws {
        let fixture = fixture()
        fixture.window.minimizeHandler = {}
        fixture.window.minimizedHandler = {
            if fixture.clock.now < 0.4 { throw WindowError.rejected(AXError.cannotComplete.rawValue) }
            return true
        }
        #expect(
            try fixture.engine.perform(.minimize, selection: fixture.selection, displays: displays)
                == "Minimize")
        #expect(fixture.clock.now >= 0.4)
        #expect(fixture.clock.now <= 1)
        #expect(fixture.window.writes == [.minimize])
    }

    @Test("Minimize does not retry permission failures as Dock delay")
    func permanentMinimizeReadFailure() throws {
        let fixture = fixture()
        fixture.window.minimizedHandler = { throw WindowError.permission }
        #expect(throws: WindowError.permission) {
            try fixture.engine.perform(.minimize, selection: fixture.selection, displays: displays)
        }
        #expect(fixture.clock.now == 0)
    }

    @Test("IPC calls and fallback attempts share the frame deadline")
    func callsShareBudget() throws {
        let fixture = fixture()
        fixture.window.beforeCall = { timeout in
            #expect(timeout > 0 && timeout <= 0.25)
            // Simulate a responsive but slow app. Setup and writes consume the
            // same budget as frame verification, instead of starting a new wait.
            fixture.clock.now += min(0.08, timeout)
        }
        #expect(throws: WindowError.timedOut) {
            try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        }
        #expect(fixture.clock.now <= 0.5)
    }

    @Test("Accepted size changes retain an explicit position-limit message")
    func limitedPosition() throws {
        let fixture = fixture()
        fixture.window.positionHandler = { point in
            fixture.window.currentFrame.origin = CGPoint(x: max(100, point.x), y: point.y)
        }
        let message = try fixture.engine.perform(.leftHalf, selection: fixture.selection, displays: displays)
        #expect(message == "The app limited the window position.")
        #expect(fixture.clock.now == 0.5)
    }

    private func fixture() -> Fixture {
        let clock = FakeWindowClock()
        let window = FakeWindow(frame: original)
        let accessibility = FakeWindowAccessibility(window: window)
        let engine = WindowOperationEngine(accessibility: accessibility, clock: clock)
        return Fixture(
            clock: clock, window: window, accessibility: accessibility, engine: engine,
            selection: engine.capture(pid: 42))
    }

    private struct Fixture {
        let clock: FakeWindowClock
        let window: FakeWindow
        let accessibility: FakeWindowAccessibility
        let engine: WindowOperationEngine
        let selection: WindowSelection
    }
}

private final class FakeWindowClock: WindowOperationClock {
    var now: TimeInterval = 0
    func sleep(for interval: TimeInterval) { now += interval }
}

private final class FakeWindowAccessibility: WindowAccessibility {
    var isTrusted = true
    var window: (any WindowAccess)?
    init(window: any WindowAccess) { self.window = window }
    func focusedWindow(pid: pid_t) -> (any WindowAccess)? { window }
}

private final class FakeWindow: WindowAccess {
    enum Write: Equatable {
        case size(CGSize)
        case position(CGPoint)
        case enhancedUI(Bool)
        case minimize
    }
    var currentFrame: CGRect
    var writes: [Write] = []
    var fullScreen = false
    var resizable = true
    var movable = true
    var minimized = false
    var enhanced: Bool?
    var sizeHandler: ((CGSize) throws -> Void)?
    var positionHandler: ((CGPoint) throws -> Void)?
    var readHandler: (() throws -> Void)?
    var minimizeHandler: (() throws -> Void)?
    var minimizedHandler: (() throws -> Bool)?
    var beforeCall: ((TimeInterval) -> Void)?

    init(frame: CGRect) { currentFrame = frame }
    func isSameWindow(as other: any WindowAccess) -> Bool { self === other }
    func frame(timeout: TimeInterval) throws -> CGRect {
        beforeCall?(timeout)
        try readHandler?()
        return currentFrame
    }
    func isFullScreen(timeout: TimeInterval) throws -> Bool {
        beforeCall?(timeout)
        return fullScreen
    }
    func isSettable(_ attribute: WindowAttribute, timeout: TimeInterval) throws -> Bool {
        beforeCall?(timeout)
        switch attribute {
        case .position: return movable
        case .size: return resizable
        case .minimized: return true
        }
    }
    func setSize(_ size: CGSize, timeout: TimeInterval) throws {
        beforeCall?(timeout)
        writes.append(.size(size))
        if let sizeHandler { try sizeHandler(size) } else { currentFrame.size = size }
    }
    func setPosition(_ point: CGPoint, timeout: TimeInterval) throws {
        beforeCall?(timeout)
        writes.append(.position(point))
        if let positionHandler { try positionHandler(point) } else { currentFrame.origin = point }
    }
    func isMinimized(timeout: TimeInterval) throws -> Bool {
        beforeCall?(timeout)
        return try minimizedHandler?() ?? minimized
    }
    func minimize(timeout: TimeInterval) throws {
        beforeCall?(timeout)
        writes.append(.minimize)
        if let minimizeHandler { try minimizeHandler() } else { minimized = true }
    }
    func enhancedUI(timeout: TimeInterval) throws -> Bool? {
        beforeCall?(timeout)
        return enhanced
    }
    func setEnhancedUI(_ enabled: Bool, timeout: TimeInterval) throws {
        beforeCall?(timeout)
        writes.append(.enhancedUI(enabled))
        enhanced = enabled
    }
}
