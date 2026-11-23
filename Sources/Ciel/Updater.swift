import AppKit
import Sparkle

/// Sparkle saves the automatic check setting itself, under `SUEnableAutomaticChecks`.
@MainActor final class Updater {
    private let dock = DockDuringUpdate()
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: dock)
    }

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

    func checkButton() -> NSButton {
        let button = NSButton(
            title: "Check for Updates…", target: controller,
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)))
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        button.isEnabled = controller.updater.canCheckForUpdates
        return button
    }

    /// Sparkle changes `canCheckForUpdates` on the main thread.
    func observeCanCheck(_ change: @escaping @MainActor @Sendable (Bool) -> Void) -> NSKeyValueObservation {
        controller.updater.observe(\.canCheckForUpdates) { updater, _ in
            MainActor.assumeIsolated { change(updater.canCheckForUpdates) }
        }
    }
}

/// Sparkle shows a scheduled update behind other apps for an app with no Dock icon, so Ciel joins the Dock
/// until the update session ends. https://sparkle-project.org/documentation/gentle-reminders
@MainActor private final class DockDuringUpdate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        NSApp.setActivationPolicy(.regular)
    }

    func standardUserDriverWillFinishUpdateSession() { NSApp.setActivationPolicy(.accessory) }
}
