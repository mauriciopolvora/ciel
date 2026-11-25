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
        try await waitUntil { secondFinished }
        let current = try #require(loadedSecond)
        #expect(cell.appIcon.image === current)
        #expect(await loader.finish("/First.app", pixels: cellIconPixels(width: 3)))
        try await waitForIdle(icons)
        #expect(cell.appIcon.image === current)
        #expect(cell.titleLabel.stringValue == "Second")
        #expect(cell.hintLabel.stringValue == "⌘2")
    }

    @Test(arguments: [
        ("ci", ["Ciel Settings", "Rescan Applications"]),
        ("display", ["Move to Next Display", "Move to Previous Display"]),
        ("left", ["Left Half"]),
    ])
    func resultIconsDrawInTheirRowColorsSelectedOrNot(query: String, titles: [String]) throws {
        let view = LauncherView(
            frame: NSRect(x: 0, y: 0, width: LauncherView.width, height: LauncherView.initialHeight))
        let window = NSWindow(
            contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.onHeightChange = { [weak window] in
            window?.setContentSize(NSSize(width: LauncherView.width, height: $0))
        }
        view.update(entries: SearchEntry.utilities + SearchEntry.commands, usage: Usage())
        view.searchField.stringValue = query
        view.updateResults()
        #expect(Array(view.results.map(\.title).prefix(titles.count)) == titles)
        let fill = gray(Theme.accent)
        let darkInk = (fill + gray(Theme.selectedSecondary)) / 2
        let lightInk = (gray(Theme.surface) + gray(Theme.secondary)) / 2
        for selected in 0..<2 {
            if selected > 0 {
                _ = view.control(
                    view.searchField, textView: NSTextView(),
                    doCommandBy: #selector(NSResponder.moveDown(_:)))
            }
            #expect(view.table.selectedRow == selected)
            let ink = try iconInk(in: view, rows: 2)
            for (row, (darkest, brightest)) in ink.enumerated() {
                let title = view.results[row].title
                if row == selected {
                    #expect(darkest < darkInk, "selected \(title) has no dark ink, darkest \(darkest)")
                    #expect(
                        brightest < (fill + 1) / 2, "selected \(title) draws above its fill, \(brightest)")
                } else {
                    #expect(brightest > lightInk, "unselected \(title) has no light ink, \(brightest)")
                }
            }
        }
    }

    @Test func aHoveredRowSelectedFromTheKeyboardKeepsItsSelectionFill() throws {
        let view = LauncherView(
            frame: NSRect(x: 0, y: 0, width: LauncherView.width, height: LauncherView.initialHeight))
        let window = NSWindow(
            contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.onHeightChange = { [weak window] in
            window?.setContentSize(NSSize(width: LauncherView.width, height: $0))
        }
        view.update(entries: SearchEntry.utilities, usage: Usage())
        view.searchField.stringValue = "ci"
        view.updateResults()
        view.layoutSubtreeIfNeeded()
        let row = try #require(view.table.rowView(atRow: 1, makeIfNecessary: false))
        let entered = try #require(
            NSEvent.enterExitEvent(
                with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0,
                userData: nil))
        let plain = try rowFill(of: row, in: view)
        row.mouseEntered(with: entered)
        #expect(try rowFill(of: row, in: view) > plain + 0.03, "the hover overlay did not draw")
        _ = view.control(
            view.searchField, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:)))
        #expect(row.isSelected)
        let fill = try rowFill(of: row, in: view)
        #expect(fill > (gray(Theme.accent) + gray(Theme.selection)) / 2, "selected fill is \(fill)")
    }
}

@MainActor
private func rowFill(of row: NSView, in view: LauncherView) throws -> CGFloat {
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
    let rect = row.convert(row.bounds, to: view)
    return gray(try #require(bitmap.colorAt(x: Int(rect.midX * scale), y: Int((rect.minY + 6) * scale))))
}

@MainActor
private func iconInk(in view: LauncherView, rows: Int) throws -> [(CGFloat, CGFloat)] {
    view.layoutSubtreeIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
    return try (0..<rows).map { row in
        let cell = try #require(view.table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ResultCell)
        let icon: NSView = cell.appIcon.isHidden ? cell.commandIcon : cell.appIcon
        let rect = icon.convert(icon.bounds, to: view)
        var darkest: CGFloat = 1
        var brightest: CGFloat = 0
        for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
            for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let value = gray(color) * color.alphaComponent
                darkest = min(darkest, value)
                brightest = max(brightest, value)
            }
        }
        return (darkest, brightest)
    }
}

private func gray(_ color: NSColor) -> CGFloat {
    color.usingColorSpace(.genericGray)?.whiteComponent ?? 0
}

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
