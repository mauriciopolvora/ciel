import Testing

@testable import CielApp

@Suite
struct WindowAccessTests {
    @Test func aFirstRunWithoutAccessDoesNotWarn() {
        withEmptyDefaults { defaults in
            #expect(!Preferences(defaults: defaults).windowAccessLost(trusted: false))
        }
    }

    @Test func accessLostAfterAGrantWarnsOnceUntilGrantedAgain() {
        withEmptyDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            #expect(!preferences.windowAccessLost(trusted: true))
            #expect(defaults.object(forKey: "hadWindowAccess") as? Bool == true)
            let launches = [false, false, true, false].map {
                Preferences(defaults: defaults).windowAccessLost(trusted: $0)
            }
            #expect(launches == [true, false, false, true])
        }
    }

    @Test func aGrantDuringARunCountsForTheNextLaunch() {
        withEmptyDefaults { defaults in
            Preferences(defaults: defaults).hadWindowAccess = true
            #expect(Preferences(defaults: defaults).windowAccessLost(trusted: false))
        }
    }
}
