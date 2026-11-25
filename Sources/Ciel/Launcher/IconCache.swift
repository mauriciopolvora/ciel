import AppKit

@MainActor
final class IconCache {
    typealias Loader = @Sendable (String) async -> CGImage?
    typealias Completion = @MainActor (String, NSImage?) -> Void

    private enum Metrics {
        static let pointSize = NSSize(width: 36, height: 36)
        static let scale: CGFloat = 2
    }

    private struct CachedIcon {
        let image: NSImage
        let cost: Int
        var lastUse: UInt64
    }

    @MainActor private final class Load {
        var completions: [Completion]
        init(_ completion: @escaping Completion) { completions = [completion] }
    }

    private let loader: Loader
    private let countLimit: Int
    private let costLimit: Int
    private let pendingLimit: Int
    private let concurrentLimit: Int
    private let completionLimit: Int
    private var cached: [String: CachedIcon] = [:]
    private var loads: [String: Load] = [:]
    private var queued: [String] = []
    private var loadsInFlight = 0
    private var deliveringPath: String?
    private var cacheCost = 0
    private var clock: UInt64 = 0

    var pendingCount: Int { queued.count + loadsInFlight }
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

    func icon(for path: String, onLoad: @escaping Completion) -> NSImage? {
        clock &+= 1
        if var hit = cached[path] {
            hit.lastUse = clock
            cached[path] = hit
            return hit.image
        }
        if let load = loads[path] {
            if load.completions.count == completionLimit { load.completions.removeFirst() }
            load.completions.append(onLoad)
            return nil
        }
        if pendingCount >= pendingLimit {
            guard !queued.isEmpty else { return nil }
            loads.removeValue(forKey: queued.removeFirst())
        }
        loads[path] = Load(onLoad)
        queued.append(path)
        startQueuedLoads()
        return nil
    }

    func invalidate(paths: Set<String>) {
        for path in paths {
            if let old = cached.removeValue(forKey: path) { cacheCost -= old.cost }
            loads.removeValue(forKey: path)
        }
        queued.removeAll { paths.contains($0) }
        if let deliveringPath, paths.contains(deliveringPath) { self.deliveringPath = nil }
    }

    private func startQueuedLoads() {
        while loadsInFlight < concurrentLimit, !queued.isEmpty {
            let path = queued.removeFirst()
            guard let load = loads[path] else { continue }
            loadsInFlight += 1
            let loader = loader
            Task.detached(priority: .userInitiated) { [weak self] in
                let pixels = await loader(path)
                await self?.complete(load, path: path, pixels: pixels)
            }
        }
    }

    private func complete(_ load: Load, path: String, pixels: CGImage?) {
        loadsInFlight -= 1
        defer { startQueuedLoads() }
        guard loads[path] === load else { return }
        loads.removeValue(forKey: path)
        let image = pixels.map(Self.image)
        if let image, let pixels {
            store(image, path: path, cost: pixels.bytesPerRow * pixels.height)
        }
        deliveringPath = path
        defer { deliveringPath = nil }
        for completion in load.completions {
            guard deliveringPath == path else { break }
            completion(path, image)
        }
    }

    private static func image(_ pixels: CGImage) -> NSImage {
        let representation = NSBitmapImageRep(cgImage: pixels)
        representation.size = Metrics.pointSize
        let image = NSImage(size: Metrics.pointSize)
        image.addRepresentation(representation)
        return image
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
            // Apple permits icon(forFile:) on any thread.
            let source = NSWorkspace.shared.icon(forFile: path)
            let pixels = Int(Metrics.pointSize.width * Metrics.scale)
            guard
                let context = CGContext(
                    data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                    bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return nil }
            context.scaleBy(x: Metrics.scale, y: Metrics.scale)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            source.draw(
                in: NSRect(origin: .zero, size: Metrics.pointSize), from: .zero, operation: .sourceOver,
                fraction: 1)
            return context.makeImage()
        }
    }
}
