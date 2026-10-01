import CielCore
import Foundation

struct Configuration {
    var applicationCounts = [1000, 10_000]
    var iterations = 20
    var warmupIterations = 3
    var budgetMillisecondsPerThousand = 100.0
    var baselinePath: String?
    var maximumRegressionFactor = 4.0
    var outputPath: String?

    static let usage = """
        Usage: CielBenchmarks [options]
          --catalog-sizes 1000,10000   Synthetic application counts (commands are added).
          --iterations 20            Measured searches per query (at least 5).
          --warmup 3                 Warmup searches per query.
          --budget-ms-per-1000 100    Absolute p95 budget; scales with catalog size.
          --baseline FILE           Compare p95 with a previous search-engine JSON report.
          --max-regression-factor 4  Baseline allowance, with a 1 ms baseline floor.
          --output FILE             Save JSON to this path. JSON is also written to stdout.

        Run a release build. This measures SearchEngine only. It excludes icons,
        AppKit layout, launch latency, and time until pixels appear on screen.
        """

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard index + 1 < arguments.count else { throw BenchmarkError("Missing value for \(option)") }
            let value = arguments[index + 1]
            switch option {
            case "--catalog-sizes":
                let parts = value.split(separator: ",", omittingEmptySubsequences: false)
                let counts = parts.compactMap { Int($0) }
                guard counts.count == parts.count, !counts.isEmpty,
                    counts.allSatisfy({ (100...100_000).contains($0) }), Set(counts).count == counts.count
                else { throw BenchmarkError("Catalog sizes must be distinct integers from 100 to 100000") }
                applicationCounts = counts.sorted()
            case "--iterations":
                guard let count = Int(value), (5...10_000).contains(count) else {
                    throw BenchmarkError("Iterations must be an integer from 5 to 10000")
                }
                iterations = count
            case "--warmup":
                guard let count = Int(value), (0...1000).contains(count) else {
                    throw BenchmarkError("Warmup must be an integer from 0 to 1000")
                }
                warmupIterations = count
            case "--budget-ms-per-1000":
                guard let budget = Double(value), budget.isFinite, budget > 0 else {
                    throw BenchmarkError("The p95 budget must be a finite positive number")
                }
                budgetMillisecondsPerThousand = budget
            case "--baseline": baselinePath = value
            case "--max-regression-factor":
                guard let factor = Double(value), factor.isFinite, factor >= 1 else {
                    throw BenchmarkError("The regression factor must be a finite number of at least 1")
                }
                maximumRegressionFactor = factor
            case "--output": outputPath = value
            default: throw BenchmarkError("Unknown option: \(option)")
            }
            index += 2
        }
    }
}

struct BenchmarkError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct QueryCase {
    let name: String
    let query: String
    let expectsMatches: Bool
}

struct Measurement: Codable {
    let applicationCount: Int
    let catalogEntries: Int
    let name: String
    let query: String
    let matches: Int
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let maxMilliseconds: Double
    let budgetMilliseconds: Double
    let baselineP95Milliseconds: Double?
    let withinBudget: Bool
    let correctResults: Bool
}

struct Report: Codable {
    struct Parameters: Codable {
        let applicationCounts: [Int]
        let iterations: Int
        let warmupIterations: Int
        let budgetMillisecondsPerThousand: Double
        let maximumRegressionFactor: Double
        let baselinePath: String?
    }
    struct Runtime: Codable {
        let operatingSystem: String
        let architecture: String
        let processorCount: Int
        let buildConfiguration: String
    }
    let schemaVersion: Int
    let kind: String
    let measuredAt: String
    let runtime: Runtime
    let parameters: Parameters
    let cases: [Measurement]
    let passed: Bool
}

let queries: [QueryCase] = [
    .init(name: "empty-broad", query: "", expectsMatches: true),
    .init(name: "single-character-broad", query: "a", expectsMatches: true),
    .init(name: "keyword-broad", query: "application", expectsMatches: true),
    .init(name: "prefix", query: "safari", expectsMatches: true),
    .init(name: "typing-error", query: "safrai", expectsMatches: true),
    .init(name: "abbreviation", query: "vsc", expectsMatches: true),
    .init(name: "reordered-tokens", query: "code visual", expectsMatches: true),
    .init(name: "multiword", query: "sys set", expectsMatches: true),
    .init(
        name: "long-multiword", query: "Visual Studio Code Insiders Edition Application Collection",
        expectsMatches: true),
    .init(name: "no-match", query: "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", expectsMatches: false),
    .init(name: "multiword-no-match", query: "safari impossible", expectsMatches: false),
    .init(name: "window-command", query: "center", expectsMatches: true),
]

