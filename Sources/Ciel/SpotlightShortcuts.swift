import AppKit
import Carbon

/// macOS handles the Spotlight shortcuts before any app hot key, so a Ciel shortcut that matches an active one
/// registers but never fires.
struct SpotlightShortcuts {
    static let commandSpace = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
    static let keyboardSettings = URL(
        string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
    private static let shipped = [
        "64": commandSpace,
        "65": Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | optionKey)),
    ]
    private static let modifiers = [
        (NSEvent.ModifierFlags.command, cmdKey), (.option, optionKey), (.control, controlKey),
        (.shift, shiftKey),
    ]

    let read: () -> [String: Any]?

    static var system: SpotlightShortcuts {
        SpotlightShortcuts {
            let domain = "com.apple.symbolichotkeys" as CFString
            CFPreferencesAppSynchronize(domain)
            return CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
        }
    }

    func owns(_ shortcut: Shortcut) -> Bool { active.contains(shortcut) }

    /// An id missing from the saved list still has its shipped shortcut.
    var active: [Shortcut] {
        let saved = read() ?? [:]
        return Self.shipped.compactMap { id, shipped in
            guard let entry = saved[id] as? [String: Any] else { return shipped }
            guard entry["enabled"] as? Bool ?? true else { return nil }
            guard let value = entry["value"] as? [String: Any] else { return shipped }
            guard let parameters = value["parameters"] as? [Int], parameters.count == 3 else { return nil }
            let flags = NSEvent.ModifierFlags(rawValue: UInt(parameters[2]))
            let carbon = Self.modifiers.reduce(0) { flags.contains($1.0) ? $0 | $1.1 : $0 }
            return Shortcut(keyCode: UInt32(parameters[1]), modifiers: UInt32(carbon))
        }
    }
}
