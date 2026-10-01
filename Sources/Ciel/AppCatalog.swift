import AppKit
import CielCore
import CoreServices

@MainActor
final class AppCatalog {
    private(set) var entries: [SearchEntry] = []
    var onChange: (() -> Void)?
    var onRefreshFinished: (() -> Void)?
    var onIconsInvalidated: ((Set<String>) -> Void)?

    private let worker = CatalogScanWorker()
    private let roots: [URL]
    private let cacheURL: URL?
    private let watchChanges: Bool
    private var canonicalRoots: [String]
    private var cachedEntries: [SearchEntry]?
    private var watcher: CatalogWatcher?
    private var pending: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var debounce = CatalogDebounce()
    private var pendingImpact = CatalogEventImpact()
    private var scanning = false
    private var rescanRequested = false

    convenience init(roots: [URL] = ApplicationScanner.defaultRoots, useCache: Bool = true) {
        // Keep the existing production path. A separate diagnostic app identity
        // must not read or overwrite the installed app's catalog cache.
        let identifier = Bundle.main.bundleIdentifier ?? "app.mauriciopolvora.jumpstart"
        let cacheURL =
            useCache
            ? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(identifier).appendingPathComponent("apps.json") : nil
        self.init(roots: roots, cacheURL: cacheURL, watchChanges: true)
    }

    // An explicit cache and disabled watcher keep unit checks separate from user files.
    init(roots: [URL], cacheURL: URL?, watchChanges: Bool) {
        self.roots = roots
        self.cacheURL = cacheURL
        self.watchChanges = watchChanges
        canonicalRoots = roots.map { CatalogPaths.canonical($0.path) }
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
            let saved = try? JSONDecoder().decode([SearchEntry].self, from: data)
        {
            entries = saved
            cachedEntries = saved
        }
        watch()
    }

    deinit {
        pending?.cancel()
        scanTask?.cancel()
    }

    func refresh() {
        // A manual refresh also consumes events already queued by the watcher.
        pending?.cancel()
        pending = nil
        debounce.reset()
        guard !scanning else {
            rescanRequested = true
            return
        }
        scanning = true
        let impact = pendingImpact
        pendingImpact = CatalogEventImpact()
        if impact.rebuildWatcher { watch() }
        let request = CatalogScanRequest(
            roots: roots, excluding: Bundle.main.bundleIdentifier, previousEntries: entries,
            cachedEntries: cachedEntries, cacheURL: cacheURL, iconImpact: impact)
        let worker = worker
        scanTask = Task { [weak self] in
            let result = await worker.scan(request)
            guard !Task.isCancelled, let self else { return }
            self.complete(result)
        }
    }

    private func complete(_ result: CatalogScanResult) {
        if result.cacheMatchesResult { cachedEntries = result.entries }
        if result.entriesChanged { entries = result.entries }
        let needsRescan = rescanRequested
        rescanRequested = false
        scanning = false
        scanTask = nil
        // Invalidate before publishing so new result cells use fresh icons.
        if !result.invalidatedIconPaths.isEmpty { onIconsInvalidated?(result.invalidatedIconPaths) }
        if result.entriesChanged { onChange?() }
        onRefreshFinished?()
        if needsRescan, !scanning { refresh() }
    }

    private func changed(_ events: [CatalogEvent]) {
        let impact = CatalogEventImpact.classify(events, roots: canonicalRoots)
        guard impact.requiresRefresh else { return }
        pendingImpact.merge(impact)
        let now = ProcessInfo.processInfo.systemUptime
        let delay = max(0, debounce.deadline(afterEventAt: now) - now)
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func watch() {
        guard watchChanges else { return }
        watcher = nil
        canonicalRoots = roots.map { CatalogPaths.canonical($0.path) }
        // Watch before scanning, including the nearest existing parent when a
        // root is absent. Full scans preserve nested apps and identifier deduplication.
        let paths = Array(
            Set(
                roots.map { root -> String in
                    var url = root
                    if url.pathExtension.lowercased() == "app" { url.deleteLastPathComponent() }
                    while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" {
                        url.deleteLastPathComponent()
                    }
                    return CatalogPaths.canonical(url.path)
                }))
        watcher = CatalogWatcher(paths: paths) { [weak self] events in self?.changed(events) }
    }
}

// This owner releases the C stream independently of actor-isolated catalog state.
// Its callback always runs on the explicitly configured main dispatch queue.
private final class CatalogWatcher {
    private var stream: FSEventStreamRef?

    init(paths: [String], onEvents: @escaping @MainActor @Sendable ([CatalogEvent]) -> Void) {
        let handler = CatalogEventHandler(onEvents: onEvents)
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                return UnsafeRawPointer(Unmanaged<CatalogEventHandler>.fromOpaque(info).retain().toOpaque())
            },
            release: { info in
                guard let info else { return }
                Unmanaged<CatalogEventHandler>.fromOpaque(info).release()
            }, copyDescription: nil)
        stream = FSEventStreamCreate(
            nil,
            { _, info, count, eventPaths, flags, _ in
                guard let info else { return }
                let pointers = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                let events = (0..<count).map {
                    CatalogEvent(path: String(cString: pointers[$0]), flags: flags[$0])
                }
                let handler = Unmanaged<CatalogEventHandler>.fromOpaque(info).takeUnretainedValue()
                MainActor.assumeIsolated { handler.onEvents(events) }
            }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            if !FSEventStreamStart(stream) {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
                NSLog("Ciel: app watcher could not start. Manual rescan remains available.")
            }
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}

// The stream retains this immutable context, so an already dispatched C callback
// does not refer to a destroyed watcher. It does not retain the catalog.
private final class CatalogEventHandler: Sendable {
    let onEvents: @MainActor @Sendable ([CatalogEvent]) -> Void

    init(onEvents: @escaping @MainActor @Sendable ([CatalogEvent]) -> Void) {
        self.onEvents = onEvents
    }
}
