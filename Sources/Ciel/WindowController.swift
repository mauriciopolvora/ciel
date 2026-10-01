import AppKit
import ApplicationServices
import CielCore

struct DisplaySnapshot: Sendable {
    let full: CGRect
    let visible: CGRect

    @MainActor static func current() -> [DisplaySnapshot] {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        return screens.map {
            DisplaySnapshot(
                full: WindowGeometry.accessibilityRect($0.frame, primaryHeight: primaryHeight),
                visible: WindowGeometry.accessibilityRect($0.visibleFrame, primaryHeight: primaryHeight))
        }.sorted { $0.full.minX == $1.full.minX ? $0.full.minY < $1.full.minY : $0.full.minX < $1.full.minX }
    }
}

/// The main actor owns the current capture. AX references never leave the worker.
@MainActor final class WindowController {
    private let worker = WindowWorker()
    private var captureTask: Task<WindowSelection, Never>?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        // The SDK imports this immutable key as a mutable C global. The public
        // string value avoids sharing imported mutable state across executors.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func capture(pid: pid_t?) {
        let worker = worker
        captureTask = Task { await worker.capture(pid: pid) }
    }

    func perform(
        _ action: WindowAction, displays: [DisplaySnapshot],
        completion: @escaping @MainActor @Sendable (Result<String, Error>) -> Void
    ) {
        // Pin this capture before awaiting it. Reopening the launcher can create
        // another capture without changing a command that is already pending.
        let capture = captureTask
        let worker = worker
        Task {
            let selection: WindowSelection
            if let capture {
                selection = await capture.value
            } else {
                selection = await worker.capture(pid: nil)
            }
            completion(await worker.perform(action, selection: selection, displays: displays))
        }
    }
}

/// Synchronous AX IPC and polling use a dedicated queue, not the main actor or
/// Swift's shared cooperative executor. The actor confines all mutable AX state.
private actor WindowWorker {
    private nonisolated let executor = WindowExecutor()
    private let engine = WindowOperationEngine(accessibility: SystemWindowAccessibility())

    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

    func capture(pid: pid_t?) -> WindowSelection {
        engine.capture(pid: pid) { [weak self] id in
            Task { await self?.releaseCapture(id) }
        }
    }

    private func releaseCapture(_ id: UUID) { engine.releaseCapture(id) }

    func perform(
        _ action: WindowAction, selection: WindowSelection, displays: [DisplaySnapshot]
    ) -> Result<String, Error> {
        Result {
            try PerformanceTrace.measure("WindowOperation") {
                try engine.perform(action, selection: selection, displays: displays)
            }
        }
    }
}

private final class WindowExecutor: SerialExecutor {
    private let queue = DispatchQueue(label: "app.ciel.windows", qos: .userInitiated)

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async { job.runSynchronously(on: executor) }
    }
}

enum WindowError: LocalizedError, Equatable, Sendable {
    case permission, noWindow, fullScreen, noHistory, oneDisplay, unsupported, timedOut
    case rejected(Int32)

    var isTemporaryMessagingFailure: Bool {
        self == .rejected(AXError.cannotComplete.rawValue)
    }

    var errorDescription: String? {
        switch self {
        case .permission: return "Allow Accessibility access in Settings to move windows."
        case .noWindow: return "Focus an app window, then try again."
        case .fullScreen: return "Exit macOS full screen before moving this window."
        case .noHistory: return "Move or resize this window first."
        case .oneDisplay: return "Connect another display to use this command."
        case .unsupported: return "This window does not support that action."
        case .timedOut: return "The app did not finish the window change. Try again."
        case .rejected: return "The app did not accept the window change. Try again."
        }
    }
}
