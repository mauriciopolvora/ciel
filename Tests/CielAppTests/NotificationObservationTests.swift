import Foundation
import Testing

@testable import CielApp

@MainActor @Suite
struct NotificationObservationTests {
    @Test func releasingOwnerRemovesItsCallbackOnly() {
        let center = NotificationCenter()
        let name = Notification.Name("ciel.fixture.observation")
        var calls = 0
        var otherCalls = 0
        var observation: NotificationObservation? = NotificationObservation(center: center, name: name) {
            calls += 1
        }
        let other = NotificationObservation(center: center, name: name) { otherCalls += 1 }
        #expect(observation != nil)
        center.post(name: name, object: nil)
        #expect(calls == 1)
        #expect(otherCalls == 1)
        observation = nil
        center.post(name: name, object: nil)
        #expect(calls == 1)
        #expect(otherCalls == 2)
        withExtendedLifetime(other) {}
    }
}
