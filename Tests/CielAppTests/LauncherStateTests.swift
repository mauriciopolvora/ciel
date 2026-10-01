import CielCore
import Testing

@testable import CielApp

@MainActor @Suite("Launcher state")
struct LauncherStateTests {
    private let applications = [
        SearchEntry(id: "calculator", title: "Calculator", subtitle: "Applications", kind: .application),
        SearchEntry(id: "calendar", title: "Calendar", subtitle: "Applications", kind: .application),
        SearchEntry(id: "calibre", title: "Calibre", subtitle: "Applications", kind: .application),
    ]

    @Test(arguments: ["", "   ", "\n\t"])
    func blankQueryHasNoSuggestions(_ query: String) {
        let state = LauncherState()
        state.update(entries: applications + SearchEntry.commands, usage: ["calculator": 8], lastUsed: [:])
        state.setQuery(query)
        state.selectFilter(1)
        #expect(!state.hasQuery)
        #expect(state.results.isEmpty)
        #expect(state.selectedEntry == nil)
        #expect(state.entry(at: 0) == nil)
        state.updateEntries(applications + SearchEntry.commands)
        #expect(state.results.isEmpty)
    }

    @Test func filterRetainsQueryAndSelectsOnlyMatchingKind() {
        let state = LauncherState()
        let entries = [
            SearchEntry(id: "notes", title: "Left Notes", subtitle: "Applications", kind: .application),
            SearchEntry(
                id: "half", title: "Left Half", subtitle: "Window Management", kind: .window,
                action: .leftHalf),
            SearchEntry(id: "tools", title: "Left Tools", subtitle: "Preferences", kind: .utility),
        ]
        state.updateEntries(entries)
        state.setQuery("left")
        #expect(Set(state.results.map(\.id)) == Set(["notes", "half", "tools"]))
        state.selectFilter(1)
        #expect(state.query == "left")
        #expect(state.results.map(\.id) == ["notes"])
        state.selectFilter(2)
        #expect(state.query == "left")
        #expect(state.results.map(\.id) == ["half"])
        state.selectFilter(0)
        #expect(state.query == "left")
        #expect(state.results.count == 3)
    }

    @Test func equivalentQueryKeepsResultsButResetsSelection() {
        let state = LauncherState()
        state.updateEntries(applications)
        state.setQuery("cal")
        state.select(index: 2)
        let change = state.setQuery("cal ")
        #expect(change.queryChanged)
        #expect(!change.resultsChanged)
        #expect(change.selectionChanged)
        #expect(state.selectedIndex == 0)
        #expect(state.setQuery("cal ").isEmpty)
    }

    @Test func catalogRefreshPreservesSelectedIdentityAcrossReordering() {
        let state = LauncherState()
        state.updateEntries(applications)
        state.setQuery("cal")
        state.select(index: state.results.firstIndex { $0.id == "calendar" })
        let oldIndex = state.selectedIndex
        let added = SearchEntry(id: "new", title: "Cal Apple", subtitle: "Applications", kind: .application)
        let change = state.updateEntries(applications + [added])
        #expect(change.resultsChanged)
        #expect(state.selectedEntry?.id == "calendar")
        #expect(state.selectedIndex != oldIndex)
    }

    @Test func catalogRemovalFallsBackToFirstResultThenClearsSelection() {
        let state = LauncherState()
        state.updateEntries(applications)
        state.setQuery("cal")
        state.select(index: state.results.firstIndex { $0.id == "calendar" })
        state.updateEntries(applications.filter { $0.id != "calendar" })
        #expect(state.selectedIndex == 0)
        #expect(state.selectedEntry?.id == state.results.first?.id)
        state.updateEntries([])
        #expect(state.selectedIndex == nil)
        #expect(state.results.isEmpty)
    }

    @Test func contentChangesWithSameIdentityRequireRowRefresh() {
        let state = LauncherState()
        let before = SearchEntry(
            id: "app", title: "Calculator", subtitle: "Old folder", kind: .application,
            path: "/Old/Calculator.app")
        let after = SearchEntry(
            id: "app", title: "Calculator", subtitle: "New folder", kind: .application,
            path: "/New/Calculator.app")
        state.updateEntries([before])
        state.setQuery("calc")
        let change = state.updateEntries([after])
        #expect(change.resultsChanged)
        #expect(state.selectedEntry == after)
        #expect(state.updateEntries([after]).isEmpty)
    }

    @Test func historyChangesRankResultsAndPreserveSelectedEntry() {
        let state = LauncherState()
        state.updateEntries(applications)
        state.setQuery("cal")
        state.select(index: state.results.firstIndex { $0.id == "calendar" })
        let change = state.updateUsage(["calibre": 10], lastUsed: ["calibre": 100])
        #expect(change.resultsChanged)
        #expect(state.results.first?.id == "calibre")
        #expect(state.selectedEntry?.id == "calendar")
        #expect(state.updateUsage(["calibre": 10], lastUsed: ["calibre": 100]).isEmpty)
        let unrelated = state.updateUsage(
            ["calibre": 10, "unmatched": 2], lastUsed: ["calibre": 100, "unmatched": 200])
        #expect(unrelated.isEmpty)
    }

    @Test func recencyBreaksEqualUsageTiesWithoutLosingSelection() {
        let state = LauncherState()
        state.update(entries: applications, usage: ["calendar": 5, "calibre": 5], lastUsed: [:])
        state.setQuery("cal")
        state.select(index: state.results.firstIndex { $0.id == "calendar" })
        state.updateUsage(["calendar": 5, "calibre": 5], lastUsed: ["calendar": 10, "calibre": 20])
        #expect(state.results.first?.id == "calibre")
        #expect(state.selectedEntry?.id == "calendar")
    }

    @Test func arrowSelectionStaysInBoundsAndQuickOpenRejectsInvalidRows() {
        let state = LauncherState()
        state.moveSelection(1)
        #expect(state.selectedIndex == nil)
        state.updateEntries(applications)
        state.setQuery("cal")
        state.moveSelection(-1)
        #expect(state.selectedIndex == 0)
        state.moveSelection(20)
        #expect(state.selectedIndex == 2)
        #expect(state.entry(at: -1) == nil)
        #expect(state.entry(at: 3) == nil)
        state.select(index: -1)
        state.moveSelection(1)
        #expect(state.selectedIndex == 0)
    }

    @Test func resetClearsQueryCategoryResultsAndSelection() {
        let state = LauncherState()
        state.updateEntries(applications)
        state.setQuery("cal")
        state.selectFilter(1)
        state.moveSelection(1)
        let change = state.reset()
        #expect(change.resultsChanged)
        #expect(state.query.isEmpty)
        #expect(state.filter == nil)
        #expect(state.results.isEmpty)
        #expect(state.selectedIndex == nil)
        #expect(state.reset().isEmpty)
    }
}
