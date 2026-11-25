import AppKit
import CielCore
import Testing

@testable import CielApp

@MainActor @Suite("Launcher category keys")
struct LauncherCategoryTests {
    @Test func tabCyclesAllAppsWindowsAndShiftTabReverses() {
        let view = LauncherView(
            frame: NSRect(x: 0, y: 0, width: LauncherView.width, height: LauncherView.initialHeight))
        let editor = NSTextView()
        func press(_ selector: Selector) -> SearchEntry.Kind? {
            #expect(view.control(view.searchField, textView: editor, doCommandBy: selector))
            return view.filter
        }
        let tab = #selector(NSResponder.insertTab(_:))
        let backtab = #selector(NSResponder.insertBacktab(_:))
        #expect([press(tab), press(tab), press(tab)] == [.application, .window, nil])
        #expect([press(backtab), press(backtab), press(backtab)] == [.window, .application, nil])
    }
}
