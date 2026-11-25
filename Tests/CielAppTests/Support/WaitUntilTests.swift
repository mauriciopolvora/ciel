import Testing

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct WaitUntilTests {
    @Test func timeQueuedBehindOtherMainActorWorkDoesNotCountAgainstTheWait() async throws {
        let stall = Stall()
        Task { @MainActor in
            let end = ContinuousClock.now.advanced(by: .milliseconds(300))
            while ContinuousClock.now < end {}
            stall.ended = true
        }
        var pollsAfterStall = 0
        try await waitUntil(polls: 100) {
            if stall.ended { pollsAfterStall += 1 }
            return pollsAfterStall == 2
        }
    }
}

@MainActor private final class Stall {
    var ended = false
}
