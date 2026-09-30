import CielCore
import CoreGraphics
import Foundation

final class SearchTests {
    let apps = [
        SearchEntry(id: "safari", title: "Safari", subtitle: "Application", kind: .application),
        SearchEntry(id: "code", title: "Visual Studio Code", subtitle: "Application", kind: .application),
        SearchEntry(id: "cafe", title: "Café", subtitle: "Application", kind: .application),
    ]

    func testExactMatchOutranksFrequentlyUsedPrefix() throws {
        let other = SearchEntry(
            id: "safari-tech", title: "Safari Technology Preview", subtitle: "Application", kind: .application
        )
        try expectEqual(
            SearchEngine.search("safari", entries: apps + [other], usage: [other.id: 1000]).first?.id,
            "safari")
    }
    func testAbbreviations() throws {
        try expectEqual(SearchEngine.search("vsc", entries: apps).first?.id, "code")
    }
    func testTypingErrors() throws {
        let calculator = SearchEntry(
            id: "calculator", title: "Calculator", subtitle: "Application", kind: .application)
        try expectEqual(SearchEngine.search("safrai", entries: apps).first?.id, "safari")
        try expectEqual(
            SearchEngine.search("calclator", entries: apps + [calculator]).first?.id, "calculator")
        try expectTrue(SearchEngine.search("zz", entries: apps).isEmpty)
    }
    func testReorderedTokens() throws {
        try expectEqual(SearchEngine.search("code visual", entries: apps).first?.id, "code")
    }
    func testCaseAccentsAndWhitespace() throws {
        try expectEqual(SearchEngine.search("  CAFE  ", entries: apps).first?.id, "cafe")
    }
    func testAllTokensMustMatch() throws {
        try expectTrue(SearchEngine.search("safari nonsense", entries: apps).isEmpty)
    }
    func testCommandAliasesAndFilter() throws {
        try expectEqual(SearchEngine.search("undo", entries: SearchEntry.commands).first?.action, .restore)
        try expectTrue(
            SearchEngine.search("safari", entries: apps + SearchEntry.commands, kind: .window).isEmpty)
        try expectEqual(
            SearchEngine.search("", entries: apps + SearchEntry.commands, kind: .window).count,
            WindowAction.allCases.count)
    }
    func testHistoryAndLimit() throws {
        try expectEqual(
            SearchEngine.search("", entries: apps, usage: ["code": 5], limit: 1).map(\.id), ["code"])
        try expectTrue(SearchEngine.search("", entries: apps, limit: 0).isEmpty)
    }
    func testFrequentCommandsRankAboveApps() throws {
        let usage = ["window.centerTwoThirds": 40, "window.minimize": 20, "safari": 10]
        let results = SearchEngine.search("", entries: apps + SearchEntry.commands, usage: usage)
        try expectEqual(
            Array(results.prefix(3).map(\.id)), ["window.centerTwoThirds", "window.minimize", "safari"])
    }
    func testRecentUseBreaksFrequencyTies() throws {
        let usage = ["window.centerTwoThirds": 3, "safari": 3]
        let dates = ["window.centerTwoThirds": 200.0, "safari": 100.0]
        try expectEqual(
            SearchEngine.search(
                "", entries: apps + SearchEntry.commands,
                usage: usage, lastUsed: dates
            ).first?.id, "window.centerTwoThirds")
    }
    func testMinimizeSearch() throws {
        try expectEqual(
            SearchEngine.search("minimise", entries: SearchEntry.commands).first?.action, .minimize)
    }
    func testEmptyAndUnicodeQueries() throws {
        try expectTrue(SearchEngine.search("🚀", entries: apps).isEmpty)
        try expectTrue(SearchEngine.search("anything", entries: []).isEmpty)
    }
    func testSearchBudgetWithOneThousandEntries() throws {
        let entries = (0..<1000).map {
            SearchEntry(
                id: "app\($0)", title: "Application \($0)", subtitle: "Application", kind: .application)
        }
        // Exercise actual ranking at this catalog size. The benchmark script records release timing separately.
        try expectEqual(SearchEngine.search("Application 789", entries: entries).first?.id, "app789")
    }
}

final class GeometryTests {
    let screen = CGRect(x: 0, y: 25, width: 1511, height: 900)
    let current = CGRect(x: 150, y: 160, width: 800, height: 600)

