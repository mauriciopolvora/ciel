@testable import CielApp

struct WaitTimedOut: Error {}

@MainActor
func waitUntil(polls: Int = 3000, _ condition: () -> Bool) async throws {
    for _ in 0..<polls {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    guard condition() else { throw WaitTimedOut() }
}

@MainActor
func waitForIdle(_ cache: IconCache) async throws {
    try await waitUntil { cache.pendingCount == 0 }
}
