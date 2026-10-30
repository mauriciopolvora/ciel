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

    var hadWindowAccess: Bool {
        get { defaults.bool(forKey: "hadWindowAccess") }
        nonmutating set { defaults.set(newValue, forKey: "hadWindowAccess") }
    }

    /// An ad-hoc rebuild or update changes the code identity, so macOS keeps showing access as
    /// enabled while denying it. Reports that once, then waits for the next grant.
    func windowAccessLost(trusted: Bool) -> Bool {
        defer { hadWindowAccess = trusted }
        return hadWindowAccess && !trusted
    }

    private func onUnlessTurnedOff(_ key: String) -> Bool {
        defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }
}
