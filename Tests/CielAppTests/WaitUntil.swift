@testable import CielApp

struct WaitTimedOut: Error {}

@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else { throw WaitTimedOut() }
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
func waitForIdle(_ cache: IconCache) async throws {
    try await waitUntil { cache.pendingCount == 0 }
}
