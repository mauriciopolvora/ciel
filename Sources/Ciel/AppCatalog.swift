import AppKit
import CielCore
import CoreServices

@MainActor
final class AppCatalog {
    private(set) var entries: [SearchEntry] = []
    var onUpdate: ((CatalogUpdate) -> Void)?

    private let worker = CatalogScanWorker()
    private let roots: [URL]
    private let cacheURL: URL?
    private let watchChanges: Bool
    private var canonicalRoots: [String]
    private var cachedEntries: [SearchEntry]?
    private var watcher: Cleanup?
    private var pending: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var debounce = CatalogDebounce()
    private var pendingImpact = CatalogEventImpact()
    private var scanning = false
    private var rescanRequested = false

    convenience init(roots: [URL] = ApplicationScanner.defaultRoots, useCache: Bool = true) {
        let identifier = Bundle.main.bundleIdentifier ?? AppIdentity.bundleIdentifier
        let cacheURL =
            useCache
            ? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(identifier).appendingPathComponent("apps.json") : nil
        self.init(roots: roots, cacheURL: cacheURL, watchChanges: true)
    }

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
        onUpdate?(
            CatalogUpdate(
                invalidatedIconPaths: result.invalidatedIconPaths, entriesChanged: result.entriesChanged))
        if needsRescan, !scanning { refresh() }
    }

    func changed(_ events: [CatalogEvent]) {
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
        watcher = CatalogWatcher.start(paths: CatalogPaths.watchPaths(for: roots)) { [weak self] events in
            self?.changed(events)
        }
    }
}

private enum CatalogWatcher {
    static func start(
        paths: [String], onEvents: @escaping @MainActor @Sendable ([CatalogEvent]) -> Void
    ) -> Cleanup? {
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
        guard
            let stream = FSEventStreamCreate(
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
                FSEventStreamCreateFlags(
                    kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        else { return nil }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            NSLog("Ciel: app watcher could not start. Manual rescan remains available.")
            return nil
        }
        return Cleanup {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}

private final class CatalogEventHandler: Sendable {
    let onEvents: @MainActor @Sendable ([CatalogEvent]) -> Void

    init(onEvents: @escaping @MainActor @Sendable ([CatalogEvent]) -> Void) {
        self.onEvents = onEvents
    }
}
