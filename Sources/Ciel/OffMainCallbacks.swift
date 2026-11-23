import AVFoundation
import AppKit

// WARNING: Apple runs the launch, microphone and tap handlers off the main thread, where a main actor closure traps.
enum OffMainCallbacks {
    // WARNING: AppKit calls handler on a LaunchServices queue.
    @MainActor static func launchApplication(
        at url: URL, configuration: NSWorkspace.OpenConfiguration,
        handler: @escaping @Sendable (NSRunningApplication?, (any Error)?) -> Void
    ) {
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: handler)
    }

    // WARNING: AVFoundation calls handler on an arbitrary queue.
    static func requestMicrophoneAccess(handler: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: handler)
    }

    // WARNING: the audio engine calls block on its audio thread.
    static func tap(
        _ node: AVAudioNode, bufferSize: AVAudioFrameCount, format: AVAudioFormat,
        block: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {
        node.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: block)
    }

    @MainActor static func animate(_ changes: (NSAnimationContext) -> Void) {
        NSAnimationContext.runAnimationGroup(changes)
    }

    @MainActor static func animate(
        _ changes: (NSAnimationContext) -> Void, completion: @escaping @Sendable () -> Void
    ) {
        NSAnimationContext.runAnimationGroup(changes, completionHandler: completion)
    }

    static func delegateTask(_ session: URLSession, with request: URLRequest) -> URLSessionDataTask {
        session.dataTask(with: request)
    }
}
