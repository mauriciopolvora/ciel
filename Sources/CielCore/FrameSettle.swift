import CoreGraphics
import Foundation

public struct FrameSettle {
    public enum Decision: Equatable {
        case matched
        case constrained
        case yieldForVisibilityCorrection
        case retry
        case keepPolling
    }

    public static let settleInterval: TimeInterval = 0.12
    public static let unchangedRetryDelay: TimeInterval = 0.2
    public static let visibilityCorrectionReserve: TimeInterval = 0.05
    static let tolerance: CGFloat = 3

    private let original: CGRect
    private let desired: CGRect
    private let visible: CGRect?
    private let started: TimeInterval
    public private(set) var last: CGRect
    private var stableSince: TimeInterval
    private var retryFrame: CGRect?

    public init(original: CGRect, desired: CGRect, visible: CGRect?, first: CGRect, at now: TimeInterval) {
        self.original = original
        self.desired = desired
        self.visible = visible
        started = now
        last = first
        stableSince = now
    }

    public var isUnchanged: Bool { Self.matches(last, original) }

    public func decide(now: TimeInterval, remaining: TimeInterval) -> Decision {
        if Self.matches(last, desired) { return .matched }
        guard now - stableSince >= Self.settleInterval else { return .keepPolling }
        guard let retryFrame else {
            let waitedForUnchanged = now - started >= Self.unchangedRetryDelay
            return appearsSizeConstrained || waitedForUnchanged ? .retry : .keepPolling
        }
        guard Self.matches(last, retryFrame) else { return .keepPolling }
        if appearsSizeConstrained { return .constrained }
        if needsVisibilityCorrection, !isUnchanged, remaining <= Self.visibilityCorrectionReserve {
            return .yieldForVisibilityCorrection
        }
        return .keepPolling
    }

    public mutating func observe(_ frame: CGRect, at now: TimeInterval) {
        if !Self.matches(frame, last) { stableSince = now }
        last = frame
    }

    public mutating func retried(_ frame: CGRect, at now: TimeInterval) {
        last = frame
        retryFrame = frame
        stableSince = now
    }

    private var appearsSizeConstrained: Bool {
        !Self.matches(last.size, original.size) && !Self.matches(last.size, desired.size)
    }

    private var needsVisibilityCorrection: Bool {
        guard let visible else { return false }
        return !Self.matches(last.origin, Self.reachableOrigin(last, in: visible))
    }

    public static func matches(_ actual: CGRect, _ desired: CGRect) -> Bool {
        matches(actual.origin, desired.origin) && matches(actual.size, desired.size)
    }
    public static func matches(_ actual: CGPoint, _ desired: CGPoint) -> Bool {
        abs(actual.x - desired.x) <= tolerance && abs(actual.y - desired.y) <= tolerance
    }
    public static func matches(_ actual: CGSize, _ desired: CGSize) -> Bool {
        abs(actual.width - desired.width) <= tolerance && abs(actual.height - desired.height) <= tolerance
    }
    public static func reachableOrigin(_ frame: CGRect, in visible: CGRect) -> CGPoint {
        CGPoint(
            x: max(visible.minX, min(frame.minX, visible.maxX - frame.width)),
            y: max(visible.minY, min(frame.minY, visible.maxY - frame.height)))
    }
}

public struct FullScreenExit {
    public static let budget: TimeInterval = 1.5
    public static let pollInterval: TimeInterval = 0.03

    private var last: CGRect?
    private var stableSince: TimeInterval?

    public init() {}

    public mutating func observe(fullScreen: Bool?, frame: CGRect?, at now: TimeInterval) -> Bool {
        guard fullScreen == false, let frame else {
            last = nil
            stableSince = nil
            return false
        }
        if let last, FrameSettle.matches(frame, last), let stableSince {
            return now - stableSince >= FrameSettle.settleInterval
        }
        last = frame
        stableSince = now
        return false
    }
}
