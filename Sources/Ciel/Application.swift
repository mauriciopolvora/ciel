import AppKit

/// Native entry point shared by the app executable and its testable library.
public enum CielApplication {
    @MainActor public static func run() {
        AppPerformance.markLaunch()
        let mode: LaunchMode
        switch LaunchMode.resolve(
            arguments: CommandLine.arguments, bundleIdentifier: Bundle.main.bundleIdentifier)
        {
        case .success(let resolved): mode = resolved
        case .failure(let error):
            FileHandle.standardError.write(Data((error.description + "\n").utf8))
            exit(EX_USAGE)
        }
        let application = NSApplication.shared
        switch mode {
        case .app: run(application, check: nil)
        case .appCheck(let check): run(application, check: check.run)
        case .processCheck(let check): withExtendedLifetime(check.start()) { application.run() }
        }
    }

    @MainActor private static func run(
        _ application: NSApplication, check: (@MainActor (CheckHandles) -> Void)?
    ) {
        let delegate = AppDelegate(check: check)
        application.delegate = delegate
        // NSApplication does not retain its delegate.
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor struct CheckHandles {
    let launcher: LauncherView
    let panel: LauncherPanel
    let fieldEditor: MonochromeFieldEditor
    let catalog: AppCatalog
    let hotKeys: HotKeys
    let menu: NSMenu?
    let showSettings: () -> SettingsController?
    let windowShortcuts: () -> WindowShortcutsController?
    let showGuide: () -> KeyboardGuideController?
}
