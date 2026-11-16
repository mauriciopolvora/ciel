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
            #expect(system.opened == [SpotlightShortcuts.keyboardSettings])
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
        }
    }

    @Test func theGuideNamesTheFinderSearchWhenItHoldsTheShortcut() {
        withSettings { settings, hotKeys, system in
            settings.recorders[.launcher]?.accept(optionCommandSpace)
            #expect(settings.spotlightGuide.held == optionCommandSpace)
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
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
            #expect(settings.errorLabel.stringValue == "Kept ⌃⌥Space. ⌘Space is still used by Spotlight.")
            system.symbolicHotKeys = ["64": ["enabled": false]]
            settings.spotlightGuide.tick()
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
        }
    }

    @Test func everyDesignWaitsForSpotlightBeforeItSavesTheLauncherShortcut() {
        withSettings { settings, hotKeys, system in
            for design in SettingsDesign.allCases {
                settings.show(design)
                settings.recorders[.launcher]?.accept(SpotlightShortcuts.commandSpace)
                #expect(hotKeys.shortcut(for: .launcher) == .launcher)
                #expect(settings.spotlightGuide.replacement == .waiting)
                settings.cancelSpotlight()
                #expect(settings.spotlightGuide.replacement == .offered)
            }
            system.symbolicHotKeys = ["64": ["enabled": false]]
            settings.recorders[.launcher]?.accept(SpotlightShortcuts.commandSpace)
            #expect(hotKeys.shortcut(for: .launcher) == SpotlightShortcuts.commandSpace)
            #expect(settings.spotlightGuide.replacement == .replaced)
        }
    }

    @Test func aFreeShortcutIsSavedAtOnce() {
        withSettings { settings, hotKeys, system in
            settings.recorders[.launcher]?.accept(shiftCommandSpace)
            #expect(hotKeys.shortcut(for: .launcher) == shiftCommandSpace)
            #expect(settings.spotlightGuide.held == nil)
            #expect(system.opened.isEmpty)
        }
    }

    private func withSettings(_ body: (SettingsController, HotKeys, FakeSystem) -> Void) {
        withEmptyDefaults { defaults in
            let system = FakeSystem()
            let hotKeys = HotKeys(
                defaults: defaults, registrar: FakeHotKeyRegistrar(), onPress: { _ in }, onChange: {})
            let folder = FileManager.default.temporaryDirectory.appending(
                path: "ciel-settings-" + UUID().uuidString)
            let settings = SettingsController(
                hotKeys: hotKeys, speech: SpeechModelStore(folder: folder), updater: Updater(),
                spotlight: SpotlightShortcuts { system.symbolicHotKeys }, open: { system.opened.append($0) })
            body(settings, hotKeys, system)
        }
    }
}
