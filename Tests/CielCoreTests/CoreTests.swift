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
    let notes = [
        SearchEntry(id: "alpha", title: "Notes Alpha", subtitle: "Application", kind: .application),
        SearchEntry(id: "beta", title: "Notes Beta", subtitle: "Application", kind: .application),
    ]

    @Test
    func testExactMatchOutranksFrequentlyUsedPrefix() {
        let other = SearchEntry(
            id: "safari-tech", title: "Safari Technology Preview", subtitle: "Application", kind: .application
        )
        #expect(
            SearchEngine.search("safari", entries: apps + [other], usage: Usage(counts: [other.id: 1000]))
                .first?.id
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
            SearchEngine.search("window", entries: apps + SearchEntry.commands, kind: .window).count
                == WindowAction.allCases.count)
    }
    @Test
    func testHistoryAndLimit() {
        #expect(
            SearchEngine.search("notes", entries: notes, usage: Usage(counts: ["beta": 5]), limit: 1).map(
                \.id) == ["beta"])
        #expect(SearchEngine.search("notes", entries: notes, limit: 0).isEmpty)
    }
    @Test
    func testRecentUseBreaksFrequencyTies() {
        let usage = Usage(counts: ["alpha": 3, "beta": 3], lastUsed: ["alpha": 100, "beta": 200])
        #expect(SearchEngine.search("notes", entries: notes, usage: usage).first?.id == "beta")
    }
    @Test
    func testMinimizeSearch() {
        #expect(SearchEngine.search("minimise", entries: SearchEntry.commands).first?.action == .minimize)
    }
    @Test
    func testEmptyAndUnicodeQueries() {
        #expect(SearchEngine.search("", entries: apps, usage: Usage(counts: ["code": 5])).isEmpty)
        #expect(SearchEngine.search("   ", entries: apps).isEmpty)
        #expect(SearchEngine.search("🚀", entries: apps).isEmpty)
        #expect(SearchEngine.search("anything", entries: []).isEmpty)
    }
    @Test
    func testRankingWithOneThousandEntries() {
        let entries = (0..<1000).map {
            SearchEntry(
                id: "app\($0)", title: "Application \($0)", subtitle: "Application", kind: .application)
        }
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
    func testCenterThreeFourthsCentersWidth() {
        let action = WindowAction.centerThreeFourths
        #expect(WindowAction(rawValue: "centerThreeFourths") == action)
        #expect(action.title == "Center Three Fourths")
        let visible = CGRect(x: -1600, y: 25, width: 1600, height: 900)
        let result = action.frame(in: visible, current: current)
        #expect(result == CGRect(x: -1400, y: 25, width: 1200, height: 900))
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
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ciel-scan-" + UUID().uuidString)

    func writeBundle(_ path: String, info: [String: Any]) throws {
        let url = root.appendingPathComponent(path + "/Contents")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Info.plist"))
    }

    @Test
    func testDiscovery() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        func app(_ path: String, id: String, extra: [String: Any] = [:]) throws {
            var info: [String: Any] = [
                "CFBundleIdentifier": id,
                "CFBundleName": path.components(separatedBy: "/").last!.replacingOccurrences(
                    of: ".app", with: ""),
            ]
            info.merge(extra) { _, new in new }
            try writeBundle(path, info: info)
        }
        try app("Nested/Menu Tool.app", id: "menu", extra: ["LSUIElement": true])
        try app(
            "BetterDisplay.app", id: "betterdisplay",
            extra: ["LSBackgroundOnly": true, "LSUIElement": true])
        try app("Normal.app", id: "normal")
        try app("Duplicate.app", id: "normal")
        try app("Agent.app", id: "agent", extra: ["LSBackgroundOnly": true])
        try app("Ciel.app", id: "self")
        try app(".Hidden.app", id: "hidden")
        try app("Normal.app/Contents/Helper.app", id: "helper")
        let results = ApplicationScanner.scan(roots: [root], excluding: "self")
        #expect(Set(results.map(\.id)) == Set(["app.menu", "app.betterdisplay", "app.normal"]))
        #expect(results.first { $0.id == "app.menu" }?.title == "Menu Tool")
        #expect(SearchEngine.search("bet", entries: results).first?.id == "app.betterdisplay")
    }

    @Test
    func testInfoPlistShapes() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let shapes: [(app: String, info: [String: Any], listed: Bool)] = [
            (
                "Normal",
                [
                    "CFBundleIdentifier": "normal", "CFBundleName": "Normal",
                    "CFBundleDisplayName": "Normal App",
                ], true
            ),
            ("FolderActionsDispatcher", ["CFBundleIdentifier": "agent", "LSBackgroundOnly": true], false),
            (
                "BetterDisplay",
                ["CFBundleIdentifier": "betterdisplay", "LSBackgroundOnly": true, "LSUIElement": true], true
            ),
            (
                "VoiceOver",
                ["CFBundleIdentifier": "voiceover", "LSBackgroundOnly": true, "LSUIElement": "1"], true
            ),
            ("AltTab", ["CFBundleIdentifier": "alttab", "LSUIElement": "true"], true),
            ("PIPAgent", ["CFBundleIdentifier": "pipagent", "LSUIElement": "YES"], true),
            ("Database Events", ["CFBundleIdentifier": "databaseevents", "LSBackgroundOnly": "1"], false),
            (
                "System Events",
                ["CFBundleIdentifier": "systemevents", "LSBackgroundOnly": "0", "LSUIElement": "1"], true
            ),
            ("FluidVoice", ["CFBundleIdentifier": "fluidvoice", "LSUIElement": false], true),
            ("No Identifier", ["CFBundleName": "No Identifier"], false),
        ]
        for shape in shapes { try writeBundle(shape.app + ".app", info: shape.info) }
        let titles = Dictionary(
            uniqueKeysWithValues: ApplicationScanner.scan(roots: [root]).map { ($0.id, $0.title) })
        let listed = shapes.filter(\.listed).map { "app." + ($0.info["CFBundleIdentifier"] as? String ?? "") }
        #expect(Set(titles.keys) == Set(listed))
        #expect(titles["app.normal"] == "Normal App")
        #expect(titles["app.systemevents"] == "System Events")
    }
}

