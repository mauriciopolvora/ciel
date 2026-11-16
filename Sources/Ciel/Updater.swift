import AppKit
import Sparkle

/// Reads its feed and public key from Info.plist. Sparkle saves the automatic check setting itself, under
/// `SUEnableAutomaticChecks`.
@MainActor final class Updater {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func start() { controller.startUpdater() }

    /// Sparkle enables the item only while the updater can check.
    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
        item.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        item.target = controller
        return item
    }
}
