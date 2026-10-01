import Foundation
import os

/// Named intervals are recorded only when a profiling tool enables signposts.
enum PerformanceTrace {
    private static let signposter = OSSignposter(
        subsystem: "app.mauriciopolvora.jumpstart", category: "Performance")

    static func measure<Value>(_ name: StaticString, _ operation: () throws -> Value) rethrows -> Value {
        let interval = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, interval) }
        return try operation()
    }
}

@MainActor enum AppPerformance {
    private(set) static var launchedAt = ProcessInfo.processInfo.systemUptime

    static func markLaunch() {
        launchedAt = ProcessInfo.processInfo.systemUptime
    }

    static var startupMilliseconds: Double {
        (ProcessInfo.processInfo.systemUptime - launchedAt) * 1_000
    }
}