@Suite
struct LearnedRankingTests {
    let entries =
        SearchEntry.commands + [
            SearchEntry(id: "finder", title: "Finder", subtitle: "Application", kind: .application),
            SearchEntry(id: "facetime", title: "FaceTime", subtitle: "Application", kind: .application),
        ]
    let firstThreeFourths = WindowAction.firstThreeFourths.id

    func top(_ query: String, _ picks: [(String, String)]) -> String? {
        let usage = Usage(picks: picks.map { Usage.Pick(query: $0.0, id: $0.1) })
        return SearchEngine.search(query, entries: entries, usage: usage).first?.id
    }

    @Test
    func aPickRanksFirstForEveryStartOfTheQueryItWasPickedFor() {
        #expect(top("f", []) != firstThreeFourths)
        #expect(top("f", [("first t", firstThreeFourths)]) == firstThreeFourths)
        #expect(top("fir", [("first t", firstThreeFourths)]) == firstThreeFourths)
        #expect(top("first t", [("first t", firstThreeFourths)]) == firstThreeFourths)
    }

    @Test
    func aPickRecordedThroughHistoryRanksForTheTypedText() {
        let suite = "ciel.history.test." + UUID().uuidString
        defer { UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite) }
        let history = UsageHistory(defaults: UserDefaults(suiteName: suite)!)
        history.record(firstThreeFourths, query: " First  T")
        #expect(
            SearchEngine.search("F", entries: entries, usage: history.usage).first?.id == firstThreeFourths)
    }

    @Test
    func aPickDoesNotRankForAQueryItDoesNotStartWith() {
        #expect(top("fa", [("first t", firstThreeFourths)]) == "facetime")
    }

    @Test
    func theEntryPickedMoreOftenForTheTypedTextWins() {
        let picks = [
            ("fin", "finder"), ("fin", "finder"), ("fin", "finder"), ("first", firstThreeFourths),
        ]
        #expect(top("f", picks) == "finder")
        #expect(top("fir", picks) == firstThreeFourths)
    }

    @Test
    func anExactTitleOutranksALearnedEntry() {
        let entries = [
            SearchEntry(id: "codex", title: "Codex", subtitle: "Application", kind: .application),
            SearchEntry(id: "code", title: "Code", subtitle: "Application", kind: .application),
        ]
        let usage = Usage(picks: [Usage.Pick(query: "codex", id: "codex")])
        #expect(SearchEngine.search("code", entries: entries, usage: usage).map(\.id) == ["code", "codex"])
        #expect(SearchEngine.search("cod", entries: entries, usage: usage).first?.id == "codex")
        let spaced = [
            SearchEntry(id: "plus", title: "Quick  Notes Plus", subtitle: "Application", kind: .application),
            SearchEntry(id: "quick", title: "Quick  Notes", subtitle: "Application", kind: .application),
        ]
        let picked = Usage(picks: [Usage.Pick(query: "quick notes plus", id: "plus")])
        #expect(SearchEngine.search("Quick  Notes", entries: spaced, usage: picked).first?.id == "quick")
    }

    @Test
    func aLearnedEntryThatNoLongerMatchesTheTextIsNotReturned() {
        let renamed = SearchEntry(id: "finder", title: "Photos", subtitle: "Application", kind: .application)
        let usage = Usage(picks: [Usage.Pick(query: "fin", id: "finder")])
        #expect(SearchEngine.search("fin", entries: [renamed], usage: usage).isEmpty)
    }
}

