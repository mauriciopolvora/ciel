import AppKit
import Testing

@testable import CielApp

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct IconCacheTests {
    @Test func coalescesLoadsAndReturnsCachedImageWithoutCallback() async throws {
        let loader = ControlledIconLoader()
        let cache = IconCache(loader: { await loader.load($0) })
        var completions: [(String, NSImage?)] = []
        #expect(cache.icon(for: "one.app") { completions.append(($0, $1)) } == nil)
        #expect(cache.icon(for: "one.app") { completions.append(($0, $1)) } == nil)
        await loader.waitForStarts(1)
        #expect(await loader.paths == ["one.app"])
        #expect(await loader.finish("one.app", pixels: iconPixels()))
        try await waitForIdle(cache)

        try #require(completions.count == 2)
        #expect(completions.map(\.0) == ["one.app", "one.app"])
        #expect(completions[0].1 === completions[1].1)
        let hit = cache.icon(for: "one.app") { _, _ in Issue.record("Cache hit called completion") }
        #expect(hit === completions[0].1)
        #expect(cache.cachedCount == 1)
        #expect(cache.pendingCount == 0)
        #expect(await loader.paths.count == 1)
    }

    @Test func invalidationRejectsInFlightImageAndStartsFreshLoad() async throws {
        let loader = ControlledIconLoader()
        let cache = IconCache(concurrentLimit: 1, loader: { await loader.load($0) })
        var staleDelivered = false
        var fresh: NSImage?
        _ = cache.icon(for: "updated.app") { _, _ in staleDelivered = true }
        await loader.waitForStarts(1)
        cache.invalidate(paths: ["updated.app"])
        _ = cache.icon(for: "updated.app") { _, image in fresh = image }
        #expect(cache.pendingCount == 2)

        #expect(await loader.finish("updated.app", pixels: iconPixels(red: 1)))
        await loader.waitForStarts(2)
        #expect(cache.cachedCount == 0)
        #expect(!staleDelivered)
        #expect(fresh == nil)
        #expect(await loader.finish("updated.app", pixels: iconPixels(green: 1)))
        try await waitForIdle(cache)

        #expect(!staleDelivered)
        let pixels = try #require(fresh?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let color = try #require(NSBitmapImageRep(cgImage: pixels).colorAt(x: 0, y: 0))
        #expect(color.greenComponent > 0.9)
        #expect(color.redComponent < 0.1)
        #expect(cache.icon(for: "updated.app") { _, _ in } === fresh)
    }

    @Test func invalidationOnlyEvictsAffectedCachedPaths() async throws {
        let cache = IconCache(loader: { _ in iconPixels() })
        let first = await loadedImage(cache, path: "first.app")
        let second = await loadedImage(cache, path: "second.app")
        cache.invalidate(paths: ["first.app"])
        #expect(cache.cachedCount == 1)
        #expect(cache.icon(for: "second.app") { _, _ in } === second)
        #expect(cache.icon(for: "first.app") { _, _ in } == nil)
        try await waitForIdle(cache)
        #expect(cache.icon(for: "first.app") { _, _ in } !== first)
    }

    @Test func countLimitEvictsLeastRecentlyUsedIcon() async throws {
        let cache = IconCache(countLimit: 2, loader: { _ in iconPixels() })
        let first = await loadedImage(cache, path: "first.app")
        _ = await loadedImage(cache, path: "second.app")
        #expect(cache.icon(for: "first.app") { _, _ in } === first)
        _ = await loadedImage(cache, path: "third.app")
        #expect(cache.cachedCount == 2)
        #expect(cache.icon(for: "first.app") { _, _ in } === first)
        #expect(cache.icon(for: "second.app") { _, _ in } == nil)
        try await waitForIdle(cache)
        #expect(cache.cachedCount == 2)
    }

    @Test func costLimitEvictsIconsAndDoesNotCacheOversizedImages() async throws {
        let pixels = try #require(iconPixels())
        let cost = pixels.bytesPerRow * pixels.height
        let cache = IconCache(costLimit: cost, loader: { _ in pixels })
        _ = await loadedImage(cache, path: "first.app")
        _ = await loadedImage(cache, path: "second.app")
        #expect(cache.cachedCount == 1)
        #expect(cache.icon(for: "first.app") { _, _ in } == nil)
        try await waitForIdle(cache)

        let oversized = IconCache(costLimit: cost - 1, loader: { _ in pixels })
        #expect(await loadedImage(oversized, path: "large.app") != nil)
        #expect(oversized.cachedCount == 0)
        #expect(oversized.icon(for: "large.app") { _, _ in } == nil)
        try await waitForIdle(oversized)
    }

    @Test func pendingLimitDropsOldQueuedPathAndKeepsNewestResult() async throws {
        let loader = ControlledIconLoader()
        let cache = IconCache(pendingLimit: 2, concurrentLimit: 1, loader: { await loader.load($0) })
        var discardedDelivered = false
        var latestDelivered = false
        _ = cache.icon(for: "active.app") { _, _ in }
        await loader.waitForStarts(1)
        _ = cache.icon(for: "old-query.app") { _, _ in discardedDelivered = true }
        _ = cache.icon(for: "new-query.app") { _, _ in latestDelivered = true }
        #expect(cache.pendingCount == 2)
        #expect(await loader.paths == ["active.app"])

        #expect(await loader.finish("active.app", pixels: iconPixels()))
        await loader.waitForStarts(2)
        #expect(await loader.paths == ["active.app", "new-query.app"])
        #expect(await loader.finish("new-query.app", pixels: iconPixels()))
        try await waitForIdle(cache)
        #expect(!discardedDelivered)
        #expect(latestDelivered)
    }

    @Test func activeLoadsStayWithinConcurrencyAndPendingLimits() async throws {
        let loader = ControlledIconLoader()
        let cache = IconCache(pendingLimit: 2, concurrentLimit: 2, loader: { await loader.load($0) })
        _ = cache.icon(for: "first.app") { _, _ in }
        _ = cache.icon(for: "second.app") { _, _ in }
        await loader.waitForStarts(2)
        #expect(cache.icon(for: "extra.app") { _, _ in Issue.record("Rejected path completed") } == nil)
        #expect(cache.pendingCount == 2)
        #expect(Set(await loader.paths) == ["first.app", "second.app"])
        #expect(await loader.finish("first.app", pixels: iconPixels()))
        #expect(await loader.finish("second.app", pixels: iconPixels()))
        try await waitForIdle(cache)
        #expect(await loader.paths.count == 2)
    }

    @Test func invalidatedRunningLoadsStillCountTowardPendingLimit() async throws {
        let loader = ControlledIconLoader()
        let cache = IconCache(pendingLimit: 2, concurrentLimit: 1, loader: { await loader.load($0) })
        var staleDelivered = false
        _ = cache.icon(for: "old.app") { _, _ in staleDelivered = true }
        await loader.waitForStarts(1)
        cache.invalidate(paths: ["old.app"])
        _ = cache.icon(for: "old.app") { _, _ in staleDelivered = true }
        _ = cache.icon(for: "latest.app") { _, _ in }
        #expect(cache.pendingCount == 2)

        #expect(await loader.finish("old.app", pixels: iconPixels()))
        await loader.waitForStarts(2)
        #expect(await loader.paths == ["old.app", "latest.app"])
        #expect(await loader.finish("latest.app", pixels: iconPixels()))
        try await waitForIdle(cache)
        #expect(!staleDelivered)
        #expect(cache.cachedCount == 1)
    }

    @Test func repeatedRequestsKeepOnlyRecentCallbacksWithinLimit() async throws {
        let loader = ControlledIconLoader()
        let cache = IconCache(completionLimit: 2, loader: { await loader.load($0) })
        var delivered: [Int] = []
        for value in 1...3 {
            _ = cache.icon(for: "one.app") { _, _ in delivered.append(value) }
        }
        await loader.waitForStarts(1)
        #expect(await loader.finish("one.app", pixels: iconPixels()))
        try await waitForIdle(cache)
        #expect(delivered == [2, 3])
    }

    @Test func failedLoadReportsExactPathOnMainActorAndCanRetry() async throws {
        let loader = ControlledIconLoader()
        let cache = IconCache(loader: { await loader.load($0) })
        var failureReported = false
        _ = cache.icon(for: "missing.app") { path, image in
            #expect(Thread.isMainThread)
            #expect(path == "missing.app")
            #expect(image == nil)
            failureReported = true
        }
        await loader.waitForStarts(1)
        #expect(await loader.finish("missing.app", pixels: nil))
        try await waitForIdle(cache)
        #expect(failureReported)
        #expect(cache.cachedCount == 0)

        _ = cache.icon(for: "missing.app") { _, _ in }
        await loader.waitForStarts(2)
        #expect(await loader.finish("missing.app", pixels: iconPixels()))
        try await waitForIdle(cache)
        #expect(cache.cachedCount == 1)
    }

    @Test func reentrantInvalidationStopsRemainingStaleCallbacks() async throws {
        let loader = ControlledIconLoader()
        let cache = IconCache(loader: { await loader.load($0) })
        var staleDelivered = false
        _ = cache.icon(for: "changed.app") { path, _ in cache.invalidate(paths: [path]) }
        _ = cache.icon(for: "changed.app") { _, _ in staleDelivered = true }
        await loader.waitForStarts(1)
        #expect(await loader.finish("changed.app", pixels: iconPixels()))
        try await waitForIdle(cache)
        #expect(!staleDelivered)
        #expect(cache.cachedCount == 0)
    }

    @Test func defaultLoaderProducesRetinaPixelsAndThirtySixPointImage() async throws {
        let cache = IconCache()
        let image = try #require(
            await loadedImage(cache, path: "/System/Applications/Utilities/Terminal.app"))
        #expect(image.size == NSSize(width: 36, height: 36))
        #expect(image.representations.first?.pixelsWide == 72)
        #expect(image.representations.first?.pixelsHigh == 72)
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
        #expect(bitmap.size == image.size)
        #expect(bitmap.cgImage?.width == 72)
        #expect(bitmap.cgImage?.height == 72)
        #expect(cache.cachedCount == 1)
    }

    @Test func mainActorImageKeepsLoaderPixelsSeparateFromLogicalSize() async throws {
        let cache = IconCache(loader: { _ in iconPixels(width: 80, height: 48) })
        let image = try #require(await loadedImage(cache, path: "custom.app"))
        let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
        #expect(image.size == NSSize(width: 36, height: 36))
        #expect(bitmap.size == image.size)
        #expect(bitmap.pixelsWide == 80)
        #expect(bitmap.pixelsHigh == 48)
        #expect(bitmap.cgImage?.width == 80)
        #expect(bitmap.cgImage?.height == 48)
    }

    private func loadedImage(_ cache: IconCache, path: String) async -> NSImage? {
        var image: NSImage?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if let hit = cache.icon(
                for: path,
                onLoad: { _, loaded in
                    image = loaded
                    continuation.resume()
                })
            {
                image = hit
                continuation.resume()
            }
        }
        return image
    }

    private func waitForIdle(_ cache: IconCache) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while cache.pendingCount > 0 {
            guard clock.now < deadline else { throw IconTestError.loadTimedOut }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

private enum IconTestError: Error {
    case loadTimedOut
}

private actor ControlledIconLoader {
    private(set) var paths: [String] = []
    private var loads: [String: [CheckedContinuation<CGImage?, Never>]] = [:]
    private var started: [(Int, CheckedContinuation<Void, Never>)] = []

    func load(_ path: String) async -> CGImage? {
        await withCheckedContinuation { continuation in
            paths.append(path)
            loads[path, default: []].append(continuation)
            let ready = started.filter { paths.count >= $0.0 }
            started.removeAll { paths.count >= $0.0 }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForStarts(_ count: Int) async {
        guard paths.count < count else { return }
        await withCheckedContinuation { continuation in started.append((count, continuation)) }
    }

    func finish(_ path: String, pixels: CGImage?) -> Bool {
        guard var pending = loads[path], !pending.isEmpty else { return false }
        pending.removeFirst().resume(returning: pixels)
        if pending.isEmpty {
            loads.removeValue(forKey: path)
        } else {
            loads[path] = pending
        }
        return true
    }
}

private func iconPixels(width: Int = 4, height: Int = 4, red: CGFloat = 0, green: CGFloat = 0) -> CGImage? {
    guard
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }
    context.setFillColor(red: red, green: green, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}
