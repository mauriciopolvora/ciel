import CielCore
import Foundation
import Testing

@testable import CielApp

@MainActor @Suite("Shipped ids and stored formats survive renames")
struct SavedDataTests {
    private let shippedWindowIDs: [String: WindowAction] = [
        "window.leftHalf": .leftHalf, "window.rightHalf": .rightHalf,
        "window.firstThreeFourths": .firstThreeFourths, "window.lastThreeFourths": .lastThreeFourths,
        "window.centerThreeFourths": .centerThreeFourths, "window.maximize": .maximize,
        "window.almostMaximize": .almostMaximize, "window.center": .center,
        "window.nextDisplay": .nextDisplay, "window.previousDisplay": .previousDisplay,
        "window.restore": .restore, "window.topHalf": .topHalf, "window.bottomHalf": .bottomHalf,
        "window.topLeft": .topLeft, "window.topRight": .topRight, "window.bottomLeft": .bottomLeft,
        "window.bottomRight": .bottomRight, "window.minimize": .minimize,
    ]

    @Test func everyShippedEntryIDStillResolves() {
        let entries = Dictionary(
            uniqueKeysWithValues: (SearchEntry.commands + SearchEntry.utilities).map { ($0.id, $0) })
        for (id, action) in shippedWindowIDs {
            #expect(entries[id]?.action == action, "\(id)")
        }
        for id in ["settings", "rescan"] {
            #expect(entries[id]?.kind == .utility, "\(id)")
        }
    }

    @Test func everyShippedShortcutNameStillBindsItsAction() {
        let bound = Dictionary(uniqueKeysWithValues: WindowAction.allCases.map { ($0.id, $0) })
        for (name, action) in shippedWindowIDs {
            #expect(bound[name] == action, "\(name)")
        }
        withEmptyDefaults { defaults in
            #expect(HotKeys(defaults: defaults).shortcuts["launcher"] == .launcher)
        }
    }

    @Test func shortcutsInTheStoredFormatStillLoad() {
        withEmptyDefaults { defaults in
            defaults.set(
                Data(
                    #"{"launcher":{"keyCode":49,"modifiers":256},"window.maximize":{"keyCode":36,"modifiers":6144}}"#
                        .utf8),
                forKey: "shortcuts")
            let hotKeys = HotKeys(defaults: defaults)
            #expect(hotKeys.shortcuts["launcher"]?.display == "⌘Space")
            #expect(hotKeys.shortcuts["window.maximize"]?.display == "⌃⌥↩")
        }
    }

    @Test func bundleIdentifierMatchesInfoPlist() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil)
        #expect((info as? [String: Any])?["CFBundleIdentifier"] as? String == AppIdentity.bundleIdentifier)
    }

    private func withEmptyDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "ciel.saved-data.test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
