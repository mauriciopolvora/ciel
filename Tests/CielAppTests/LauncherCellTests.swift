import AppKit
import CielCore
import Testing

@testable import CielApp

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct LauncherCellTests {
    @Test func lateApplicationIconDoesNotReplaceUtilitySymbolInReusedCell() async throws {
        let loader = CellIconLoader()
        let icons = IconCache(loader: { await loader.load($0) })
        let cell = ResultCell()
        let app = SearchEntry(
            id: "app", title: "Application", subtitle: "Applications", kind: .application,
            path: "/Application.app")
        let settings = SearchEntry(id: "settings", title: "Settings", subtitle: "Ciel", kind: .utility)
        cell.configure(app, index: 0, icons: icons, selected: false, showKeys: false)
        await loader.waitForStarts(1)
        cell.configure(settings, index: 0, icons: icons, selected: true, showKeys: false)
        let symbol = try #require(cell.appIcon.image)
        #expect(await loader.finish("/Application.app", pixels: cellIconPixels(width: 3)))
        try await waitForIdle(icons)
        #expect(cell.appIcon.image === symbol)
        #expect(cell.titleLabel.stringValue == "Settings")
        #expect(cell.hintLabel.stringValue == "↵")
    }

    @Test func lateIconForOldPathDoesNotReplaceCurrentApplicationIcon() async throws {
        let loader = CellIconLoader()
        let icons = IconCache(loader: { await loader.load($0) })
        let cell = ResultCell()
        let first = SearchEntry(
            id: "first", title: "First", subtitle: "Applications", kind: .application, path: "/First.app")
        let second = SearchEntry(
            id: "second", title: "Second", subtitle: "Applications", kind: .application, path: "/Second.app")
        cell.configure(first, index: 0, icons: icons, selected: false, showKeys: false)
        cell.configure(second, index: 1, icons: icons, selected: false, showKeys: true)
        await loader.waitForStarts(2)
        var loadedSecond: NSImage?
        var secondFinished = false
        _ = icons.icon(for: "/Second.app") { _, image in
            loadedSecond = image
            secondFinished = true
        }
        #expect(await loader.finish("/Second.app", pixels: cellIconPixels(width: 7)))
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        // AppKit can change an image's representations. Wait for the cache's
        // exact delivered object, then check that cell reuse keeps this object.
        while !secondFinished {
            guard ContinuousClock.now < deadline else { throw CellTestError.loadTimedOut }
            try await Task.sleep(for: .milliseconds(1))
        }
        let current = try #require(loadedSecond)
        #expect(cell.appIcon.image === current)
        #expect(await loader.finish("/First.app", pixels: cellIconPixels(width: 3)))
        try await waitForIdle(icons)
        #expect(cell.appIcon.image === current)
        #expect(cell.titleLabel.stringValue == "Second")
        #expect(cell.hintLabel.stringValue == "⌘2")
    }

    private func waitForIdle(_ cache: IconCache) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while cache.pendingCount > 0 {
            guard ContinuousClock.now < deadline else { throw CellTestError.loadTimedOut }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

private enum CellTestError: Error { case loadTimedOut }

private actor CellIconLoader {
    private var starts = 0
    private var pending: [String: CheckedContinuation<CGImage?, Never>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func load(_ path: String) async -> CGImage? {
        await withCheckedContinuation { continuation in
            starts += 1
            pending[path] = continuation
            let ready = waiters.filter { starts >= $0.0 }
            waiters.removeAll { starts >= $0.0 }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForStarts(_ count: Int) async {
        guard starts < count else { return }
        await withCheckedContinuation { continuation in waiters.append((count, continuation)) }
    }

    func finish(_ path: String, pixels: CGImage?) -> Bool {
        guard let continuation = pending.removeValue(forKey: path) else { return false }
        continuation.resume(returning: pixels)
        return true
    }
}

private func cellIconPixels(width: Int) -> CGImage? {
    CGContext(
        data: nil, width: width, height: 2, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
        .makeImage()
}
