import AppKit
import Carbon
import Testing

@testable import CielApp

@MainActor @Suite
struct SettingsSpotlightTests {
    private let optionCommandSpace = Shortcut(
        keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | optionKey))
    private let shiftCommandSpace = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))

    @Test func recordingAShortcutSpotlightHoldsKeepsTheOldOneUntilSpotlightLetsGo() {
        withSettings { settings, hotKeys, system in
            settings.recorders[.launcher]?.accept(SpotlightShortcuts.commandSpace)
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
            #expect(settings.spotlightGuide.held == SpotlightShortcuts.commandSpace)
            #expect(
                system.opened.map(\.absoluteString) == [
                    "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Spotlight"
                ])
            #expect(
                settings.spotlightGuide.shownCard
                    == .turnOff(action: "Show Spotlight search", shortcut: "⌘Space"))
            #expect(settings.spotlightGuide.heading.stringValue == "Free ⌘Space from Spotlight")
            #expect(
                settings.spotlightGuide.note.stringValue
                    == "In Keyboard Shortcuts, select Spotlight and turn off Show Spotlight search. Ciel switches when ⌘Space is free."
            )
            settings.spotlightGuide.tick()
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
            system.symbolicHotKeys = ["64": ["enabled": false]]
            settings.spotlightGuide.tick()
            #expect(hotKeys.shortcut(for: .launcher) == SpotlightShortcuts.commandSpace)
            #expect(settings.recorders[.launcher]?.shortcut == SpotlightShortcuts.commandSpace)
            #expect(settings.spotlightGuide.held == nil)
            #expect(settings.spotlightGuide.shownCard == .freed(shortcut: "⌘Space"))
            settings.close()
            #expect(settings.spotlightGuide.shownCard == nil)
        }
    }

    @Test func theGuideNamesTheFinderSearchWhenItHoldsTheShortcut() {
        withSettings { settings, hotKeys, system in
            settings.recorders[.launcher]?.accept(optionCommandSpace)
            #expect(settings.spotlightGuide.held == optionCommandSpace)
            #expect(
                settings.spotlightGuide.shownCard
                    == .turnOff(action: "Show Finder search window", shortcut: "⌥⌘Space"))
            #expect(settings.spotlightGuide.heading.stringValue == "Free ⌥⌘Space from Spotlight")
            #expect(
                settings.spotlightGuide.note.stringValue
                    == "In Keyboard Shortcuts, select Spotlight and turn off Show Finder search window. Ciel switches when ⌥⌘Space is free."
            )
            system.symbolicHotKeys = ["65": ["enabled": false]]
            settings.spotlightGuide.tick()
            #expect(hotKeys.shortcut(for: .launcher) == optionCommandSpace)
        }
    }

    @Test func theGuideNamesTheSpotlightSearchWhenItIsRemappedToTheShortcut() {
        withSettings { settings, hotKeys, system in
            system.symbolicHotKeys = [
                "64": [
                    "enabled": true,
                    "value": ["parameters": [32, 49, 1 << 20 | 1 << 17], "type": "standard"],
                ]
            ]
            settings.recorders[.launcher]?.accept(shiftCommandSpace)
            #expect(settings.spotlightGuide.held == shiftCommandSpace)
            #expect(
                settings.spotlightGuide.shownCard
                    == .turnOff(action: "Show Spotlight search", shortcut: "⇧⌘Space"))
            #expect(settings.spotlightGuide.heading.stringValue == "Free ⇧⌘Space from Spotlight")
            #expect(
                settings.spotlightGuide.note.stringValue
                    == "In Keyboard Shortcuts, select Spotlight and turn off Show Spotlight search. Ciel switches when ⇧⌘Space is free."
            )
            system.symbolicHotKeys = ["64": ["enabled": false]]
            settings.spotlightGuide.tick()
            #expect(hotKeys.shortcut(for: .launcher) == shiftCommandSpace)
        }
    }

    @Test func closingSettingsDropsTheShortcutSpotlightHolds() {
        withSettings { settings, hotKeys, system in
            settings.recorders[.launcher]?.accept(SpotlightShortcuts.commandSpace)
            settings.windowWillClose(Notification(name: NSWindow.willCloseNotification))
            #expect(settings.spotlightGuide.held == nil)
            #expect(settings.spotlightGuide.shownCard == nil)
            system.symbolicHotKeys = ["64": ["enabled": false]]
            settings.spotlightGuide.tick()
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
        }
    }

    @Test func cancelKeepsTheOldShortcutAndSaysSo() {
        withSettings { settings, hotKeys, system in
            settings.recorders[.launcher]?.accept(SpotlightShortcuts.commandSpace)
            settings.cancelSpotlight()
            #expect(settings.spotlightGuide.held == nil)
            #expect(settings.spotlightGuide.shownCard == nil)
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
            #expect(settings.errorLabel.stringValue == "Kept ⌃⌥Space. ⌘Space is still used by Spotlight.")
            system.symbolicHotKeys = ["64": ["enabled": false]]
            settings.spotlightGuide.tick()
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
        }
    }

    @Test func theCaptionBesideTheShortcutFollowsTheSpotlightState() {
        withSettings { settings, hotKeys, system in
            #expect(settings.spotlightGuide.caption.stringValue == "")
            settings.recorders[.launcher]?.accept(SpotlightShortcuts.commandSpace)
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
            #expect(settings.spotlightGuide.caption.stringValue == "Used by Spotlight")
            settings.cancelSpotlight()
            #expect(settings.spotlightGuide.caption.stringValue == "")
            system.symbolicHotKeys = ["64": ["enabled": false]]
            settings.recorders[.launcher]?.accept(SpotlightShortcuts.commandSpace)
            #expect(hotKeys.shortcut(for: .launcher) == SpotlightShortcuts.commandSpace)
            #expect(settings.spotlightGuide.caption.stringValue == "Replaces Spotlight")
        }
    }

    @Test func checkForUpdatesSitsUnderTheToggleAndIsOffWhileTheUpdaterIsStopped() {
        withSettings { settings, _, _ in
            let button = settings.updateButton
            #expect(button.title == "Check for Updates…")
            #expect(button.action == Selector(("checkForUpdates:")))
            #expect(!button.isEnabled)
            let content = settings.content
            content.layoutSubtreeIfNeeded()
            let toggle = Self.alignment(of: settings.updateChecks, in: content)
            let frame = Self.alignment(of: button, in: content)
            #expect(frame.minY > toggle.maxY, "toggle \(toggle), button \(frame)")
            #expect(abs(frame.minX - toggle.minX) <= 0.5, "toggle \(toggle), button \(frame)")
        }
    }

    @Test func aLongDownloadErrorTruncatesInsideItsRow() {
        withEmptyDefaults { defaults in
            let hotKeys = HotKeys(
                defaults: defaults, registrar: FakeHotKeyRegistrar(), onPress: { _ in }, onChange: {})
            let speech = SpeechModelStore(
                folder: FileManager.default.temporaryDirectory.appending(
                    path: "ciel-settings-" + UUID().uuidString))
            let settings = SettingsController(hotKeys: hotKeys, speech: speech, updater: Updater())
            speech.showForCheck(.failed(String(repeating: "The network connection was lost. ", count: 6)))
            settings.refresh()
            let content = settings.content
            content.layoutSubtreeIfNeeded()
            let button = Self.alignment(of: settings.modelButton, in: content)
            let status = Self.alignment(of: settings.modelStatus, in: content)
            let name = Self.labels(in: content).first { $0.stringValue == "Speech model" }
            let nameFrame = name.map { Self.alignment(of: $0, in: content) } ?? .zero
            let frames = "name \(nameFrame), status \(status), button \(button)"
            #expect(button.minX >= 0 && button.maxX <= content.bounds.width, "\(frames)")
            #expect(status.minX >= nameFrame.maxX - 0.5 && status.maxX <= button.minX + 0.5, "\(frames)")
        }
    }

    /// Bezeled buttons draw inside a frame wider than their visible shape, so rows lay out by alignment rect.
    private static func alignment(of view: NSView, in content: NSView) -> NSRect {
        view.superview?.convert(view.alignmentRect(forFrame: view.frame), to: content) ?? .zero
    }

    private static func labels(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? labels(in: $0) }
    }

    @Test func aFreeShortcutIsSavedAtOnce() {
        withSettings { settings, hotKeys, system in
            settings.recorders[.launcher]?.accept(shiftCommandSpace)
            #expect(hotKeys.shortcut(for: .launcher) == shiftCommandSpace)
            #expect(settings.spotlightGuide.held == nil)
            #expect(system.opened.isEmpty)
            #expect(settings.spotlightGuide.shownCard == nil)
        }
    }

    @Test func theCardSaysTheShortcutIsFreeThenCloses() async throws {
        try await withSettingsAsync { settings, hotKeys, system in
            settings.spotlightGuide.hold = .zero
            settings.recorders[.launcher]?.accept(SpotlightShortcuts.commandSpace)
            system.symbolicHotKeys = ["64": ["enabled": false]]
            settings.spotlightGuide.tick()
            #expect(settings.spotlightGuide.shownCard == .freed(shortcut: "⌘Space"))
            try await waitUntil { settings.spotlightGuide.shownCard == nil }
            #expect(hotKeys.shortcut(for: .launcher) == SpotlightShortcuts.commandSpace)
        }
    }

    @Test func choosingAgainDuringTheHoldReplacesTheCard() {
        withSettings { settings, hotKeys, system in
            settings.recorders[.launcher]?.accept(SpotlightShortcuts.commandSpace)
            system.symbolicHotKeys = ["64": ["enabled": false]]
            settings.spotlightGuide.tick()
            settings.recorders[.launcher]?.accept(optionCommandSpace)
            #expect(
                settings.spotlightGuide.shownCard
                    == .turnOff(action: "Show Finder search window", shortcut: "⌥⌘Space"))
            settings.recorders[.launcher]?.accept(shiftCommandSpace)
            #expect(settings.spotlightGuide.shownCard == nil)
            #expect(hotKeys.shortcut(for: .launcher) == shiftCommandSpace)
        }
    }

    private func withSettings(_ body: (SettingsController, HotKeys, FakeSystem) -> Void) {
        withEmptyDefaults { defaults in
            let (settings, hotKeys, system) = Self.settings(defaults)
            body(settings, hotKeys, system)
        }
    }

    private func withSettingsAsync(
        _ body: (SettingsController, HotKeys, FakeSystem) async throws -> Void
    ) async throws {
        let suite = "ciel.saved-data.test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let (settings, hotKeys, system) = Self.settings(defaults)
        try await body(settings, hotKeys, system)
    }

    private static func settings(_ defaults: UserDefaults) -> (SettingsController, HotKeys, FakeSystem) {
        let system = FakeSystem()
        let hotKeys = HotKeys(
            defaults: defaults, registrar: FakeHotKeyRegistrar(), onPress: { _ in }, onChange: {})
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "ciel-settings-" + UUID().uuidString)
        let settings = SettingsController(
            hotKeys: hotKeys, speech: SpeechModelStore(folder: folder), updater: Updater(),
            spotlight: SpotlightShortcuts { system.symbolicHotKeys }, open: { system.opened.append($0) })
        return (settings, hotKeys, system)
    }
}
