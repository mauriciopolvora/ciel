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

struct ForeignProcess: Equatable, Sendable {
    let pid: pid_t

    init?(_ pid: pid_t?) {
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        self.pid = pid
    }

    @MainActor static var frontmost: ForeignProcess? {
        ForeignProcess(NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }
}

struct WindowTarget: Sendable {
    fileprivate let selection: Task<WindowSelection, Never>
}

enum WindowOutcome: Equatable, Sendable {
    case applied, sizeLimited, positionLimited

    var notice: String? {
        switch self {
        case .applied: nil
        case .sizeLimited: "The app limited the window size."
        case .positionLimited: "The app limited the window position."
        }
    }
}

@MainActor final class WindowController {
    private let worker = WindowWorker()
    private(set) var isBusy = false

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        // The SDK imports this immutable key as a mutable C global. The public
        // string value avoids sharing imported mutable state across executors.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func capture(_ process: ForeignProcess?) -> WindowTarget {
        let worker = worker
        return WindowTarget(selection: Task { await worker.capture(process) })
    }

    func perform(
        _ action: WindowAction, on target: WindowTarget,
        completion: @escaping @MainActor @Sendable (Result<WindowOutcome, Error>) -> Void
    ) {
        let displays = DisplaySnapshot.current()
        let worker = worker
        isBusy = true
        Task {
            let result = await worker.perform(action, selection: target.selection.value, displays: displays)
            isBusy = false
            completion(result)
        }
    }
}

/// Synchronous AX IPC and polling use a dedicated queue, not the main actor or
/// Swift's shared cooperative executor. The actor confines all mutable AX state.
private actor WindowWorker {
    private nonisolated let executor = WindowExecutor()
    private let engine = WindowOperationEngine(accessibility: SystemWindowAccessibility())

    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

    func capture(_ process: ForeignProcess?) -> WindowSelection {
        engine.capture(process) { [weak self] id in
            Task { await self?.releaseCapture(id) }
        }
    }

    private func releaseCapture(_ id: UUID) { engine.releaseCapture(id) }

    func perform(
        _ action: WindowAction, selection: WindowSelection, displays: [DisplaySnapshot]
    ) -> Result<WindowOutcome, Error> {
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
