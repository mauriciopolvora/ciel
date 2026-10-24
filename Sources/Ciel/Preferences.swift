import Foundation

/// An unset toggle reads as on, so no reader depends on `register(defaults:)` running first.
struct Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var animations: Bool {
        get { flag("animations") }
        nonmutating set { defaults.set(newValue, forKey: "animations") }
    }

    var showMenuBarIcon: Bool {
        get { flag("showMenuBarIcon") }
        nonmutating set { defaults.set(newValue, forKey: "showMenuBarIcon") }
    }

    private func flag(_ key: String) -> Bool {
        defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }
}
