import AppKit
import Carbon
import Testing

@testable import CielApp

@MainActor @Suite
struct SettingsSpotlightTests {
    @Test func recordingAShortcutSpotlightHoldsKeepsTheOldOneUntilSpotlightLetsGo() {
        withSettings { settings, hotKeys, system in
            settings.recorders[.launcher]?.accept(SpotlightShortcuts.commandSpace)
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
            #expect(settings.spotlightGuide.held == SpotlightShortcuts.commandSpace)
            #expect(system.opened == [SpotlightShortcuts.keyboardSettings])
            settings.spotlightGuide.tick()
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
            system.symbolicHotKeys = ["64": ["enabled": false]]
            settings.spotlightGuide.tick()
            #expect(hotKeys.shortcut(for: .launcher) == SpotlightShortcuts.commandSpace)
            #expect(settings.recorders[.launcher]?.shortcut == SpotlightShortcuts.commandSpace)
            #expect(settings.spotlightGuide.held == nil)
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

    @Test func aFreeShortcutIsSavedAtOnce() {
        withSettings { settings, hotKeys, system in
            let shiftCommandSpace = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))
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
                hotKeys: hotKeys, speech: SpeechModelStore(folder: folder),
                spotlight: SpotlightShortcuts { system.symbolicHotKeys }, open: { system.opened.append($0) })
            body(settings, hotKeys, system)
        }
    }
}
