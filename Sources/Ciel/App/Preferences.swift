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

    var speechEnabled: Bool {
        get { defaults.bool(forKey: "speechEnabled") }
        nonmutating set { defaults.set(newValue, forKey: "speechEnabled") }
    }

    var onboarded: Bool {
        get { defaults.bool(forKey: "onboarded") }
        nonmutating set { defaults.set(newValue, forKey: "onboarded") }
    }

    var hadWindowAccess: Bool {
        get { defaults.bool(forKey: "hadWindowAccess") }
        nonmutating set { defaults.set(newValue, forKey: "hadWindowAccess") }
    }

    func windowAccessLost(trusted: Bool) -> Bool {
        defer { hadWindowAccess = trusted }
        return hadWindowAccess && !trusted
    }

    func dropRetiredKeys() {
        for key in ["designPreview.settings", "designPreview.launcher"] { defaults.removeObject(forKey: key) }
    }

    private func onUnlessTurnedOff(_ key: String) -> Bool {
        defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }
}
