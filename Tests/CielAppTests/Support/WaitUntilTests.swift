import Testing

@testable import CielApp

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct WaitUntilTests {
    @Test func timeQueuedBehindOtherMainActorWorkDoesNotCountAgainstTheWait() async throws {
        let change = Change()
        Task { @MainActor in
            let end = ContinuousClock.now.advanced(by: .milliseconds(300))
            while ContinuousClock.now < end {}
        }
        Task { @MainActor in
            await Task.detached {}.value
            change.arrived = true
        }
        try await waitUntil(polls: 100) { change.arrived }
    }
}

@MainActor private final class Change {
    var arrived = false
}
