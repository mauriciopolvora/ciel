import AppKit
import CielCore
import Testing

@testable import CielApp

@MainActor @Suite("Launcher designs")
struct LauncherDesignTests {
    @Test func designAKeepsTheShippedHeights() {
        let style = LauncherStyle.make(.a, systemDark: true)
        #expect(style.height(results: 0, hasQuery: false) == 68)
        #expect(style.height(results: 0, hasQuery: true) == 140)
        #expect(style.height(results: 1, hasQuery: true) == 120)
        #expect(style.height(results: 12, hasQuery: true) == 404)
    }

    @Test func everyDesignKeepsTheHeaderAndOnlyGraphiteFollowsTheSystem() {
        for design in LauncherDesign.allCases {
            for systemDark in [true, false] {
                let style = LauncherStyle.make(design, systemDark: systemDark)
                #expect(style.height(results: 0, hasQuery: false) == LauncherView.initialHeight)
                #expect(style.dark == (design == .b ? systemDark : true))
            }
        }
    }

    @Test func aDesignChoiceRestylesAnOpenLauncher() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "designPreview.launcher") }
        let view = LauncherView(
            frame: NSRect(x: 0, y: 0, width: LauncherView.width, height: LauncherView.initialHeight))
        var heights: [CGFloat] = []
        view.onHeightChange = { heights.append($0) }
        let entries = ["Calculator", "Calendar", "Chess"].map {
            SearchEntry(id: $0, title: $0, subtitle: "Applications", kind: .application, path: "/\($0).app")
        }
        view.update(entries: entries, usage: [:], lastUsed: [:])
        view.searchField.stringValue = "calculator"
        view.updateResults()
        let count = view.results.count
        #expect(count > 0)
        DesignPreview().launcher = .c
        try await waitUntil { view.style.design == .c }
        #expect(view.table.rowHeight == 34)
        #expect(
            heights.last == LauncherStyle.make(.c, systemDark: true).height(results: count, hasQuery: true))
        #expect(view.table.selectedRow == 0)
        DesignPreview().launcher = .a
        try await waitUntil { view.style.design == .a }
        #expect(
            heights.last == LauncherStyle.make(.a, systemDark: true).height(results: count, hasQuery: true))
    }
}
