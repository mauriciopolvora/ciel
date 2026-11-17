import AppKit
import QuartzCore

/// Times what a person waits for: the hotkey to the panel on screen, key and focused; a keystroke to its results;
/// an arrow key to the moved selection. Each ends at the target time of the first display frame after the change.
@MainActor struct Interactions {
    private(set) var open = Samples()
    private(set) var keystroke = Samples()
    private(set) var arrow = Samples()

    @MainActor struct Samples {
        var frame: [Double] = []
        var mainThread: [Double] = []

        var report: [String: Any] {
            [
                "samples": frame.count,
                "frameMedianMilliseconds": PerformanceCheck.percentile(frame.sorted(), fraction: 0.5),
                "frameP95Milliseconds": PerformanceCheck.percentile(frame.sorted(), fraction: 0.95),
                "mainThreadMedianMilliseconds": PerformanceCheck.percentile(
                    mainThread.sorted(), fraction: 0.5),
                "mainThreadP95Milliseconds": PerformanceCheck.percentile(mainThread.sorted(), fraction: 0.95),
            ]
        }
    }

    var report: [String: Any] {
        ["open": open.report, "keystroke": keystroke.report, "arrow": arrow.report]
    }

    static func measure(launcher: LauncherView, panel: LauncherPanel, open: () -> Void) async throws
        -> Interactions
    {
        let frames = FrameClock()
        let editor = panel.fieldEditor
        var result = Interactions()
        func ready() -> Bool {
            panel.occlusionState.contains(.visible) && panel.isKeyWindow
                && panel.firstResponder === launcher.searchField.currentEditor()
        }
        for _ in 0..<30 {
            panel.dismiss()
            try await frames.wait(3, on: launcher)
            let started = CACurrentMediaTime()
            open()
            result.open.mainThread.append(milliseconds(since: started))
            var shown = try await frames.next(on: launcher)
            while !ready() { shown = try await frames.next(on: launcher) }
            result.open.frame.append((shown - started) * 1_000)
        }
        for word in ["calculator", "safari", "terminal", "left half", "zzzz", "calculator", "settings"] {
            for character in word {
                try await result.keystroke.time(on: launcher, frames) {
                    editor.insertText(
                        String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
                }
            }
            for _ in word {
                try await result.keystroke.time(on: launcher, frames) { editor.deleteBackward(nil) }
            }
        }
        editor.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await frames.wait(2, on: launcher)
        for _ in 0..<5 {
            for command in Array(repeating: #selector(NSResponder.moveDown(_:)), count: 6)
                + Array(repeating: #selector(NSResponder.moveUp(_:)), count: 6)
            {
                try await result.arrow.time(on: launcher, frames) { editor.doCommand(by: command) }
            }
        }
        editor.deleteBackward(nil)
        return result
    }

    private static func milliseconds(since start: CFTimeInterval) -> Double {
        (CACurrentMediaTime() - start) * 1_000
    }
}

extension Interactions.Samples {
    @MainActor mutating func time(on view: NSView, _ frames: FrameClock, _ action: () -> Void) async throws {
        let started = CACurrentMediaTime()
        action()
        mainThread.append((CACurrentMediaTime() - started) * 1_000)
        frame.append((try await frames.next(on: view) - started) * 1_000)
    }
}

/// Waits for the next display frame of a view's screen and returns its target presentation time.
@MainActor final class FrameClock: NSObject {
    private var waiting: CheckedContinuation<CFTimeInterval, Error>?
    private var link: CADisplayLink?
    private var generation = 0

    func next(on view: NSView) async throws -> CFTimeInterval {
        try await withCheckedThrowingContinuation { continuation in
            waiting = continuation
            let link = view.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
            generation += 1
            let current = generation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.generation == current, self.waiting != nil else { return }
                self.finish(.failure(FrameClockError.noFrame))
            }
        }
    }

    func wait(_ count: Int, on view: NSView) async throws {
        for _ in 0..<count { _ = try await next(on: view) }
    }

    @objc private func tick(_ link: CADisplayLink) { finish(.success(link.targetTimestamp)) }

    private func finish(_ result: Result<CFTimeInterval, Error>) {
        link?.invalidate()
        link = nil
        waiting?.resume(with: result)
        waiting = nil
    }

    private enum FrameClockError: LocalizedError {
        case noFrame
        var errorDescription: String? { "No display frame arrived within 2 seconds" }
    }
}
