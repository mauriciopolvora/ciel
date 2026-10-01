import AppKit
import Darwin
import Foundation

struct NativePerformanceBudget {
    var maximumP95Milliseconds: Double = 50
    var maximumStartupMilliseconds: Double = 2_500
    var maximumIdleCPUPercent: Double = 10
    var maximumGrowthMiB: Double = 24

    func failures(startup: Double, p95: Double, idleCPU: Double, growthMiB: Double) -> [String] {
        var result: [String] = []
        if !startup.isFinite || startup > maximumStartupMilliseconds {
            result.append("Startup exceeded budget")
        }
        if !p95.isFinite || p95 > maximumP95Milliseconds {
            result.append("Native update p95 exceeded budget")
        }
        if !idleCPU.isFinite || idleCPU > maximumIdleCPUPercent { result.append("Idle CPU exceeded budget") }
        if !growthMiB.isFinite || growthMiB > maximumGrowthMiB {
            result.append("Session resident growth exceeded budget")
        }
        return result
    }
}

/// An explicit desktop diagnostic. Its temporary app identity protects user preferences.
@MainActor enum PerformanceCheck {
    static func run(launcher: LauncherView, panel: LauncherPanel, startupMilliseconds: Double) {
        Task {
            do {
                try await measure(launcher: launcher, panel: panel, startupMilliseconds: startupMilliseconds)
            } catch {
                print("FAIL native performance: \(error.localizedDescription)")
                exit(1)
            }
        }
    }

