import CielCore
import Foundation

final class WindowSelection: Hashable, Sendable {
    fileprivate let id = UUID()
    private let onRelease: (@Sendable (UUID) -> Void)?

    init(onRelease: (@Sendable (UUID) -> Void)? = nil) { self.onRelease = onRelease }
    deinit { onRelease?(id) }
    static func == (lhs: WindowSelection, rhs: WindowSelection) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

protocol WindowOperationClock {
    var now: TimeInterval { get }
    func sleep(for interval: TimeInterval)
}

private struct SystemWindowClock: WindowOperationClock {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    func sleep(for interval: TimeInterval) { Thread.sleep(forTimeInterval: interval) }
}

final class WindowOperationEngine {
    private struct Capture {
        let selectionID: UUID
        let pid: pid_t?
        var window: (any WindowAccess)?
    }

    private let accessibility: any WindowAccessibility
    private let clock: any WindowOperationClock
    private var captures: [Capture] = []
    private var history: [(window: any WindowAccess, frame: CGRect)] = []
    private static let frameBudget: TimeInterval = 0.5
    private static let minimizeBudget: TimeInterval = 1
    private static let callTimeout: TimeInterval = 0.25
    private static let pollInterval: TimeInterval = 0.01
    private static let enhancedUIRestoreTimeout: TimeInterval = 0.05

    init(accessibility: any WindowAccessibility, clock: (any WindowOperationClock)? = nil) {
        self.accessibility = accessibility
        self.clock = clock ?? SystemWindowClock()
    }

    func capture(pid: pid_t?, onRelease: (@Sendable (UUID) -> Void)? = nil) -> WindowSelection {
        let selection = WindowSelection(onRelease: onRelease)
        // AX calls into our own AppKit views can deadlock AppKit.
        let validPID = pid.flatMap {
            $0 != ProcessInfo.processInfo.processIdentifier && accessibility.isTrusted ? $0 : nil
        }
        captures.append(
            Capture(
                selectionID: selection.id, pid: validPID,
                window: validPID.flatMap { accessibility.focusedWindow(pid: $0) }))
        return selection
    }

    func releaseCapture(_ id: UUID) { captures.removeAll { $0.selectionID == id } }

    func perform(
        _ action: WindowAction, selection: WindowSelection, displays: [DisplaySnapshot]
    ) throws -> String {
        guard accessibility.isTrusted else { throw WindowError.permission }
        guard let captureIndex = captures.firstIndex(where: { $0.selectionID == selection.id }) else {
            throw WindowError.noWindow
        }
        if captures[captureIndex].window == nil, let pid = captures[captureIndex].pid {
            captures[captureIndex].window = accessibility.focusedWindow(pid: pid)
        }
        guard let window = captures[captureIndex].window else { throw WindowError.noWindow }
        let budget = Budget(
            clock: clock, duration: action == .minimize ? Self.minimizeBudget : Self.frameBudget)
        if try window.isFullScreen(timeout: budget.timeout()) { throw WindowError.fullScreen }
        if action == .minimize { return try minimize(window, action: action, budget: budget) }

        let original = try window.frame(timeout: budget.timeout())
        guard let index = WindowGeometry.displayIndex(for: original, displays: displays.map(\.full)) else {
            throw WindowError.noWindow
        }
        let source = displays[index].visible
        var targetVisible = source
        let desired: CGRect
        if action == .restore {
            guard let saved = history.last(where: { $0.window.isSameWindow(as: window) }) else {
                throw WindowError.noHistory
            }
            var restored = saved.frame
            if !displays.contains(where: { $0.visible.intersects(restored) }) {
                restored = WindowAction.center.frame(in: source, current: restored)
            }
            desired = restored
            if let destination = WindowGeometry.displayIndex(for: desired, displays: displays.map(\.full)) {
                targetVisible = displays[destination].visible
            }
        } else if action == .nextDisplay || action == .previousDisplay {
            guard displays.count > 1 else { throw WindowError.oneDisplay }
            let offset = action == .nextDisplay ? 1 : displays.count - 1
            targetVisible = displays[(index + offset) % displays.count].visible
            desired = WindowGeometry.move(original, from: source, to: targetVisible)
        } else {
            desired = action.frame(in: source, current: original)
        }

        guard try window.isSettable(.position, timeout: budget.timeout()) else {
            throw WindowError.unsupported
        }
        let canResize = try window.isSettable(.size, timeout: budget.timeout())
        if !canResize && desired.size != original.size { throw WindowError.unsupported }

        let actual = try withEnhancedUserInterfaceDisabled(window, budget: budget) {
            try update(
                window, from: original, to: desired, canResize: canResize,
                crossesDisplay: targetVisible != source, budget: budget)
            let settled = try waitForFrame(
                window, original: original, desired: desired, canResize: canResize,
                visible: targetVisible, budget: budget)
            return try keepReachable(window, settled, in: targetVisible, budget: budget)
        }

        history.removeAll { $0.window.isSameWindow(as: window) }
        history.append((window, original))
        if history.count > 24 { history.removeFirst() }
        if !FrameSettle.matches(actual.size, desired.size) { return "The app limited the window size." }
        if !FrameSettle.matches(actual.origin, desired.origin) {
            return "The app limited the window position."
        }
        return action.title
    }

