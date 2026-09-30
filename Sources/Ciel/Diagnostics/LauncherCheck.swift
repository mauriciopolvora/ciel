import AppKit
import CielCore

/// Native checks run only when Ciel starts with --ui-test.
enum LauncherCheck {
    static func run(launcher: LauncherView, panel: LauncherPanel, entries: [SearchEntry]) {
        guard launcher.results.isEmpty, launcher.table.numberOfRows == 0,
            panel.frame.height == LauncherView.initialHeight,
            launcher.scopeButton.isHidden, launcher.searchField.placeholderString == nil,
            panel.firstResponder is NSTextView
        else {
            print("FAIL blank input-only launcher")
            exit(1)
        }
        let originalExecute = launcher.onExecute
        var ranEmptyResult = false
        launcher.onExecute = { _ in ranEmptyResult = true }
        launcher.executeSelected()
        launcher.execute(at: 0)
        launcher.onExecute = originalExecute
        guard !ranEmptyResult else {
            print("FAIL empty launcher executed a result")
            exit(1)
        }
        guard let editor = panel.firstResponder as? MonochromeFieldEditor,
            editor.insertionPointColor == Theme.text,
            editor.selectedTextAttributes[.backgroundColor] as? NSColor == Theme.selection
        else {
            print("FAIL monochrome native editor")
            exit(1)
        }
        let toggle = MonochromeSwitch(frame: NSRect(x: 0, y: 0, width: 38, height: 28))
        toggle.performClick(nil)
        guard toggle.state == .on else {
            print("FAIL monochrome switch on")
            exit(1)
        }
        toggle.performClick(nil)
        guard toggle.state == .off else {
            print("FAIL monochrome switch off")
            exit(1)
        }
        print("PASS neutral editor colors and native switch state changes")
        print("PASS input-only launch, focused editor, and no empty execution")
        let queries = ["", "calclator", "zzzzzzzzzzzz", "vsc", "right", "safrai", "center", ""]
        for index in 0..<240 {
            launcher.selectFilter(index % 3)
            launcher.searchField.stringValue = queries[index % queries.count]
            launcher.updateResults()
            launcher.layoutSubtreeIfNeeded()
            guard launcher.table.numberOfRows == launcher.results.count else {
                print("FAIL native table row count")
                exit(1)
            }
        }
        launcher.selectFilter(0)
        launcher.searchField.stringValue = "calclator"
        launcher.updateResults()
        guard launcher.results.first?.title == "Calculator", panel.frame.height == 120 else {
            print("FAIL compact Calculator result")
            exit(1)
        }
        guard let editor = panel.firstResponder as? NSTextView,
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "a",
                charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0),
            panel.performKeyEquivalent(with: event), editor.selectedRange().length == 9
        else {
            print("FAIL native Select All shortcut")
            exit(1)
        }
        let query = launcher.searchField.stringValue
        launcher.scopeButton.performClick(nil)
        guard launcher.filter == .application, launcher.searchField.stringValue == query,
            panel.firstResponder is NSTextView
        else {
            print("FAIL category button and search focus")
            exit(1)
        }
        launcher.scopeButton.performClick(nil)
        guard launcher.filter == .window else {
            print("FAIL window category")
            exit(1)
        }
        launcher.scopeButton.performClick(nil)
        guard launcher.filter == nil else {
            print("FAIL all category")
            exit(1)
        }
        launcher.searchField.stringValue = ""
        launcher.updateResults()
        guard launcher.results.isEmpty, launcher.scopeButton.isHidden,
            panel.frame.height == LauncherView.initialHeight
        else {
            print("FAIL clearing query restores blank launcher")
            exit(1)
        }
        launcher.searchField.stringValue = "   "
        launcher.updateResults()
        launcher.entries = entries + SearchEntry.commands
        guard launcher.results.isEmpty, launcher.table.numberOfRows == 0,
            panel.frame.height == LauncherView.initialHeight
        else {
            print("FAIL whitespace or catalog refresh revealed suggestions")
            exit(1)
        }
        print("PASS clearing, whitespace, and catalog refresh keep the launcher blank")
        print("PASS category button cycle, retained query, and search focus")
        print("PASS native Select All shortcut")
        print("PASS 240 native filter/query changes, empty results, and panel resizing")
        print("PASS fuzzy Calculator result and 120-point compact panel")
        NSApp.terminate(nil)
    }
}
