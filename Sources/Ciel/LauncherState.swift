import CielCore
import Foundation

/// Owns launcher transitions independently of AppKit drawing and input controls.
@MainActor final class LauncherState {
    struct Change: Equatable {
        var queryChanged = false
        var hasQueryChanged = false
        var filterChanged = false
        var resultsChanged = false
        var selectionChanged = false

        var isEmpty: Bool {
            !queryChanged && !hasQueryChanged && !filterChanged && !resultsChanged && !selectionChanged
        }

        static let initial = Change(hasQueryChanged: true, filterChanged: true, selectionChanged: true)
    }

    private(set) var query = ""
    private(set) var filter: SearchEntry.Kind?
    private(set) var results: [SearchEntry] = []
    private(set) var selectedIndex: Int?
    private var entries: [SearchEntry] = []
    private var usage: [String: Int] = [:]
    private var lastUsed: [String: Double] = [:]

    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var selectedEntry: SearchEntry? { selectedIndex.map { results[$0] } }

    @discardableResult
    func update(
        entries: [SearchEntry], usage: [String: Int], lastUsed: [String: Double]
    ) -> Change {
        guard self.entries != entries || self.usage != usage || self.lastUsed != lastUsed else {
            return Change()
        }
        return transition(preserveSelection: true) {
            self.entries = entries
            self.usage = usage
            self.lastUsed = lastUsed
        }
    }

    @discardableResult
    func updateUsage(_ usage: [String: Int], lastUsed: [String: Double]) -> Change {
        update(entries: entries, usage: usage, lastUsed: lastUsed)
    }

    @discardableResult
    func updateEntries(_ entries: [SearchEntry]) -> Change {
        update(entries: entries, usage: usage, lastUsed: lastUsed)
    }

    @discardableResult
    func setQuery(_ query: String, preserveSelection: Bool = false) -> Change {
        guard self.query != query else { return Change() }
        return transition(preserveSelection: preserveSelection) { self.query = query }
    }

    @discardableResult
    func selectFilter(_ index: Int, query: String? = nil) -> Change {
        let kind: SearchEntry.Kind? = index == 1 ? .application : index == 2 ? .window : nil
        let nextQuery = query ?? self.query
        guard filter != kind || self.query != nextQuery else { return Change() }
        return transition(preserveSelection: false) {
            filter = kind
            self.query = nextQuery
        }
    }

    @discardableResult
    func reset() -> Change {
        guard !query.isEmpty || filter != nil || selectedIndex != nil else { return Change() }
        return transition(preserveSelection: false) {
            query = ""
            filter = nil
        }
    }

    @discardableResult
    func select(index: Int?) -> Change {
        let nextIndex = index.flatMap { results.indices.contains($0) ? $0 : nil }
        guard selectedIndex != nextIndex else { return Change() }
        selectedIndex = nextIndex
        return Change(selectionChanged: true)
    }

    @discardableResult
    func moveSelection(_ delta: Int) -> Change {
        guard !results.isEmpty else { return Change() }
        return select(index: min(max((selectedIndex ?? -1) + delta, 0), results.count - 1))
    }

    func entry(at index: Int) -> SearchEntry? {
        results.indices.contains(index) ? results[index] : nil
    }

    private func transition(preserveSelection: Bool, update: () -> Void) -> Change {
        let previousQuery = query
        let previousHasQuery = hasQuery
        let previousFilter = filter
        let previousResults = results
        let previousIndex = selectedIndex
        let selectedID = preserveSelection ? selectedEntry?.id : nil
        update()
        results =
            hasQuery
            ? PerformanceTrace.measure("Search") {
                SearchEngine.search(query, entries: entries, kind: filter, usage: usage, lastUsed: lastUsed)
            }
            : []
        selectedIndex =
            results.isEmpty
            ? nil : selectedID.flatMap { id in results.firstIndex { $0.id == id } } ?? 0
        return Change(
            queryChanged: previousQuery != query,
            hasQueryChanged: previousHasQuery != hasQuery,
            filterChanged: previousFilter != filter,
            resultsChanged: previousResults != results,
            selectionChanged: previousIndex != selectedIndex)
    }
}
