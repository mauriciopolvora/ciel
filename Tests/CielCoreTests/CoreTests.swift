import CielCore
import CoreGraphics
import Foundation
import Testing

@Suite
struct SearchTests {
    let apps = [
        SearchEntry(id: "safari", title: "Safari", subtitle: "Application", kind: .application),
        SearchEntry(id: "code", title: "Visual Studio Code", subtitle: "Application", kind: .application),
        SearchEntry(id: "cafe", title: "Café", subtitle: "Application", kind: .application),
    ]

    @Test
    func testExactMatchOutranksFrequentlyUsedPrefix() {
        let other = SearchEntry(
            id: "safari-tech", title: "Safari Technology Preview", subtitle: "Application", kind: .application
        )
        #expect(
            SearchEngine.search("safari", entries: apps + [other], usage: [other.id: 1000]).first?.id
                == "safari")
    }
    @Test
    func testAbbreviations() {
        #expect(SearchEngine.search("vsc", entries: apps).first?.id == "code")
    }
    @Test
    func testTypingErrors() {
        let calculator = SearchEntry(
            id: "calculator", title: "Calculator", subtitle: "Application", kind: .application)
        #expect(SearchEngine.search("safrai", entries: apps).first?.id == "safari")
        #expect(SearchEngine.search("calclator", entries: apps + [calculator]).first?.id == "calculator")
        #expect(SearchEngine.search("zz", entries: apps).isEmpty)
    }
    @Test
    func testReorderedTokens() {
        #expect(SearchEngine.search("code visual", entries: apps).first?.id == "code")
    }
    @Test
    func testCaseAccentsAndWhitespace() {
        #expect(SearchEngine.search("  CAFE  ", entries: apps).first?.id == "cafe")
    }
    @Test
    func testAllTokensMustMatch() {
        #expect(SearchEngine.search("safari nonsense", entries: apps).isEmpty)
    }
    @Test
    func testCommandAliasesAndFilter() {
        #expect(SearchEngine.search("undo", entries: SearchEntry.commands).first?.action == .restore)
        #expect(SearchEngine.search("safari", entries: apps + SearchEntry.commands, kind: .window).isEmpty)
        #expect(
            SearchEngine.search("", entries: apps + SearchEntry.commands, kind: .window).count
                == WindowAction.allCases.count)
    }
    @Test
    func testHistoryAndLimit() {
        #expect(SearchEngine.search("", entries: apps, usage: ["code": 5], limit: 1).map(\.id) == ["code"])
        #expect(SearchEngine.search("", entries: apps, limit: 0).isEmpty)
    }
    @Test
    func testFrequentCommandsRankAboveApps() {
        let usage = ["window.centerTwoThirds": 40, "window.minimize": 20, "safari": 10]
        let results = SearchEngine.search("", entries: apps + SearchEntry.commands, usage: usage)
        #expect(
            Array(results.prefix(3).map(\.id)) == ["window.centerTwoThirds", "window.minimize", "safari"])
    }
    @Test
    func testRecentUseBreaksFrequencyTies() {
        let usage = ["window.centerTwoThirds": 3, "safari": 3]
        let dates = ["window.centerTwoThirds": 200.0, "safari": 100.0]
        #expect(
            SearchEngine.search(
                "", entries: apps + SearchEntry.commands,
                usage: usage, lastUsed: dates
            ).first?.id == "window.centerTwoThirds")
    }
    @Test
    func testMinimizeSearch() {
        #expect(SearchEngine.search("minimise", entries: SearchEntry.commands).first?.action == .minimize)
    }
    @Test
    func testEmptyAndUnicodeQueries() {
        #expect(SearchEngine.search("🚀", entries: apps).isEmpty)
        #expect(SearchEngine.search("anything", entries: []).isEmpty)
    }
    @Test
    func testRankingWithOneThousandEntries() {
        let entries = (0..<1000).map {
            SearchEntry(
                id: "app\($0)", title: "Application \($0)", subtitle: "Application", kind: .application)
        }
        // Exercise actual ranking at this catalog size. The benchmark script records release timing separately.
        #expect(SearchEngine.search("Application 789", entries: entries).first?.id == "app789")
    }
}

@Suite
struct GeometryTests {
    let screen = CGRect(x: 0, y: 25, width: 1511, height: 900)
    let current = CGRect(x: 150, y: 160, width: 800, height: 600)

