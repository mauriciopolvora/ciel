import AppKit

@MainActor
final class IconCache {
    typealias Loader = @Sendable (String) async -> CGImage?
    typealias Completion = @MainActor (String, NSImage?) -> Void

    private struct CachedIcon {
        let image: NSImage
        let cost: Int
        var lastUse: UInt64
    }

    private struct Request {
        let id: UUID
        var completions: [Completion]
    }

    private let loader: Loader
    private let countLimit: Int
    private let costLimit: Int
    private let pendingLimit: Int
    private let concurrentLimit: Int
    private let completionLimit: Int
    private var cached: [String: CachedIcon] = [:]
    private var requests: [String: Request] = [:]
    private var queued: [String] = []
    private var running: [UUID: Task<Void, Never>] = [:]
    private var delivering: [String: UUID] = [:]
    private var cacheCost = 0
    private var clock: UInt64 = 0

    /// Include obsolete running loads so diagnostic checks can wait for all icon work.
    var pendingCount: Int { queued.count + running.count }
    var cachedCount: Int { cached.count }

    init(
        countLimit: Int = 80, costLimit: Int = 4 * 1024 * 1024,
        pendingLimit: Int = 64, concurrentLimit: Int = 2, completionLimit: Int = 16,
        loader: @escaping Loader = { await IconCache.loadIcon($0) }
    ) {
        self.countLimit = max(1, countLimit)
        self.costLimit = max(0, costLimit)
        self.pendingLimit = max(1, pendingLimit)
        self.concurrentLimit = max(1, min(concurrentLimit, self.pendingLimit))
        self.completionLimit = max(1, completionLimit)
        self.loader = loader
    }

    /// A miss returns immediately. Keep a placeholder until the main-actor callback arrives.
    /// A cell must check its current entry before applying the callback's path and image.
    func icon(for path: String, onLoad: @escaping Completion) -> NSImage? {
        clock &+= 1
        if var hit = cached[path] {
            hit.lastUse = clock
            cached[path] = hit
            return hit.image
        }
        if var request = requests[path] {
            // Repeated table updates must not retain unlimited callbacks for the same icon.
            if request.completions.count == completionLimit { request.completions.removeFirst() }
            request.completions.append(onLoad)
            requests[path] = request
            return nil
        }
        if pendingCount >= pendingLimit {
            // Prefer recent results when a query changes faster than icons can load.
            guard !queued.isEmpty else { return nil }
            requests.removeValue(forKey: queued.removeFirst())
        }
        requests[path] = Request(id: UUID(), completions: [onLoad])
        queued.append(path)
        startQueuedLoads()
        return nil
    }

    func invalidate(paths: Set<String>) {
        for path in paths {
            if let old = cached.removeValue(forKey: path) { cacheCost -= old.cost }
            requests.removeValue(forKey: path)
            delivering.removeValue(forKey: path)
        }
        queued.removeAll { paths.contains($0) }
        // Running work may finish after invalidation. Its request ID no longer matches.
    }

    private func startQueuedLoads() {
        while running.count < concurrentLimit, !queued.isEmpty {
            let path = queued.removeFirst()
            guard let request = requests[path] else { continue }
            let id = request.id
            let loader = loader
            running[id] = Task.detached(priority: .userInitiated) { [weak self] in
                let pixels = await loader(path)
                await self?.complete(path: path, id: id, pixels: pixels)
            }
        }
    }

    private func complete(path: String, id: UUID, pixels: CGImage?) {
        running.removeValue(forKey: id)
        defer { startQueuedLoads() }
        guard let request = requests[path], request.id == id else { return }
        requests.removeValue(forKey: path)
        delivering[path] = id
        defer {
            if delivering[path] == id { delivering.removeValue(forKey: path) }
        }
        let image = pixels.map { pixels in
            // Keep source pixel dimensions separate from the image's point size.
            let size = NSSize(width: 36, height: 36)
            let representation = NSBitmapImageRep(cgImage: pixels)
            representation.size = size
            let image = NSImage(size: size)
            image.addRepresentation(representation)
            return image
        }
        if let image, let pixels {
            store(image, path: path, cost: pixels.bytesPerRow * pixels.height)
        }
        for completion in request.completions {
            guard delivering[path] == id else { break }
            completion(path, image)
        }
    }

    private func store(_ image: NSImage, path: String, cost: Int) {
        guard cost <= costLimit else { return }
        while cached.count >= countLimit || cacheCost + cost > costLimit {
            guard let oldest = cached.min(by: { $0.value.lastUse < $1.value.lastUse }) else { break }
            cached.removeValue(forKey: oldest.key)
            cacheCost -= oldest.value.cost
        }
        clock &+= 1
        cached[path] = CachedIcon(image: image, cost: cost, lastUse: clock)
        cacheCost += cost
    }

    nonisolated private static func loadIcon(_ path: String) async -> CGImage? {
        autoreleasepool {
            // Apple permits icon(forFile:) on any thread. Keep AppKit image work here;
            // only the immutable CGImage crosses to the main actor.
            let source = NSWorkspace.shared.icon(forFile: path)
            let pixels = 72
            guard
                let context = CGContext(
                    data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                    bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return nil }
            context.scaleBy(x: 2, y: 2)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            source.draw(
                in: NSRect(x: 0, y: 0, width: 36, height: 36), from: .zero, operation: .sourceOver,
                fraction: 1)
            return context.makeImage()
        }
    }
}
