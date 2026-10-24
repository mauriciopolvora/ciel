import CoreGraphics
import Testing

@testable import CielApp

@Suite("Frame settle decisions")
struct FrameSettleTests {
    private let screen = CGRect(x: 0, y: 30, width: 1200, height: 800)
    private let original = CGRect(x: 150, y: 160, width: 800, height: 500)
    private let leftHalf = CGRect(x: 0, y: 30, width: 600, height: 800)
    private let minimumSize = CGRect(x: 0, y: 30, width: 900, height: 800)

    private func settle(original: CGRect? = nil, desired: CGRect? = nil) -> FrameSettle {
        let original = original ?? self.original
        return FrameSettle(
            original: original, desired: desired ?? leftHalf, visible: screen, first: original, at: 0)
    }

    @Test("A frame within tolerance of the target matches at once")
    func matchWithinTolerance() {
        var settle = settle()
        settle.observe(leftHalf.offsetBy(dx: 2, dy: -2), at: 0.01)
        #expect(settle.decide(now: 0.01, remaining: 0.49) == .matched)
    }

    @Test("An unchanged frame gets time to respond before the retry")
    func unchangedFrameWaitsBeforeRetry() {
        let settle = settle()
        let delay = FrameSettle.unchangedRetryDelay
        #expect(settle.decide(now: delay - 0.01, remaining: 0.5 - delay + 0.01) == .keepPolling)
        #expect(settle.decide(now: delay, remaining: 0.5 - delay) == .retry)
    }

    @Test("A changed size that holds still retries before the unchanged-frame delay")
    func constrainedSizeRetriesSooner() {
        var settle = settle()
        settle.observe(minimumSize, at: 0.01)
        let stable = 0.01 + FrameSettle.settleInterval
        #expect(stable < FrameSettle.unchangedRetryDelay)
        #expect(settle.decide(now: stable - 0.001, remaining: 0.5 - stable) == .keepPolling)
        #expect(settle.decide(now: stable, remaining: 0.5 - stable) == .retry)
    }

    @Test("A frame that is still moving does not retry")
    func movingFrameKeepsPolling() {
        var settle = settle()
        settle.observe(original.offsetBy(dx: -40, dy: 0), at: 0.15)
        settle.observe(original.offsetBy(dx: -80, dy: 0), at: 0.25)
        #expect(settle.decide(now: 0.3, remaining: 0.2) == .keepPolling)
    }

    @Test("The same constrained frame after the retry settles as constrained")
    func repeatedConstraintSettles() {
        var settle = settle()
        settle.observe(minimumSize, at: 0.01)
        settle.retried(minimumSize, at: 0.13)
        let stable = 0.13 + FrameSettle.settleInterval
        #expect(settle.decide(now: stable - 0.001, remaining: 0.5 - stable) == .keepPolling)
        #expect(settle.decide(now: stable, remaining: 0.5 - stable) == .constrained)
    }

    @Test("An unchanged size after the retry is a pending write, not a minimum size")
    func unchangedSizeIsNotConstrained() {
        var settle = settle()
        settle.retried(original, at: 0.2)
        #expect(settle.decide(now: 0.45, remaining: 0.05) == .keepPolling)
        #expect(settle.isUnchanged)
    }

    @Test("A window already at its minimum size yields near the deadline for a visibility correction")
    func minimumSizeWindowYieldsForCorrection() {
        let rightHalf = CGRect(x: 600, y: 30, width: 600, height: 800)
        let offscreen = CGRect(x: 600, y: 30, width: 900, height: 800)
        var settle = settle(original: minimumSize, desired: rightHalf)
        settle.observe(offscreen, at: 0.01)
        settle.retried(offscreen, at: 0.2)
        let reserve = FrameSettle.visibilityCorrectionReserve
        #expect(settle.decide(now: 0.44, remaining: reserve + 0.01) == .keepPolling)
        #expect(settle.decide(now: 0.45, remaining: reserve) == .yieldForVisibilityCorrection)
        #expect(!settle.isUnchanged)
    }

    @Test("A reachable origin keeps the whole frame inside the visible area")
    func reachableOrigin() {
        let offscreen = CGRect(x: 600, y: -20, width: 900, height: 800)
        #expect(FrameSettle.reachableOrigin(offscreen, in: screen) == CGPoint(x: 300, y: 30))
        #expect(FrameSettle.reachableOrigin(leftHalf, in: screen) == leftHalf.origin)
    }
}
