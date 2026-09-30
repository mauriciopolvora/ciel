import AppKit
import CielCore
import CoreServices

final class AppCatalog {
    private(set) var entries: [SearchEntry] = []
    var onChange: (() -> Void)?
    private let queue = DispatchQueue(label: "app.ciel.catalog", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private var scanning = false
    private var rescanRequested = false
    private let roots: [URL]
    private let canonicalRoots: [String]
    private let cacheURL: URL?

    init(roots: [URL] = ApplicationScanner.defaultRoots, useCache: Bool = true) {
        self.roots = roots
        canonicalRoots = roots.map { Self.canonicalPath($0.path) }
        cacheURL =
            useCache
            ? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("app.mauriciopolvora.jumpstart/apps.json") : nil
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
            let saved = try? JSONDecoder().decode([SearchEntry].self, from: data)
        {
            entries = saved
        }
        watch()
    }

    deinit {
        pending?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !scanning else {
            rescanRequested = true
            return
        }
        scanning = true
        let cache = cacheURL
        let roots = roots
        let identifier = Bundle.main.bundleIdentifier
        queue.async { [weak self] in
            let result = ApplicationScanner.scan(roots: roots, excluding: identifier)
            if let cache, let data = try? JSONEncoder().encode(result) {
                try? FileManager.default.createDirectory(
                    at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cache, options: .atomic)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.entries = result
                self.scanning = false
                self.onChange?()
                if self.rescanRequested {
                    self.rescanRequested = false
                    self.refresh()
                }
            }
        }
    }

    private func changed(paths: [String], flags: UnsafePointer<FSEventStreamEventFlags>, count: Int) {
        let dropped = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)
        let relevant = (0..<count).contains { index in
            flags[index] & dropped != 0
                || canonicalRoots.contains { root in
                    paths[index] == root || paths[index].hasPrefix(root + "/")
                        || root.hasPrefix(paths[index] + "/")
                }
        }
        guard relevant else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private static func canonicalPath(_ path: String) -> String {
        // URL.resolvingSymlinksInPath hides /private on macOS. FSEvents uses the real path.
        if let resolved = realpath(path, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        guard path != "/" else { return path }
        let parent = (path as NSString).deletingLastPathComponent
        return canonicalPath(parent) + "/" + (path as NSString).lastPathComponent
    }

    private func watch() {
        // FSEvents covers nested directories and changes inside Info.plist. No polling.
        // Watch the nearest existing parent when a standard application folder is absent.
        let paths = Array(
            Set(
                roots.map { root -> String in
                    var url = root
                    if url.pathExtension == "app" { url.deleteLastPathComponent() }
                    while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" {
                        url.deleteLastPathComponent()
                    }
                    return Self.canonicalPath(url.path)
                }))
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(
            nil,
            { _, info, count, eventPaths, flags, _ in
                guard let info else { return }
                let pointers = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                let paths = (0..<count).map { String(cString: pointers[$0]) }
                Unmanaged<AppCatalog>.fromOpaque(info).takeUnretainedValue().changed(
                    paths: paths, flags: flags, count: count)
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
}

final class IconCache {
    private let cache = NSCache<NSString, NSImage>()
    init() {
        cache.countLimit = 80
        cache.totalCostLimit = 4 * 1024 * 1024
    }
    func icon(for path: String) -> NSImage {
        if let image = cache.object(forKey: path as NSString) { return image }
        let image: NSImage = autoreleasepool {
            let source = NSWorkspace.shared.icon(forFile: path)
            let result = NSImage(size: NSSize(width: 36, height: 36))
            result.lockFocus()
            source.draw(
                in: NSRect(x: 0, y: 0, width: 36, height: 36), from: .zero, operation: .sourceOver,
                fraction: 1)
            result.unlockFocus()
            return result
        }
        cache.setObject(image, forKey: path as NSString, cost: 72 * 72 * 4)
        return image
    }
}
