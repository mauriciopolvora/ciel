import AVFoundation
import AppKit

/// Every call to an Apple API that can run its handler off the main thread. A main actor closure traps there
/// on entry, so each handler here is `@Sendable` without `@MainActor`, and the compiler rejects a main actor
/// closure. A caller hops to the main actor inside its handler. `scripts/lint-callbacks.sh` fails when one of
/// these APIs is called outside this file.
enum OffMainCallbacks {
    /// AppKit calls `handler` on a LaunchServices queue.
    @MainActor static func launchApplication(
        at url: URL, configuration: NSWorkspace.OpenConfiguration,
        handler: @escaping @Sendable (NSRunningApplication?, (any Error)?) -> Void
    ) {
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: handler)
    }

    /// AVFoundation calls `handler` on an arbitrary queue.
    static func requestMicrophoneAccess(handler: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: handler)
    }

    /// The audio engine calls `block` on its audio thread.
    static func tap(
        _ node: AVAudioNode, bufferSize: AVAudioFrameCount, format: AVAudioFormat,
        block: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {
        node.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: block)
    }

    /// No handler runs after the changes, so nothing here runs off the main thread.
    @MainActor static func animate(_ changes: (NSAnimationContext) -> Void) {
        NSAnimationContext.runAnimationGroup(changes)
    }

    @MainActor static func animate(
        _ changes: (NSAnimationContext) -> Void, completion: @escaping @Sendable () -> Void
    ) {
        NSAnimationContext.runAnimationGroup(changes, completionHandler: completion)
    }

    /// The session delegate gets this task's events. No completion handler runs.
    static func delegateTask(_ session: URLSession, with request: URLRequest) -> URLSessionDataTask {
        session.dataTask(with: request)
    }
}
