import Foundation

struct Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var animations: Bool {
        get { onUnlessTurnedOff("animations") }
        nonmutating set { defaults.set(newValue, forKey: "animations") }
    }

    var showMenuBarIcon: Bool {
        get { onUnlessTurnedOff("showMenuBarIcon") }
        nonmutating set { defaults.set(newValue, forKey: "showMenuBarIcon") }
    }

    private func onUnlessTurnedOff(_ key: String) -> Bool {
        defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }
}