func catalog(applicationCount: Int) -> [SearchEntry] {
    let names = [
        "Safari", "Visual Studio Code", "Calculator", "Activity Monitor", "System Settings",
        "Calendar", "Terminal", "Photos", "Notion", "Firefox",
        "Visual Studio Code Insiders Edition Application Collection",
    ]
    return (0..<applicationCount).map {
        SearchEntry(
            id: "app\($0)", title: names[$0 % names.count] + " \($0)", subtitle: "Application",
            kind: .application, keywords: "Application desktop tool")
    } + SearchEntry.commands
}

func percentile(_ fraction: Double, sorted values: [Double]) -> Double {
    values[max(0, min(values.count - 1, Int(ceil(fraction * Double(values.count))) - 1))]
}

func run(_ configuration: Configuration) throws -> Report {
    var baseline: Report?
    if let path = configuration.baselinePath {
        baseline = try JSONDecoder().decode(Report.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard baseline?.schemaVersion == 1, baseline?.kind == "search-engine",
            baseline?.runtime.buildConfiguration == "release", baseline?.passed == true
        else {
            throw BenchmarkError(
                "The baseline must be a passing release search-engine report with schemaVersion 1")
        }
    }
    var measurements: [Measurement] = []
    for count in configuration.applicationCounts {
        let entries = catalog(applicationCount: count)
        for query in queries {
            var samples: [Double] = []
            var matchCount = 0
            var correct = true
            for iteration in 0..<(configuration.warmupIterations + configuration.iterations) {
                let start = DispatchTime.now().uptimeNanoseconds
                let results = SearchEngine.search(query.query, entries: entries)
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                matchCount = results.count
                correct =
                    correct && (query.expectsMatches ? !results.isEmpty : results.isEmpty)
                    && results.count <= 60
                if iteration >= configuration.warmupIterations { samples.append(elapsed) }
            }
            samples.sort()
            let reference = baseline?.cases.first { $0.applicationCount == count && $0.name == query.name }
            if baseline != nil, reference == nil {
                throw BenchmarkError("The baseline has no \(count)-application \(query.name) case")
            }
            if let reference, reference.query != query.query || !reference.correctResults {
                throw BenchmarkError("The baseline query does not match \(query.name)")
            }
            var budget = configuration.budgetMillisecondsPerThousand * max(1, Double(count) / 1000)
            if let reference {
                budget = min(
                    budget, max(1, reference.p95Milliseconds) * configuration.maximumRegressionFactor)
            }
            let p95 = percentile(0.95, sorted: samples)
            measurements.append(
                Measurement(
                    applicationCount: count, catalogEntries: entries.count, name: query.name,
                    query: query.query,
                    matches: matchCount, medianMilliseconds: percentile(0.5, sorted: samples),
                    p95Milliseconds: p95, maxMilliseconds: samples.last!, budgetMilliseconds: budget,
                    baselineP95Milliseconds: reference?.p95Milliseconds,
                    withinBudget: p95 <= budget, correctResults: correct))
        }
    }
    #if arch(arm64)
        let architecture = "arm64"
    #elseif arch(x86_64)
        let architecture = "x86_64"
    #else
        let architecture = "unknown"
    #endif
    #if DEBUG
        let buildConfiguration = "debug"
    #else
        let buildConfiguration = "release"
    #endif
    return Report(
        schemaVersion: 1, kind: "search-engine", measuredAt: ISO8601DateFormatter().string(from: Date()),
        runtime: .init(
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture, processorCount: ProcessInfo.processInfo.processorCount,
            buildConfiguration: buildConfiguration),
        parameters: .init(
            applicationCounts: configuration.applicationCounts, iterations: configuration.iterations,
            warmupIterations: configuration.warmupIterations,
            budgetMillisecondsPerThousand: configuration.budgetMillisecondsPerThousand,
            maximumRegressionFactor: configuration.maximumRegressionFactor,
            baselinePath: configuration.baselinePath),
        cases: measurements, passed: measurements.allSatisfy { $0.withinBudget && $0.correctResults })
}

if CommandLine.arguments.dropFirst().contains("--help") {
    print(Configuration.usage)
    exit(0)
}

do {
    let configuration = try Configuration(arguments: Array(CommandLine.arguments.dropFirst()))
    let report = try run(configuration)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let output = try encoder.encode(report)
    if let path = configuration.outputPath {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: url, options: .atomic)
    }
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data("\n".utf8))
    for measurement in report.cases where !measurement.withinBudget || !measurement.correctResults {
        let message = String(
            format: "FAIL %d entries, %@: p95 %.3f ms, budget %.3f ms, valid results %@\n",
            measurement.catalogEntries, measurement.name, measurement.p95Milliseconds,
            measurement.budgetMilliseconds, measurement.correctResults ? "yes" : "no")
        FileHandle.standardError.write(Data(message.utf8))
    }
    exit(report.passed ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("\(error)\n\(Configuration.usage)\n".utf8))
    exit(2)
}
