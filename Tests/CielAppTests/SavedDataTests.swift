import Carbon
import CielCore
import Foundation
import Testing

@testable import CielApp

@MainActor @Suite("Shipped ids and stored formats survive renames")
struct SavedDataTests {
    private nonisolated static let shippedWindowIDs: [String: WindowAction] = [
        "window.leftHalf": .leftHalf, "window.rightHalf": .rightHalf,
        "window.firstThreeFourths": .firstThreeFourths, "window.lastThreeFourths": .lastThreeFourths,
        "window.centerThreeFourths": .centerThreeFourths, "window.maximize": .maximize,
        "window.almostMaximize": .almostMaximize, "window.center": .center,
        "window.nextDisplay": .nextDisplay, "window.previousDisplay": .previousDisplay,
        "window.restore": .restore, "window.topHalf": .topHalf, "window.bottomHalf": .bottomHalf,
        "window.topLeft": .topLeft, "window.topRight": .topRight, "window.bottomLeft": .bottomLeft,
        "window.bottomRight": .bottomRight, "window.minimize": .minimize,
    ]

    private nonisolated static let shippedShortcutKeys: [(String, HotKeyCommand)] =
        [("launcher", .launcher)] + shippedWindowIDs.map { ($0.key, .window($0.value)) }

    @Test func everyShippedEntryIDStillResolves() {
        let entries = Dictionary(
            uniqueKeysWithValues: (SearchEntry.commands + SearchEntry.utilities).map { ($0.id, $0) })
        for (id, action) in Self.shippedWindowIDs {
            #expect(entries[id]?.action == action, "\(id)")
        }
        #expect(entries["settings"]?.utility == .settings)
        #expect(entries["rescan"]?.utility == .rescan)
    }

    @Test func togglesAreOnUntilTurnedOffUnderTheirShippedKeys() {
        withEmptyDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            #expect(preferences.animations)
            #expect(preferences.showMenuBarIcon)
            preferences.animations = false
            preferences.showMenuBarIcon = false
            #expect(defaults.object(forKey: "animations") as? Bool == false)
            #expect(defaults.object(forKey: "showMenuBarIcon") as? Bool == false)
            #expect(!preferences.animations)
            #expect(!preferences.showMenuBarIcon)
        }
    }

    @Test(arguments: shippedShortcutKeys)
    func aShortcutSavedUnderAShippedKeyFiresItsCommand(key: String, command: HotKeyCommand) throws {
        try withEmptyDefaults { defaults in
            let saved = Shortcut(keyCode: UInt32(kVK_F13), modifiers: UInt32(controlKey))
            defaults.set(try JSONEncoder().encode([key: saved]), forKey: "shortcuts")
            let registrar = FakeHotKeyRegistrar()
            var pressed: [HotKeyCommand] = []
            let hotKeys = HotKeys(
                defaults: defaults, registrar: registrar, onPress: { pressed.append($0) }, onChange: {})
            registrar.press(saved)
            #expect(pressed == [command])
            let changed = Shortcut(keyCode: UInt32(kVK_F14), modifiers: UInt32(controlKey))
            try hotKeys.update(command, to: changed)
            let data = try #require(defaults.data(forKey: "shortcuts"))
            #expect(try JSONDecoder().decode([String: Shortcut].self, from: data)[key] == changed)
        }
    }

    @Test func launcherShortcutDefaultsToControlOptionSpace() {
        withEmptyDefaults { defaults in
            let hotKeys = HotKeys(
                defaults: defaults, registrar: FakeHotKeyRegistrar(), onPress: { _ in }, onChange: {})
            #expect(hotKeys.shortcut(for: .launcher) == .launcher)
        }
    }

    @Test func shortcutsInTheStoredFormatStillLoad() {
        withEmptyDefaults { defaults in
            defaults.set(
                Data(
                    #"{"launcher":{"keyCode":49,"modifiers":256},"window.maximize":{"keyCode":36,"modifiers":6144}}"#
                        .utf8),
                forKey: "shortcuts")
            let hotKeys = HotKeys(
                defaults: defaults, registrar: FakeHotKeyRegistrar(), onPress: { _ in }, onChange: {})
            #expect(hotKeys.shortcut(for: .launcher)?.display == "⌘Space")
            #expect(hotKeys.shortcut(for: .window(.maximize))?.display == "⌃⌥↩")
        }
    }

    @Test func bundleIdentifierMatchesInfoPlist() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil)
        #expect((info as? [String: Any])?["CFBundleIdentifier"] as? String == AppIdentity.bundleIdentifier)
    }
}