    private static func measure(launcher: LauncherView, panel: LauncherPanel, startupMilliseconds: Double)
        async throws
    {
        let environment = ProcessInfo.processInfo.environment
        let cycles = try integer(
            "CIEL_NATIVE_CYCLES", default: 300, range: 10...100_000, environment: environment)
        let idleSeconds = try number("CIEL_NATIVE_IDLE_SECONDS", default: 5, environment: environment)
        guard idleSeconds <= 300 else { throw DiagnosticError.invalid("CIEL_NATIVE_IDLE_SECONDS") }
        var budget = NativePerformanceBudget()
        budget.maximumP95Milliseconds = try number(
            "CIEL_NATIVE_MAX_P95_MS", default: 50, environment: environment)
        budget.maximumStartupMilliseconds = try number(
            "CIEL_NATIVE_MAX_STARTUP_MS", default: 2_500, environment: environment)
        budget.maximumIdleCPUPercent = try number(
            "CIEL_NATIVE_MAX_IDLE_CPU_PERCENT", default: 10, environment: environment)
        budget.maximumGrowthMiB = try number(
            "CIEL_NATIVE_MAX_GROWTH_MIB", default: 24, environment: environment)

        let firstStarted = ProcessInfo.processInfo.systemUptime
        let firstUpdate = update("calclator", launcher: launcher, panel: panel)
        try await settleIcons(launcher)
        panel.displayIfNeeded()
        let firstSettled = (ProcessInfo.processInfo.systemUptime - firstStarted) * 1_000
        let baseline = try resources()
        let queries = ["half", "safrai", "", "calclator", "zzzzzzzzzz", "center", "   ", "a"]
        var timings: [Double] = []
        var samples: [ResourceSample] = [baseline]
        for index in 0..<cycles {
            let duration = update(queries[index % queries.count], launcher: launcher, panel: panel)
            if index >= 8 { timings.append(duration) }
            // Let AppKit and worker completions run between interactions.
            try await Task.sleep(for: .milliseconds(2))
            if index > 0 && index % 100 == 0 { samples.append(try resources()) }
        }
        try await settleIcons(launcher)
        panel.displayIfNeeded()
        let afterSession = try resources()
        samples.append(afterSession)
        panel.orderOut(nil)
        let idleStart = try resources()
        try await Task.sleep(for: .seconds(idleSeconds))
        let idleEnd = try resources()
        samples.append(idleEnd)
        let actualIdleSeconds = idleEnd.wallSeconds - idleStart.wallSeconds
        let idleCPU = max(0, idleEnd.cpuSeconds - idleStart.cpuSeconds) / actualIdleSeconds * 100
        let growthMiB = (Double(afterSession.residentBytes) - Double(baseline.residentBytes)) / 1_048_576
        timings.sort()
        let p95 = percentile(timings, fraction: 0.95)
        let failures = budget.failures(
            startup: startupMilliseconds, p95: p95, idleCPU: idleCPU, growthMiB: growthMiB)
        let report: [String: Any] = [
            "schemaVersion": 1,
            "kind": "native-ui",
            "platform": ProcessInfo.processInfo.operatingSystemVersionString,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "unknown",
            "buildConfiguration": "release",
            "parameters": ["cycles": cycles, "idleSeconds": actualIdleSeconds],
            "startupMilliseconds": startupMilliseconds,
            "firstQueryDisplaySubmissionMilliseconds": firstUpdate,
            "firstQueryIconSettlementMilliseconds": firstSettled,
            "updateMedianMilliseconds": percentile(timings, fraction: 0.5),
            "updateP95Milliseconds": p95,
            "updateMaximumMilliseconds": timings.last ?? 0,
            "idleCPUPercentOfOneCore": idleCPU,
            "sessionResidentGrowthMiB": growthMiB,
            "resourceSamples": samples.map {
                [
                    "wallSeconds": $0.wallSeconds, "cpuSeconds": $0.cpuSeconds,
                    "residentBytes": $0.residentBytes,
                ] as [String: Any]
            },
            "budgets": [
                "maximumP95Milliseconds": budget.maximumP95Milliseconds,
                "maximumStartupMilliseconds": budget.maximumStartupMilliseconds,
                "maximumIdleCPUPercent": budget.maximumIdleCPUPercent,
                "maximumGrowthMiB": budget.maximumGrowthMiB,
            ],
            "passed": failures.isEmpty,
            "failures": failures,
            "limits": [
                "Native update timing ends at synchronous layout/display submission, not physical display presentation.",
                "First icon settlement uses bounded polling and includes polling overhead.",
                "Resident memory growth describes this workload; it is not a leak proof.",
            ],
        ]
        let output =
            environment["CIEL_PERFORMANCE_OUTPUT"] ?? NSTemporaryDirectory() + "ciel-performance.json"
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: output).deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        print(String(data: data, encoding: .utf8) ?? "{}")
        print("Native performance report: \(output)")
        exit(failures.isEmpty ? 0 : 1)
    }

    private static func update(_ query: String, launcher: LauncherView, panel: LauncherPanel) -> Double {
        let started = DispatchTime.now().uptimeNanoseconds
        PerformanceTrace.measure("NativeQueryDisplay") {
            launcher.searchField.stringValue = query
            launcher.updateResults()
            launcher.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
        }
        return Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    private static func settleIcons(_ launcher: LauncherView) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while launcher.pendingIconCount > 0 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw DiagnosticError.iconsTimedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    static func percentile(_ values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        return values[min(values.count - 1, max(0, Int(ceil(Double(values.count) * fraction)) - 1))]
    }

    private struct ResourceSample {
        let wallSeconds: Double
        let cpuSeconds: Double
        let residentBytes: UInt64
    }

    private static func resources() throws -> ResourceSample {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw DiagnosticError.resourcesUnavailable }
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw DiagnosticError.resourcesUnavailable }
        let cpu =
            Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        return ResourceSample(
            wallSeconds: ProcessInfo.processInfo.systemUptime, cpuSeconds: cpu,
            residentBytes: UInt64(info.resident_size))
    }

    private static func number(_ name: String, default value: Double, environment: [String: String]) throws
        -> Double
    {
        guard let raw = environment[name] else { return value }
        guard let parsed = Double(raw), parsed.isFinite, parsed > 0 else {
            throw DiagnosticError.invalid(name)
        }
        return parsed
    }

    private static func integer(
        _ name: String, default value: Int, range: ClosedRange<Int>, environment: [String: String]
    ) throws -> Int {
        guard let raw = environment[name] else { return value }
        guard let parsed = Int(raw), range.contains(parsed) else { throw DiagnosticError.invalid(name) }
        return parsed
    }

    private enum DiagnosticError: LocalizedError {
        case invalid(String)
        case iconsTimedOut
        case resourcesUnavailable
        var errorDescription: String? {
            switch self {
            case .invalid(let name): return "Invalid \(name)"
            case .iconsTimedOut: return "Icon work exceeded the diagnostic deadline"
            case .resourcesUnavailable: return "Process resource measurements are unavailable"
            }
        }
    }
}
