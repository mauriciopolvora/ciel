import Foundation

/// A main-actor owner can hold a C or Foundation registration this way without reading isolated state in its deinit.
final class Cleanup {
    private let release: () -> Void

    init(_ release: @escaping () -> Void) { self.release = release }

    deinit { release() }
}

extension NotificationCenter {
    func observe(_ name: Notification.Name, handler: @escaping @MainActor @Sendable () -> Void) -> Cleanup {
        let token = addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return Cleanup { [self] in removeObserver(token) }
    }
}
