import AppKit
import ApplicationServices
import CielCore

struct DisplaySnapshot {
    let full: CGRect
    let visible: CGRect
    static func current() -> [DisplaySnapshot] {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        return screens.map {
            DisplaySnapshot(
                full: WindowGeometry.accessibilityRect($0.frame, primaryHeight: primaryHeight),
                visible: WindowGeometry.accessibilityRect($0.visibleFrame, primaryHeight: primaryHeight))
        }.sorted { $0.full.minX == $1.full.minX ? $0.full.minY < $1.full.minY : $0.full.minX < $1.full.minX }
    }
}

final class WindowController {
    private let queue = DispatchQueue(label: "app.ciel.windows", qos: .userInitiated)
    private var target: AXUIElement?
    private var targetPID: pid_t?
    private var history: [(window: AXUIElement, frame: CGRect)] = []
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func capture(pid: pid_t?) {
        queue.async {
            self.target = nil
            self.targetPID = pid
            // AX calls into our own AppKit views on this queue can deadlock AppKit.
            guard let pid, pid != ProcessInfo.processInfo.processIdentifier, Self.isTrusted else {
                self.targetPID = nil
                return
            }
            self.target = Self.focusedWindow(pid: pid)
        }
    }

    func perform(
        _ action: WindowAction, displays: [DisplaySnapshot],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        queue.async {
            let result: Result<String, Error>
            do { result = .success(try self.apply(action, displays: displays)) } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func apply(_ action: WindowAction, displays: [DisplaySnapshot]) throws -> String {
        guard Self.isTrusted else { throw WindowError.permission }
        if target == nil, let pid = targetPID { target = Self.focusedWindow(pid: pid) }
        guard let window = target else { throw WindowError.noWindow }
        AXUIElementSetMessagingTimeout(window, 0.25)
        if Self.value(window, "AXFullScreen") as? Bool == true { throw WindowError.fullScreen }
        if action == .minimize {
            var canMinimize = DarwinBoolean(false)
            guard
                AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &canMinimize)
                    == .success,
                canMinimize.boolValue
            else { throw WindowError.unsupported }
            let result = AXUIElementSetAttributeValue(
                window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            guard result == .success else { throw WindowError.rejected(result.rawValue) }
            // The Dock animation can delay the minimized state after AX accepts the change.
            // Confirm it on the window queue before recording a successful command.
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while Self.value(window, kAXMinimizedAttribute) as? Bool != true {
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    throw WindowError.rejected(AXError.cannotComplete.rawValue)
                }
                Thread.sleep(forTimeInterval: 0.025)
            }
            return action.title
        }
        guard let original = Self.frame(window),
            let index = WindowGeometry.displayIndex(for: original, displays: displays.map(\.full))
        else { throw WindowError.noWindow }
        let source = displays[index].visible
        var desired: CGRect
        var targetVisible = source
        if action == .restore {
            guard let saved = history.last(where: { CFEqual($0.window, window) }) else {
                throw WindowError.noHistory
            }
            desired = saved.frame
            // A display can be disconnected after a snap. Keep the restored window reachable.
            if !displays.contains(where: { $0.visible.intersects(desired) }) {
                desired = WindowAction.center.frame(in: source, current: desired)
            }
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
        var canMove = DarwinBoolean(false)
        var canResize = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &canMove)
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &canResize)
        guard canMove.boolValue else { throw WindowError.unsupported }
        if !canResize.boolValue && desired.size != original.size { throw WindowError.unsupported }
        // Enhanced UI can make an app animate each AX update separately. Disable
        // it only for this operation, then restore its original enabled state.
        let app = targetPID.map { AXUIElementCreateApplication($0) }
        if let app { AXUIElementSetMessagingTimeout(app, 0.25) }
        let restoreEnhancedUI =
            app.map {
                Self.value($0, "AXEnhancedUserInterface") as? Bool == true
                    && AXUIElementSetAttributeValue(
                        $0, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) == .success
            } ?? false
        defer {
            if restoreEnhancedUI, let app {
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
        }
        // Send size-position-size without waiting at an intermediate frame.
        // The final size update handles apps that clamp at the old position.
        if canResize.boolValue && desired.size != original.size { try Self.setSize(window, desired.size) }
        if desired.origin != original.origin { try Self.setPosition(window, desired.origin) }
        if canResize.boolValue && (desired.size != original.size || targetVisible != source) {
            try Self.setSize(window, desired.size)
        }
        Self.waitForFrame(window) { Self.matches($0, desired) }
        guard var actual = Self.frame(window) else { throw WindowError.noWindow }
        // Some apps clamp a move against their previous size. Retry only after
        // the fast update fails, rather than delaying every normal snap.
        if !Self.matches(actual, desired) {
            if actual.size != desired.size && canResize.boolValue { try Self.setSize(window, desired.size) }
            if actual.origin != desired.origin { try Self.setPosition(window, desired.origin) }
            Self.waitForFrame(window) { Self.matches($0, desired) }
            actual = Self.frame(window) ?? actual
        }
        // Preserve visibility if an app enforces a larger minimum size.
        let bounded = CGPoint(
            x: max(targetVisible.minX, min(actual.minX, targetVisible.maxX - actual.width)),
            y: max(targetVisible.minY, min(actual.minY, targetVisible.maxY - actual.height)))
        if bounded != actual.origin {
            try Self.setPosition(window, bounded)
            actual = Self.frame(window) ?? actual
        }
        history.removeAll { CFEqual($0.window, window) }
        history.append((window, original))
        if history.count > 24 { history.removeFirst() }
        if abs(actual.width - desired.width) > 3 || abs(actual.height - desired.height) > 3 {
            return "The app limited the window size."
        }
        if abs(actual.minX - desired.minX) > 3 || abs(actual.minY - desired.minY) > 3 {
            return "The app limited the window position."
        }
        return action.title
    }

    private static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let value = value(app, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func waitForFrame(_ window: AXUIElement, matches: (CGRect) -> Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.5
        repeat {
            if let current = frame(window), matches(current) { return }
            Thread.sleep(forTimeInterval: 0.01)
        } while ProcessInfo.processInfo.systemUptime < deadline
    }

    private static func matches(_ actual: CGRect, _ desired: CGRect) -> Bool {
        abs(actual.minX - desired.minX) <= 3 && abs(actual.minY - desired.minY) <= 3
            && abs(actual.width - desired.width) <= 3 && abs(actual.height - desired.height) <= 3
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = value(window, kAXPositionAttribute), let s = value(window, kAXSizeAttribute),
            CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    private static func setSize(_ window: AXUIElement, _ size: CGSize) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            throw WindowError.rejected(AXError.illegalArgument.rawValue)
        }
        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        guard result == .success else { throw WindowError.rejected(result.rawValue) }
    }
    private static func setPosition(_ window: AXUIElement, _ point: CGPoint) throws {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else {
            throw WindowError.rejected(AXError.illegalArgument.rawValue)
        }
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        guard result == .success else { throw WindowError.rejected(result.rawValue) }
    }
}

enum WindowError: LocalizedError {
    case permission, noWindow, fullScreen, noHistory, oneDisplay, unsupported
    case rejected(Int32)
    var errorDescription: String? {
        switch self {
        case .permission: return "Allow Accessibility access in Settings to move windows."
        case .noWindow: return "Focus an app window, then try again."
        case .fullScreen: return "Exit macOS full screen before moving this window."
        case .noHistory: return "Move or resize this window first."
        case .oneDisplay: return "Connect another display to use this command."
        case .unsupported: return "This window does not support that action."
        case .rejected: return "The app did not accept the window change. Try again."
        }
    }
}
