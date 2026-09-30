import CielCore
import CoreGraphics
import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}
func expectTrue(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line)
    throws
{
    if !value { throw CheckFailure(description: "\(file):\(line): condition failed \(message)") }
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line)
    throws
{
    if actual != expected { throw CheckFailure(description: "\(file):\(line): \(actual) != \(expected)") }
}
func expectEqual(
    _ actual: CGFloat, _ expected: CGFloat, accuracy: CGFloat, file: StaticString = #filePath,
    line: UInt = #line
) throws {
    try expectTrue(abs(actual - expected) <= accuracy, "\(actual) != \(expected)", file: file, line: line)
}
func expectGreaterThan<T: Comparable>(
    _ actual: T, _ lower: T, file: StaticString = #filePath, line: UInt = #line
) throws {
    try expectTrue(actual > lower, file: file, line: line)
}
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws {
    try expectTrue(value == nil, file: file, line: line)
}

let checks: [(String, () throws -> Void)] = [
    ("testExactMatchOutranksFrequentlyUsedPrefix", SearchTests().testExactMatchOutranksFrequentlyUsedPrefix),
    ("testTypingErrors", SearchTests().testTypingErrors),
    ("testReorderedTokens", SearchTests().testReorderedTokens),
    ("testDiscovery", CatalogTests().testDiscovery),
    ("testAbbreviations", SearchTests().testAbbreviations),
    ("testCaseAccentsAndWhitespace", SearchTests().testCaseAccentsAndWhitespace),
    ("testAllTokensMustMatch", SearchTests().testAllTokensMustMatch),
    ("testCommandAliasesAndFilter", SearchTests().testCommandAliasesAndFilter),
    ("testFrequentCommandsRankAboveApps", SearchTests().testFrequentCommandsRankAboveApps),
    ("testRecentUseBreaksFrequencyTies", SearchTests().testRecentUseBreaksFrequencyTies),
    ("testMinimizeSearch", SearchTests().testMinimizeSearch),
    ("testPersistenceAndLegacyCounts", UsageHistoryTests().testPersistenceAndLegacyCounts),
    ("testHistoryAndLimit", SearchTests().testHistoryAndLimit),
    ("testEmptyAndUnicodeQueries", SearchTests().testEmptyAndUnicodeQueries),
    ("testSearchBudgetWithOneThousandEntries", SearchTests().testSearchBudgetWithOneThousandEntries),
    (
        "testHalvesShareAnExactBoundaryOnOddWidthDisplay",
        GeometryTests().testHalvesShareAnExactBoundaryOnOddWidthDisplay
    ),
    ("testAllLayoutsStayInsideUsableArea", GeometryTests().testAllLayoutsStayInsideUsableArea),
    ("testCenterPreservesSize", GeometryTests().testCenterPreservesSize),
    ("testCenterClampsOversizedWindow", GeometryTests().testCenterClampsOversizedWindow),
    (
        "testAppKitConversionWithDisplayAboveAndLeft",
        GeometryTests().testAppKitConversionWithDisplayAboveAndLeft
    ),
    (
        "testDisplaySelectionUsesLargestIntersection",
        GeometryTests().testDisplaySelectionUsesLargestIntersection
    ),
    ("testOffScreenWindowUsesNearestDisplay", GeometryTests().testOffScreenWindowUsesNearestDisplay),
    ("testMoveToDisplayPreservesRelativeLayout", GeometryTests().testMoveToDisplayPreservesRelativeLayout),
    ("testMoveClampsWindowOutsideSource", GeometryTests().testMoveClampsWindowOutsideSource),
    ("testSnapAtGuideIntersection", LauncherPlacementTests().testSnapAtGuideIntersection),
    ("testFreePlacementAndDistance", LauncherPlacementTests().testFreePlacementAndDistance),
    ("testNarrowScreenAndEdges", LauncherPlacementTests().testNarrowScreenAndEdges),
    ("testInputAnchorSurvivesResultResizing", LauncherPlacementTests().testInputAnchorSurvivesResultResizing),
    ("testDisplayChangeAndPersistence", LauncherPlacementTests().testDisplayChangeAndPersistence),
    ("testInvalidSavedPlacementFallsBack", LauncherPlacementTests().testInvalidSavedPlacementFallsBack),
]
var failures = 0
for (name, check) in checks {
    do {
        try check()
        print("PASS \(name)")
    } catch {
        failures += 1
        print("FAIL \(name): \(error)")
    }
}
let names = [
    "Safari", "Visual Studio Code", "Calculator", "Activity Monitor", "System Settings",
    "Calendar", "Terminal", "Photos", "Notion", "Firefox",
]
let entries =
    (0..<1000).map {
        SearchEntry(
            id: "app\($0)", title: names[$0 % names.count] + " \($0)", subtitle: "Application",
            kind: .application)
    } + SearchEntry.commands
let queries = ["safrai", "vsc", "calclator", "am", "sys set", "frfx", "term", "photos", "right", "center"]
var timings: [Double] = []
for index in 0..<110 {
    let start = DispatchTime.now().uptimeNanoseconds
    let results = SearchEngine.search(queries[index % queries.count], entries: entries)
    if results.isEmpty {
        failures += 1
        print("FAIL benchmark query: \(queries[index % queries.count])")
    }
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    if index >= 10 { timings.append(elapsed) }
}
timings.sort()
print(
    String(
        format: "Mixed fuzzy search benchmark (%d entries): median %.2f ms, p95 %.2f ms", entries.count,
        timings[50], timings[95]))
print("\(checks.count) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
