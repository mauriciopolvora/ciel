import CoreGraphics
import Foundation

struct FrameSettle {
    enum Decision: Equatable {
        case matched
        case constrained
        case yieldForVisibilityCorrection
        case retry
        case keepPolling
    }

    static let settleInterval: TimeInterval = 0.12
    static let unchangedRetryDelay: TimeInterval = 0.2
    static let visibilityCorrectionReserve: TimeInterval = 0.05
    static let tolerance: CGFloat = 3

    private let original: CGRect
    private let desired: CGRect
    private let visible: CGRect?
    private let started: TimeInterval
    private(set) var last: CGRect
    private var stableSince: TimeInterval
    private var retryFrame: CGRect?

    init(original: CGRect, desired: CGRect, visible: CGRect?, first: CGRect, at now: TimeInterval) {
        self.original = original
        self.desired = desired
        self.visible = visible
        started = now
        last = first
        stableSince = now
    }

    var isUnchanged: Bool { Self.matches(last, original) }

    func decide(now: TimeInterval, remaining: TimeInterval) -> Decision {
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

    mutating func observe(_ frame: CGRect, at now: TimeInterval) {
        if !Self.matches(frame, last) { stableSince = now }
        last = frame
    }

    mutating func retried(_ frame: CGRect, at now: TimeInterval) {
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

    static func matches(_ actual: CGRect, _ desired: CGRect) -> Bool {
        matches(actual.origin, desired.origin) && matches(actual.size, desired.size)
    }
    static func matches(_ actual: CGPoint, _ desired: CGPoint) -> Bool {
        abs(actual.x - desired.x) <= tolerance && abs(actual.y - desired.y) <= tolerance
    }
    static func matches(_ actual: CGSize, _ desired: CGSize) -> Bool {
        abs(actual.width - desired.width) <= tolerance && abs(actual.height - desired.height) <= tolerance
    }
    static func reachableOrigin(_ frame: CGRect, in visible: CGRect) -> CGPoint {
        CGPoint(
            x: max(visible.minX, min(frame.minX, visible.maxX - frame.width)),
            y: max(visible.minY, min(frame.minY, visible.maxY - frame.height)))
    }
}
