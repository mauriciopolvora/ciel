import CielCore
import CoreServices
import Foundation

struct CatalogScanRequest: Sendable {
    let roots: [URL]
    let excluding: String?
    let previousEntries: [SearchEntry]
    let cachedEntries: [SearchEntry]?
    let cacheURL: URL?
    let iconImpact: CatalogEventImpact
}

struct CatalogScanResult: Sendable {
    let entries: [SearchEntry]
    let entriesChanged: Bool
    let cacheMatchesResult: Bool
    let invalidatedIconPaths: Set<String>
}

final class CatalogScanWorker: Sendable {
    private let queue = DispatchQueue(label: "app.ciel.catalog", qos: .utility)

    func scan(_ request: CatalogScanRequest) async -> CatalogScanResult {
        await withCheckedContinuation { continuation in
            queue.async {
                let entries = PerformanceTrace.measure("CatalogScan") {
                    ApplicationScanner.scan(roots: request.roots, excluding: request.excluding)
                }
                var cacheMatches = request.cachedEntries == entries
                if !cacheMatches, let cacheURL = request.cacheURL {
                    do {
                        let data = try JSONEncoder().encode(entries)
                        try FileManager.default.createDirectory(
                            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: cacheURL, options: .atomic)
                        cacheMatches = true
                    } catch {
                        NSLog("Ciel: app catalog cache could not be saved: %@", error.localizedDescription)
                    }
                }
                continuation.resume(
                    returning: CatalogScanResult(
                        entries: entries, entriesChanged: entries != request.previousEntries,
                        cacheMatchesResult: cacheMatches,
                        invalidatedIconPaths: request.iconImpact.iconPaths(
                            in: request.previousEntries + entries)))
            }
        }
    }
}

struct CatalogEvent: Sendable {
    let path: String
    let flags: FSEventStreamEventFlags
}

struct CatalogEventImpact: Equatable, Sendable {
    var requiresRefresh = false
    var invalidateAllIcons = false
    var rebuildWatcher = false
    var appBundles: Set<String> = []
    var directories: Set<String> = []

    static func classify(_ events: [CatalogEvent], roots: [String]) -> Self {
        let lostEvents = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped)
        let rootChanged = FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
        var result = Self()
        for event in events {
            if event.flags & (lostEvents | rootChanged) != 0 {
                result.requiresRefresh = true
                result.invalidateAllIcons = true
                result.rebuildWatcher = result.rebuildWatcher || event.flags & rootChanged != 0
                continue
            }
            guard roots.contains(where: { CatalogPaths.overlap($0, event.path) }) else { continue }
            result.requiresRefresh = true
            if let bundle = CatalogPaths.appBundle(containing: event.path, roots: roots) {
                result.appBundles.insert(bundle)
            } else {
                // A directory event can cover several installed, removed, or renamed apps.
                result.directories.insert(event.path)
            }
        }
        return result
    }

    mutating func merge(_ other: Self) {
        requiresRefresh = requiresRefresh || other.requiresRefresh
        invalidateAllIcons = invalidateAllIcons || other.invalidateAllIcons
        rebuildWatcher = rebuildWatcher || other.rebuildWatcher
        appBundles.formUnion(other.appBundles)
        directories.formUnion(other.directories)
    }

    func iconPaths(in entries: [SearchEntry]) -> Set<String> {
        guard invalidateAllIcons || !appBundles.isEmpty || !directories.isEmpty else { return [] }
        let paths = Set(entries.compactMap(\.path))
        if invalidateAllIcons { return paths }
        return appBundles.union(
            paths.filter { path in
                let canonical = CatalogPaths.canonical(path)
                return appBundles.contains(canonical)
                    || directories.contains { CatalogPaths.contains($0, canonical) }
            })
    }
}

struct CatalogDebounce {
    private var firstEvent: TimeInterval?
    private let quietDelay: TimeInterval = 0.6
    private let maximumDelay: TimeInterval = 2

    mutating func deadline(afterEventAt now: TimeInterval) -> TimeInterval {
        let first = firstEvent ?? now
        firstEvent = first
        return min(now + quietDelay, first + maximumDelay)
    }

    mutating func reset() { firstEvent = nil }
}

enum CatalogPaths {
    static func contains(_ parent: String, _ path: String) -> Bool {
        parent == "/" || path == parent || path.hasPrefix(parent + "/")
    }

    static func overlap(_ a: String, _ b: String) -> Bool { contains(a, b) || contains(b, a) }

    static func appBundle(containing path: String, roots: [String]) -> String? {
        var components: [Substring] = []
        for component in path.split(separator: "/") {
            components.append(component)
            if component.lowercased().hasSuffix(".app") {
                let bundle = "/" + components.joined(separator: "/")
                if roots.contains(where: { contains($0, bundle) }) { return bundle }
            }
        }
        return nil
    }

    static func canonical(_ path: String) -> String {
        guard path.hasPrefix("/") else { return canonical(URL(fileURLWithPath: path).path) }
        // URL.resolvingSymlinksInPath hides /private on macOS. FSEvents uses the real path.
        if let resolved = realpath(path, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        guard path != "/" else { return path }
        let parent = (path as NSString).deletingLastPathComponent
        let prefix = canonical(parent)
        return (prefix == "/" ? prefix : prefix + "/") + (path as NSString).lastPathComponent
    }
}