    @Test
    func testHalvesShareAnExactBoundaryOnOddWidthDisplay() {
        let left = WindowAction.leftHalf.frame(in: screen, current: current)
        let right = WindowAction.rightHalf.frame(in: screen, current: current)
        #expect(left.maxX == right.minX)
        #expect(left.width + right.width == screen.width)
        #expect(left.minY == screen.minY)
        #expect(right.maxX == screen.maxX)
    }
    @Test
    func testAllLayoutsStayInsideUsableArea() {
        for action in WindowAction.allCases where action.unitRect != nil {
            let result = action.frame(in: screen, current: current)
            #expect(screen.contains(result), "\(action.rawValue)")
            #expect(result.width > 0)
        }
    }
    @Test
    func testCenterPreservesSize() {
        let result = WindowAction.center.frame(in: screen, current: current)
        #expect(abs(result.midX - screen.midX) <= 0.5)
        #expect(abs(result.midY - screen.midY) <= 0.5)
        #expect(result.height == current.height)
    }
    @Test
    func testCenterClampsOversizedWindow() {
        #expect(
            WindowAction.center.frame(in: screen, current: CGRect(x: 0, y: 0, width: 3000, height: 2000))
                == screen)
    }
    @Test
    func testAppKitConversionWithDisplayAboveAndLeft() {
        let above = CGRect(x: -300, y: 1000, width: 1600, height: 900)
        #expect(
            WindowGeometry.accessibilityRect(above, primaryHeight: 1000)
                == CGRect(x: -300, y: -900, width: 1600, height: 900))
    }
    @Test
    func testDisplaySelectionUsesLargestIntersection() {
        let displays = [
            CGRect(x: -1000, y: 0, width: 1000, height: 800), CGRect(x: 0, y: 0, width: 1400, height: 900),
        ]
        #expect(
            WindowGeometry.displayIndex(
                for: CGRect(x: -100, y: 50, width: 900, height: 600), displays: displays) == 1)
        #expect(WindowGeometry.displayIndex(for: current, displays: []) == nil)
    }
    @Test
    func testOffScreenWindowUsesNearestDisplay() {
        let displays = [
            CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800),
        ]
        #expect(
            WindowGeometry.displayIndex(
                for: CGRect(x: 2200, y: 200, width: 400, height: 400), displays: displays) == 1)
    }
    @Test
    func testMoveToDisplayPreservesRelativeLayout() {
        let source = CGRect(x: -1200, y: 30, width: 1200, height: 800)
        let target = CGRect(x: 0, y: -1000, width: 1600, height: 1000)
        let left = WindowAction.leftHalf.frame(in: source, current: current)
        #expect(
            WindowGeometry.move(left, from: source, to: target)
                == CGRect(x: 0, y: -1000, width: 800, height: 1000))
    }
    @Test
    func testMoveClampsWindowOutsideSource() {
        let target = CGRect(x: 0, y: 0, width: 800, height: 600)
        let moved = WindowGeometry.move(
            CGRect(x: -800, y: -100, width: 2500, height: 1500), from: screen, to: target)
        #expect(target.contains(moved))
    }
}

@Suite
struct CatalogTests {
    @Test
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
        #expect(Set(results.map(\.id)) == Set(["app.menu", "app.normal"]))
        #expect(results.first { $0.id == "app.menu" }?.title == "Menu Tool")
    }
}

@Suite
struct UsageHistoryTests {
    @Test
    func testPersistenceAndLegacyCounts() {
        let suite = "ciel.history.test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["safari": 3], forKey: "usage")
        let history = UsageHistory(defaults: defaults)
        #expect(history.counts["safari"] == 3)
        #expect(history.lastUsed.isEmpty)
        history.record("window.centerTwoThirds", at: Date(timeIntervalSince1970: 200))
        history.record("safari", at: Date(timeIntervalSince1970: 100))
        let reopened = UsageHistory(defaults: UserDefaults(suiteName: suite)!)
        #expect(reopened.counts["safari"] == 4)
        #expect(reopened.counts["window.centerTwoThirds"] == 1)
        #expect(reopened.lastUsed["window.centerTwoThirds"] == 200)
        #expect(reopened.lastUsed["safari"] == 100)
    }
}