    private func withEnhancedUserInterfaceDisabled<T>(
        _ window: any WindowAccess, budget: Budget, _ body: () throws -> T
    ) rethrows -> T {
        let disabled =
            (try? window.enhancedUI(timeout: budget.timeout())) == true
            && (try? window.setEnhancedUI(false, timeout: budget.timeout())) != nil
        defer {
            if disabled { try? window.setEnhancedUI(true, timeout: Self.enhancedUIRestoreTimeout) }
        }
        return try body()
    }

    private func keepReachable(
        _ window: any WindowAccess, _ frame: CGRect, in visible: CGRect, budget: Budget
    ) throws -> CGRect {
        let reachable = FrameSettle.reachableOrigin(frame, in: visible)
        if FrameSettle.matches(frame.origin, reachable) { return frame }
        try window.setPosition(reachable, timeout: budget.timeout())
        return try waitForFrame(
            window, original: frame, desired: CGRect(origin: reachable, size: frame.size), canResize: false,
            budget: budget)
    }

    private func minimize(_ window: any WindowAccess, action: WindowAction, budget: Budget) throws -> String {
        guard try window.isSettable(.minimized, timeout: budget.timeout()) else {
            throw WindowError.unsupported
        }
        try window.minimize(timeout: budget.timeout())
        while try !dockFinishedMinimizing(window, budget: budget) {
            try budget.pause(Self.pollInterval)
        }
        return action.title
    }

    private func dockFinishedMinimizing(_ window: any WindowAccess, budget: Budget) throws -> Bool {
        do {
            return try window.isMinimized(timeout: budget.timeout())
        } catch let error as WindowError where error.isTemporaryMessagingFailure {
            return false
        }
    }

    private func update(
        _ window: any WindowAccess, from current: CGRect, to desired: CGRect,
        canResize: Bool, crossesDisplay: Bool = false, budget: Budget
    ) throws {
        if canResize && current.size != desired.size {
            try window.setSize(desired.size, timeout: budget.timeout())
        }
        if current.origin != desired.origin {
            try window.setPosition(desired.origin, timeout: budget.timeout())
        }
        // The second size write repairs apps that clamp their first resize
        // against the previous position.
        if canResize && (current.size != desired.size || crossesDisplay) {
            try window.setSize(desired.size, timeout: budget.timeout())
        }
    }

    private func waitForFrame(
        _ window: any WindowAccess, original: CGRect, desired: CGRect,
        canResize: Bool, visible: CGRect? = nil, budget: Budget
    ) throws -> CGRect {
        let first = try window.frame(timeout: budget.timeout())
        var settle = FrameSettle(
            original: original, desired: desired, visible: visible, first: first, at: clock.now)
        while true {
            switch settle.decide(now: clock.now, remaining: budget.remaining) {
            case .matched, .constrained, .yieldForVisibilityCorrection:
                return settle.last
            case .retry:
                try update(window, from: settle.last, to: desired, canResize: canResize, budget: budget)
                let retried = try window.frame(timeout: budget.timeout())
                settle.retried(retried, at: clock.now)
            case .keepPolling:
                break
            }
            do {
                try budget.pause(Self.pollInterval)
                let observed = try window.frame(timeout: budget.timeout())
                settle.observe(observed, at: clock.now)
            } catch WindowError.timedOut {
                if settle.isUnchanged { throw WindowError.timedOut }
                return settle.last
            }
        }
    }

    private struct Budget {
        let clock: any WindowOperationClock
        let deadline: TimeInterval

        init(clock: any WindowOperationClock, duration: TimeInterval) {
            self.clock = clock
            deadline = clock.now + duration
        }
        var remaining: TimeInterval { max(0, deadline - clock.now) }
        func timeout() throws -> TimeInterval {
            let remaining = self.remaining
            guard remaining > 0 else { throw WindowError.timedOut }
            return min(WindowOperationEngine.callTimeout, remaining)
        }
        func pause(_ interval: TimeInterval) throws {
            let remaining = deadline - clock.now
            guard remaining > 0 else { throw WindowError.timedOut }
            clock.sleep(for: min(interval, remaining))
        }
    }
}
