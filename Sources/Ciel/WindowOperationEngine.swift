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

/// Queue-owned state and geometry decisions. A fake window and clock can test
/// rejections, delayed frames, and size constraints without moving user windows.
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
    private let frameDuration: TimeInterval = 0.5
    private let pollInterval: TimeInterval = 0.01
    private let settleInterval: TimeInterval = 0.12

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
        let budget = Budget(clock: clock, duration: action == .minimize ? 1 : frameDuration)
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

        // This app-specific attribute is optional. Restore it after success and
        // every throwing path. Restoration has a separate short cleanup timeout.
        let restoreEnhancedUI: Bool
        if (try? window.enhancedUI(timeout: budget.timeout())) == true {
            restoreEnhancedUI = (try? window.setEnhancedUI(false, timeout: budget.timeout())) != nil
        } else {
            restoreEnhancedUI = false
        }
        defer {
            if restoreEnhancedUI { try? window.setEnhancedUI(true, timeout: 0.05) }
        }

        try update(
            window, from: original, to: desired, canResize: canResize,
            crossesDisplay: targetVisible != source, budget: budget)
        var actual = try waitForFrame(
            window, original: original, desired: desired, canResize: canResize,
            visible: targetVisible, budget: budget)

        // A minimum size can extend beyond the requested half. Keep the window
        // reachable, and verify the correction within the same operation budget.
        let bounded = Self.boundedOrigin(actual, in: targetVisible)
        if !Self.matches(actual.origin, bounded) {
            let beforeCorrection = actual
            try window.setPosition(bounded, timeout: budget.timeout())
            let corrected = CGRect(origin: bounded, size: actual.size)
            actual = try waitForFrame(
                window, original: beforeCorrection, desired: corrected, canResize: false, budget: budget)
        }

        history.removeAll { $0.window.isSameWindow(as: window) }
        history.append((window, original))
        if history.count > 24 { history.removeFirst() }
        if !Self.matches(actual.size, desired.size) { return "The app limited the window size." }
        if !Self.matches(actual.origin, desired.origin) { return "The app limited the window position." }
        return action.title
    }

    private func minimize(_ window: any WindowAccess, action: WindowAction, budget: Budget) throws -> String {
        guard try window.isSettable(.minimized, timeout: budget.timeout()) else {
            throw WindowError.unsupported
        }
        try window.minimize(timeout: budget.timeout())
        while true {
            do {
                if try window.isMinimized(timeout: budget.timeout()) { return action.title }
            } catch let error as WindowError where error.isTemporaryMessagingFailure {
                // The Dock animation can temporarily block the state read after
                // the setter succeeds. Confirm it within the same total budget.
            }
            try budget.pause(pollInterval)
        }
    }

    private func update(
        _ window: any WindowAccess, from current: CGRect, to desired: CGRect,
        canResize: Bool, crossesDisplay: Bool = false, budget: Budget
    ) throws {
        // Do not wait at an intermediate frame. The second size write repairs
        // apps that clamp their first resize against the previous position.
        if canResize && current.size != desired.size {
            try window.setSize(desired.size, timeout: budget.timeout())
        }
        if current.origin != desired.origin {
            try window.setPosition(desired.origin, timeout: budget.timeout())
        }
        if canResize && (current.size != desired.size || crossesDisplay) {
            try window.setSize(desired.size, timeout: budget.timeout())
        }
    }

    private func waitForFrame(
        _ window: any WindowAccess, original: CGRect, desired: CGRect,
        canResize: Bool, visible: CGRect? = nil, budget: Budget
    ) throws -> CGRect {
        var last = try window.frame(timeout: budget.timeout())
        var stableSince = clock.now
        var retried = false
        var retryFrame: CGRect?
        let started = clock.now
        while true {
            if Self.matches(last, desired) { return last }
            let stable = clock.now - stableSince >= settleInterval
            // An unchanged original size is not evidence of a minimum size:
            // some apps accept writes before applying them asynchronously.
            let changedSize = !Self.matches(last.size, original.size)
            let constrainedSize = changedSize && !Self.matches(last.size, desired.size)
            if retried, stable, let retryFrame, Self.matches(last, retryFrame), constrainedSize {
                return last
            }
            // Keep time for a final visibility correction. This is needed when
            // the existing size already equals an app's minimum: that size
            // cannot safely use the changed-size fast path above.
            if let visible, retried, stable, let retryFrame, Self.matches(last, retryFrame),
                !Self.matches(last.origin, Self.boundedOrigin(last, in: visible)),
                !Self.matches(last, original), budget.remaining <= 0.05
            {
                return last
            }
            // Retry a changed, stable frame sooner. Give an unchanged frame time
            // to respond, and share one deadline across both attempts.
            if !retried && stable && (constrainedSize || clock.now - started >= 0.2) {
                try update(window, from: last, to: desired, canResize: canResize, budget: budget)
                last = try window.frame(timeout: budget.timeout())
                retryFrame = last
                stableSince = clock.now
                retried = true
            }
            do {
                try budget.pause(pollInterval)
                let observed = try window.frame(timeout: budget.timeout())
                if !Self.matches(observed, last) { stableSince = clock.now }
                last = observed
            } catch WindowError.timedOut {
                // Do not record an accepted but unchanged write as a successful
                // constrained result. The app may still be processing it.
                if Self.matches(last, original) { throw WindowError.timedOut }
                return last
            }
        }
    }

    private static func matches(_ actual: CGRect, _ desired: CGRect) -> Bool {
        matches(actual.origin, desired.origin) && matches(actual.size, desired.size)
    }
    private static func matches(_ actual: CGPoint, _ desired: CGPoint) -> Bool {
        abs(actual.x - desired.x) <= 3 && abs(actual.y - desired.y) <= 3
    }
    private static func matches(_ actual: CGSize, _ desired: CGSize) -> Bool {
        abs(actual.width - desired.width) <= 3 && abs(actual.height - desired.height) <= 3
    }
    private static func boundedOrigin(_ frame: CGRect, in visible: CGRect) -> CGPoint {
        CGPoint(
            x: max(visible.minX, min(frame.minX, visible.maxX - frame.width)),
            y: max(visible.minY, min(frame.minY, visible.maxY - frame.height)))
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
            return min(0.25, remaining)
        }
        func pause(_ interval: TimeInterval) throws {
            let remaining = deadline - clock.now
            guard remaining > 0 else { throw WindowError.timedOut }
            clock.sleep(for: min(interval, remaining))
        }
    }
}
