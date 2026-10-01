import Foundation

/// Own the notification token separately from actor state. Releasing the owner
/// unregisters the callback without reading actor-isolated storage in deinit.
final class NotificationObservation {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(
        center: NotificationCenter, name: Notification.Name,
        handler: @escaping @MainActor @Sendable () -> Void
    ) {
        self.center = center
        token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            // This observer always uses OperationQueue.main.
            MainActor.assumeIsolated { handler() }
        }
    }

    deinit { center.removeObserver(token) }
}
