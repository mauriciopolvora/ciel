import ApplicationServices
import Foundation

enum WindowAttribute {
    case position, size, minimized

    var name: String {
        switch self {
        case .position: return kAXPositionAttribute
        case .size: return kAXSizeAttribute
        case .minimized: return kAXMinimizedAttribute
        }
    }
}

/// The operation engine depends on window behavior, not Core Foundation types.
/// Implementations remain confined to their owner; they are not Sendable.
protocol WindowAccess: AnyObject {
    func isSameWindow(as other: any WindowAccess) -> Bool
    func frame(timeout: TimeInterval) throws -> CGRect
    func isFullScreen(timeout: TimeInterval) throws -> Bool
    func isSettable(_ attribute: WindowAttribute, timeout: TimeInterval) throws -> Bool
    func setSize(_ size: CGSize, timeout: TimeInterval) throws
    func setPosition(_ point: CGPoint, timeout: TimeInterval) throws
    func isMinimized(timeout: TimeInterval) throws -> Bool
    func minimize(timeout: TimeInterval) throws
    func enhancedUI(timeout: TimeInterval) throws -> Bool?
    func setEnhancedUI(_ enabled: Bool, timeout: TimeInterval) throws
}

protocol WindowAccessibility {
    var isTrusted: Bool { get }
    func focusedWindow(pid: pid_t) -> (any WindowAccess)?
}

struct SystemWindowAccessibility: WindowAccessibility {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func focusedWindow(pid: pid_t) -> (any WindowAccess)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        guard
            result == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return SystemWindowAccess(window: value as! AXUIElement, application: app)
    }
}

private final class SystemWindowAccess: WindowAccess {
    private let window: AXUIElement
    private let application: AXUIElement

    init(window: AXUIElement, application: AXUIElement) {
        self.window = window
        self.application = application
    }

    func isSameWindow(as other: any WindowAccess) -> Bool {
        guard let other = other as? SystemWindowAccess else { return false }
        return CFEqual(window, other.window)
    }

    func frame(timeout: TimeInterval) throws -> CGRect {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        try setTimeout(window, timeout)
        var values: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(
            window, [kAXPositionAttribute, kAXSizeAttribute] as CFArray, .stopOnError, &values)
        let position: CFTypeRef
        let size: CFTypeRef
        if result == .notImplemented || result == .attributeUnsupported {
            // Some apps implement individual reads without the batch operation.
            // Both fallback reads share the remaining timeout for this frame.
            guard
                let p = try value(
                    window, kAXPositionAttribute,
                    timeout: deadline - ProcessInfo.processInfo.systemUptime),
                let s = try value(
                    window, kAXSizeAttribute,
                    timeout: deadline - ProcessInfo.processInfo.systemUptime)
            else { throw WindowError.noWindow }
            position = p
            size = s
        } else {
            try check(result)
            guard let values, CFArrayGetCount(values) == 2 else { throw WindowError.noWindow }
            position = unsafeBitCast(CFArrayGetValueAtIndex(values, 0), to: CFTypeRef.self)
            size = unsafeBitCast(CFArrayGetValueAtIndex(values, 1), to: CFTypeRef.self)
        }
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw WindowError.noWindow
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
            AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
            point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
            dimensions.width > 0, dimensions.height > 0
        else { throw WindowError.noWindow }
        return CGRect(origin: point, size: dimensions)
    }

    func isFullScreen(timeout: TimeInterval) throws -> Bool {
        try value(window, "AXFullScreen", timeout: timeout) as? Bool == true
    }

    func isSettable(_ attribute: WindowAttribute, timeout: TimeInterval) throws -> Bool {
        try setTimeout(window, timeout)
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(window, attribute.name as CFString, &settable)
        if result == .attributeUnsupported || result == .notImplemented { return false }
        try check(result)
        return settable.boolValue
    }

    func setSize(_ size: CGSize, timeout: TimeInterval) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            throw WindowError.rejected(AXError.illegalArgument.rawValue)
        }
        try set(window, kAXSizeAttribute, value: value, timeout: timeout)
    }

    func setPosition(_ point: CGPoint, timeout: TimeInterval) throws {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else {
            throw WindowError.rejected(AXError.illegalArgument.rawValue)
        }
        try set(window, kAXPositionAttribute, value: value, timeout: timeout)
    }

    func isMinimized(timeout: TimeInterval) throws -> Bool {
        return try value(window, kAXMinimizedAttribute, timeout: timeout) as? Bool == true
    }

    func minimize(timeout: TimeInterval) throws {
        try set(window, kAXMinimizedAttribute, value: kCFBooleanTrue, timeout: timeout)
    }

    func enhancedUI(timeout: TimeInterval) throws -> Bool? {
        try value(application, "AXEnhancedUserInterface", timeout: timeout) as? Bool
    }

    func setEnhancedUI(_ enabled: Bool, timeout: TimeInterval) throws {
        try set(
            application, "AXEnhancedUserInterface", value: enabled ? kCFBooleanTrue : kCFBooleanFalse,
            timeout: timeout)
    }

    private func value(_ element: AXUIElement, _ name: String, timeout: TimeInterval) throws -> CFTypeRef? {
        try setTimeout(element, timeout)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if result == .attributeUnsupported || result == .noValue || result == .notImplemented { return nil }
        try check(result)
        return value
    }

    private func set(_ element: AXUIElement, _ name: String, value: CFTypeRef, timeout: TimeInterval) throws {
        try setTimeout(element, timeout)
        let result = AXUIElementSetAttributeValue(element, name as CFString, value)
        try check(result)
    }

    private func setTimeout(_ element: AXUIElement, _ timeout: TimeInterval) throws {
        guard timeout > 0 else { throw WindowError.timedOut }
        try check(AXUIElementSetMessagingTimeout(element, Float(timeout)))
    }

    private func check(_ result: AXError) throws {
        switch result {
        case .success: return
        case .apiDisabled: throw WindowError.permission
        case .invalidUIElement: throw WindowError.noWindow
        default: throw WindowError.rejected(result.rawValue)
        }
    }
}
