import AppKit
import Testing

@testable import CielApp

@MainActor @Suite
struct SettingsPlacementTests {
    @Test func settingsCentersOnTheGivenScreenNotTheFirstOne() {
        let size = NSSize(width: 560, height: 420)
        let main = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let external = NSRect(x: 1512, y: -300, width: 2560, height: 1415)
        #expect(
            PreferencesController.centered(size, in: main) == NSRect(x: 476, y: 262, width: 560, height: 420))
        let placed = PreferencesController.centered(size, in: external)
        #expect(placed == NSRect(x: 2512, y: 198, width: 560, height: 420))
        #expect(external.contains(placed))
    }
}
