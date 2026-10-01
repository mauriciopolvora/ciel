import CielCore
import CoreServices
import Foundation
import Testing

@testable import CielApp

@Suite("Application catalog")
struct CatalogTests {
    @Test @MainActor
    func initialEmptyScanFinishesWithoutPublishing() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = AppCatalog(roots: [fixture.root], cacheURL: nil, watchChanges: false)
        var changes = 0
        catalog.onChange = { changes += 1 }
        await refresh(catalog)
        #expect(catalog.entries.isEmpty)
        #expect(changes == 0)
    }

    @Test @MainActor
    func unchangedSnapshotDoesNotRewriteCacheOrPublish() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        try fixture.writeApp(name: "Tool")
        let cache = fixture.root.appendingPathComponent("cache/catalog.json")
        let catalog = AppCatalog(roots: [fixture.root], cacheURL: cache, watchChanges: false)
        var changes = 0
        catalog.onChange = { changes += 1 }
        await refresh(catalog)
        #expect(changes == 1)
        let firstData = try Data(contentsOf: cache)
        let oldDate = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: cache.path)
        await refresh(catalog)
        #expect(changes == 1)
        #expect(try Data(contentsOf: cache) == firstData)
        let attributes = try FileManager.default.attributesOfItem(atPath: cache.path)
        #expect(attributes[.modificationDate] as? Date == oldDate)

        try fixture.writeApp(name: "New Tool")
        await refresh(catalog)
        #expect(changes == 2)
        #expect(catalog.entries.first?.title == "New Tool")
        #expect(try Data(contentsOf: cache) != firstData)
    }

    @Test @MainActor
    func cachedSnapshotStillFinishesItsFirstScan() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        try fixture.writeApp(name: "Tool")
        let cache = fixture.root.appendingPathComponent("catalog.json")
        let expected = ApplicationScanner.scan(roots: [fixture.root])
        try JSONEncoder().encode(expected).write(to: cache)
        let catalog = AppCatalog(roots: [fixture.root], cacheURL: cache, watchChanges: false)
        var changes = 0
        catalog.onChange = { changes += 1 }
        await refresh(catalog)
        #expect(catalog.entries == expected)
        #expect(changes == 0)
    }

    @Test @MainActor
    func refreshRequestsDuringScanCoalesceIntoOneFollowUp() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = AppCatalog(roots: [fixture.root], cacheURL: nil, watchChanges: false)
        var completions = 0
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            catalog.onRefreshFinished = {
                completions += 1
                if completions == 2 { continuation.resume() }
            }
            catalog.refresh()
            catalog.refresh()
            catalog.refresh()
        }
        #expect(completions == 2)
        catalog.onRefreshFinished = nil
    }

    @Test
    func appResourceChangesInvalidateTheBundle() {
        let impact = CatalogEventImpact.classify(
            [CatalogEvent(path: "/Applications/Nested/Tool.app/Contents/Resources/Icon.icns", flags: 0)],
            roots: ["/Applications"])
        #expect(impact.requiresRefresh)
        #expect(impact.appBundles == ["/Applications/Nested/Tool.app"])
        #expect(!impact.invalidateAllIcons)
        #expect(!impact.rebuildWatcher)
    }

    @Test
    func directoryEventsInvalidateAffectedAppsOnly() {
        let impact = CatalogEventImpact.classify(
            [
                CatalogEvent(
                    path: "/Applications/Nested",
                    flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir))
            ],
            roots: ["/Applications"])
        let nested = entry(path: "/Applications/Nested/Tool.app")
        let separate = entry(path: "/Applications/Other.app")
        #expect(impact.requiresRefresh)
        #expect(impact.iconPaths(in: [nested, separate]) == [nested.path!])
        let unrelated = CatalogEventImpact.classify(
            [CatalogEvent(path: "/Applications-Else/Tool.app", flags: 0)], roots: ["/Applications"])
        #expect(!unrelated.requiresRefresh)
    }

    @Test(arguments: [
        kFSEventStreamEventFlagMustScanSubDirs,
        kFSEventStreamEventFlagUserDropped,
        kFSEventStreamEventFlagKernelDropped,
        kFSEventStreamEventFlagEventIdsWrapped,
    ])
    func lostEventsRequireFullRefreshAndInvalidation(flag: Int) {
        let impact = CatalogEventImpact.classify(
            [CatalogEvent(path: "/unrelated", flags: FSEventStreamEventFlags(flag))], roots: ["/Applications"]
        )
        #expect(impact.requiresRefresh)
        #expect(impact.invalidateAllIcons)
        #expect(!impact.rebuildWatcher)
        #expect(impact.iconPaths(in: [entry(path: "/Applications/Tool.app")]) == ["/Applications/Tool.app"])
    }

    @Test
    func rootChangeRebuildsWatcherAndAncestorsRemainRelevant() {
        let movedRoot = CatalogEventImpact.classify(
            [
                CatalogEvent(
                    path: "/old/root", flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged))
            ],
            roots: ["/Applications"])
        #expect(movedRoot.requiresRefresh)
        #expect(movedRoot.invalidateAllIcons)
        #expect(movedRoot.rebuildWatcher)
        let ancestor = CatalogEventImpact.classify(
            [CatalogEvent(path: "/Users/example", flags: 0)], roots: ["/Users/example/Applications"])
        #expect(ancestor.requiresRefresh)
    }

    @Test
    func realPathsInvalidateSymbolicAppPaths() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        try fixture.writeApp(name: "Tool")
        let alias = fixture.root.appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.app)
        let canonical = CatalogPaths.canonical(fixture.app.path)
        let impact = CatalogEventImpact.classify(
            [CatalogEvent(path: canonical + "/Contents/Info.plist", flags: 0)],
            roots: [CatalogPaths.canonical(fixture.root.path)])
        #expect(impact.iconPaths(in: [entry(path: alias.path)]).contains(alias.path))
    }

    @Test
    func sustainedEventsHaveABoundedDebounce() {
        var debounce = CatalogDebounce()
        #expect(debounce.deadline(afterEventAt: 0) == 0.6)
        #expect(debounce.deadline(afterEventAt: 0.5) == 1.1)
        #expect(debounce.deadline(afterEventAt: 1.5) == 2)
        #expect(debounce.deadline(afterEventAt: 2.5) == 2)
        debounce.reset()
        #expect(debounce.deadline(afterEventAt: 5) == 5.6)
    }

    @MainActor
    private func refresh(_ catalog: AppCatalog) async {
        await withCheckedContinuation { continuation in
            catalog.onRefreshFinished = { continuation.resume() }
            catalog.refresh()
        }
        catalog.onRefreshFinished = nil
    }

    private func entry(path: String) -> SearchEntry {
        SearchEntry(id: path, title: "Tool", subtitle: "Application", kind: .application, path: path)
    }
}

private struct CatalogFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ciel-catalog-" + UUID().uuidString)
    var app: URL { root.appendingPathComponent("Nested/Tool.app") }

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func writeApp(name: String) throws {
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "ciel.fixture.catalog", "CFBundleName": name]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
