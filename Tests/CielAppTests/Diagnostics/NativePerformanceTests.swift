import Testing

@testable import CielApp

@Suite struct NativePerformanceTests {
    @Test func reportsEveryExceededBudget() {
        let budget = NativePerformanceBudget()
        #expect(budget.failures(startup: 3_000, p95: 51, idleCPU: 11, growthMiB: 25).count == 4)
        #expect(budget.failures(startup: 100, p95: 1, idleCPU: 0, growthMiB: -1).isEmpty)
    }

    @Test func invalidMeasurementsCannotPass() {
        #expect(
            NativePerformanceBudget().failures(
                startup: .nan, p95: .infinity, idleCPU: .nan, growthMiB: .infinity
            ).count == 4)
    }

    @MainActor @Test func percentileUsesObservedSamples() {
        #expect(PerformanceCheck.percentile([1, 2, 3, 4, 5], fraction: 0.95) == 5)
        #expect(PerformanceCheck.percentile([1, 2, 3, 4, 5], fraction: 0.5) == 3)
    }
}