    func testHalvesShareAnExactBoundaryOnOddWidthDisplay() throws {
        let left = WindowAction.leftHalf.frame(in: screen, current: current)
        let right = WindowAction.rightHalf.frame(in: screen, current: current)
        try expectEqual(left.maxX, right.minX)
        try expectEqual(left.width + right.width, screen.width)
        try expectEqual(left.minY, screen.minY)
        try expectEqual(right.maxX, screen.maxX)
    }
    func testAllLayoutsStayInsideUsableArea() throws {
        for action in WindowAction.allCases where action.unitRect != nil {
            let result = action.frame(in: screen, current: current)
            try expectTrue(screen.contains(result), action.rawValue)
            try expectGreaterThan(result.width, 0)
        }
    }
    func testCenterPreservesSize() throws {
        let result = WindowAction.center.frame(in: screen, current: current)
        try expectEqual(result.midX, screen.midX, accuracy: 0.5)
        try expectEqual(result.midY, screen.midY, accuracy: 0.5)
        try expectEqual(result.height, current.height)
    }
    func testCenterClampsOversizedWindow() throws {
        try expectEqual(
            WindowAction.center.frame(in: screen, current: CGRect(x: 0, y: 0, width: 3000, height: 2000)),
            screen)
    }
    func testAppKitConversionWithDisplayAboveAndLeft() throws {
        let above = CGRect(x: -300, y: 1000, width: 1600, height: 900)
        try expectEqual(
            WindowGeometry.accessibilityRect(above, primaryHeight: 1000),
            CGRect(x: -300, y: -900, width: 1600, height: 900))
    }
    func testDisplaySelectionUsesLargestIntersection() throws {
        let displays = [
            CGRect(x: -1000, y: 0, width: 1000, height: 800), CGRect(x: 0, y: 0, width: 1400, height: 900),
        ]
        try expectEqual(
            WindowGeometry.displayIndex(
                for: CGRect(x: -100, y: 50, width: 900, height: 600), displays: displays), 1)
        try expectNil(WindowGeometry.displayIndex(for: current, displays: []))
    }
    func testOffScreenWindowUsesNearestDisplay() throws {
        let displays = [
            CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800),
        ]
        try expectEqual(
            WindowGeometry.displayIndex(
                for: CGRect(x: 2200, y: 200, width: 400, height: 400), displays: displays), 1)
    }
    func testMoveToDisplayPreservesRelativeLayout() throws {
        let source = CGRect(x: -1200, y: 30, width: 1200, height: 800)
        let target = CGRect(x: 0, y: -1000, width: 1600, height: 1000)
        let left = WindowAction.leftHalf.frame(in: source, current: current)
        try expectEqual(
            WindowGeometry.move(left, from: source, to: target),
            CGRect(x: 0, y: -1000, width: 800, height: 1000))
    }
    func testMoveClampsWindowOutsideSource() throws {
        let target = CGRect(x: 0, y: 0, width: 800, height: 600)
        let moved = WindowGeometry.move(
            CGRect(x: -800, y: -100, width: 2500, height: 1500), from: screen, to: target)
        try expectTrue(target.contains(moved))
    }
}

final class CatalogTests {
    func testDiscovery() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ciel-scan-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        func app(_ path: String, id: String, extra: [String: Any] = [:]) throws {
            let url = root.appendingPathComponent(path + "/Contents")
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            var info: [String: Any] = [
                "CFBundleIdentifier": id,
                "CFBundleName": path.components(separatedBy: "/").last!.replacingOccurrences(
                    of: ".app", with: ""),
            ]
            info.merge(extra) { _, new in new }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: url.appendingPathComponent("Info.plist"))
        }
        try app("Nested/Menu Tool.app", id: "menu", extra: ["LSUIElement": true])
        try app("Normal.app", id: "normal")
        try app("Duplicate.app", id: "normal")
        try app("Agent.app", id: "agent", extra: ["LSBackgroundOnly": true])
        try app("Ciel.app", id: "self")
        try app(".Hidden.app", id: "hidden")
        try app("Normal.app/Contents/Helper.app", id: "helper")
        let results = ApplicationScanner.scan(roots: [root], excluding: "self")
        try expectEqual(Set(results.map(\.id)), Set(["app.menu", "app.normal"]))
        try expectEqual(results.first { $0.id == "app.menu" }?.title, "Menu Tool")
    }
}

final class UsageHistoryTests {
    func testPersistenceAndLegacyCounts() throws {
        let suite = "ciel.history.test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["safari": 3], forKey: "usage")
        let history = UsageHistory(defaults: defaults)
        try expectEqual(history.counts["safari"], 3)
        try expectTrue(history.lastUsed.isEmpty)
        history.record("window.centerTwoThirds", at: Date(timeIntervalSince1970: 200))
        history.record("safari", at: Date(timeIntervalSince1970: 100))
        let reopened = UsageHistory(defaults: UserDefaults(suiteName: suite)!)
        try expectEqual(reopened.counts["safari"], 4)
        try expectEqual(reopened.counts["window.centerTwoThirds"], 1)
        try expectEqual(reopened.lastUsed["window.centerTwoThirds"], 200)
        try expectEqual(reopened.lastUsed["safari"], 100)
    }
}