@Suite
struct UsageHistoryTests {
    func withDefaults(_ body: (String) -> Void) {
        let suite = "ciel.history.test." + UUID().uuidString
        defer { UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite) }
        body(suite)
    }

    @Test
    func testPersistenceAndLegacyCounts() {
        withDefaults { suite in
            let defaults = UserDefaults(suiteName: suite)!
            defaults.set(["safari": 3], forKey: "usage")
            let history = UsageHistory(defaults: defaults)
            #expect(history.usage.counts["safari"] == 3)
            #expect(history.usage.lastUsed.isEmpty)
            history.record("window.centerThreeFourths", at: Date(timeIntervalSince1970: 200))
            history.record("safari", at: Date(timeIntervalSince1970: 100))
            let reopened = UsageHistory(defaults: UserDefaults(suiteName: suite)!)
            #expect(reopened.usage.counts["safari"] == 4)
            #expect(reopened.usage.counts["window.centerThreeFourths"] == 1)
            #expect(reopened.usage.lastUsed["window.centerThreeFourths"] == 200)
            #expect(reopened.usage.lastUsed["safari"] == 100)
            #expect(reopened.usage.picks.isEmpty)
        }
    }

    @Test
    func picksPersistNormalizedAndBlankQueriesStoreNone() {
        withDefaults { suite in
            let history = UsageHistory(defaults: UserDefaults(suiteName: suite)!)
            history.record("window.firstThreeFourths", query: "  First   T ")
            history.record("safari", query: "   ")
            history.record("safari", query: "")
            history.record("safari")
            let reopened = UsageHistory(defaults: UserDefaults(suiteName: suite)!)
            #expect(reopened.usage.picks == [Usage.Pick(query: "first t", id: "window.firstThreeFourths")])
            #expect(reopened.usage.counts["safari"] == 3)
        }
    }

    @Test
    func picksKeepOnlyTheNewestFiveHundred() {
        withDefaults { suite in
            let history = UsageHistory(defaults: UserDefaults(suiteName: suite)!)
            for index in 0...UsageHistory.pickLimit { history.record("app\(index)", query: "a") }
            let picks = UsageHistory(defaults: UserDefaults(suiteName: suite)!).usage.picks
            #expect(picks.count == 500)
            #expect(picks.first?.id == "app1")
            #expect(picks.last?.id == "app500")
        }
    }

    @Test
    func storedPicksReadBackAndMalformedRowsAreSkipped() {
        withDefaults { suite in
            let defaults = UserDefaults(suiteName: suite)!
            defaults.set(
                [["query": "f", "id": "x"], ["query": "g"], ["query": 1, "id": "y"], "z"], forKey: "picks")
            #expect(UsageHistory(defaults: defaults).usage.picks == [Usage.Pick(query: "f", id: "x")])
        }
    }
}
