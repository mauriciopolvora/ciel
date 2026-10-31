import AppKit
import QuartzCore

@MainActor final class DictationPill {
    private let view = PillView()
    private var activity = Dictation.Activity.idle
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: PillView.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = view
        return panel
    }()

    func show(_ next: Dictation.Activity) {
        let previous = activity
        activity = next
        switch next {
        case .idle: if previous != .idle { hide() }
        case .listening:
            view.listen()
            if previous == .idle { appear() }
        case .transcribing: view.transcribe()
        }
    }

    func level(_ rms: Float) {
        if activity == .listening { view.level(rms) }
    }

    private func appear() {
        let screen =
            NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - PillView.size.width / 2, y: frame.minY + 24))
        }
        panel.alphaValue = Theme.reduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        guard !Theme.reduceMotion else { return }
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = Theme.reduceMotion ? 0 : Theme.hoverDuration
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.activity == .idle else { return }
                    self.panel.orderOut(nil)
                    self.view.stop()
                }
            })
    }
}

final class PillView: SurfaceView {
    static let size = NSSize(width: 96, height: 32)
    private static let weights: [CGFloat] = [1, 0.85, 0.7, 0.55, 0.4]
    private static let barWidth: CGFloat = 3
    private static let restHeight: CGFloat = 3
    private static let peakHeight: CGFloat = 16
    private static let quietDecibels: CGFloat = -50
    private static let loudDecibels: CGFloat = -10
    private static let decay: CGFloat = 0.6
    private let bars = (0..<9).map { _ in CALayer() }
    private var history = [CGFloat](repeating: 0, count: 5)

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        isFloating = true
        isCapsule = true
        refreshSurface()
        for bar in bars {
            bar.cornerRadius = Self.barWidth / 2
            layer?.addSublayer(bar)
        }
        layout(animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func refreshSurface() {
        super.refreshSurface()
        for bar in bars { bar.backgroundColor = Theme.cg(Theme.text, in: self) }
    }

    func listen() {
        stop()
        history = history.map { _ in 0 }
        layout(animated: false)
    }

    func level(_ rms: Float) {
        let decibels = 20 * log10(max(CGFloat(rms), 0.000_01))
        let target = min(
            max((decibels - Self.quietDecibels) / (Self.loudDecibels - Self.quietDecibels), 0), 1)
        let eased = target > history[0] ? target : history[0] * Self.decay + target * (1 - Self.decay)
        history = [eased] + history.dropLast()
        layout(animated: !Theme.reduceMotion)
    }

    func transcribe() {
        history = history.map { _ in 0 }
        layout(animated: !Theme.reduceMotion)
        guard !Theme.reduceMotion else {
            for bar in bars { bar.opacity = 0.5 }
            return
        }
        let start = CACurrentMediaTime()
        for (index, bar) in bars.enumerated() {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.25
            pulse.duration = 0.45
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.beginTime = start + Double(index) * 0.1
            pulse.fillMode = .backwards
            bar.add(pulse, forKey: "pulse")
        }
    }

    func stop() {
        for bar in bars {
            bar.removeAllAnimations()
            bar.opacity = 1
        }
    }

    private func layout(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.1)
        let gap = Self.barWidth
        let left = (Self.size.width - CGFloat(bars.count) * (Self.barWidth + gap) + gap) / 2
        let center = bars.count / 2
        for (index, bar) in bars.enumerated() {
            let distance = abs(index - center)
            let height =
                Self.restHeight + (Self.peakHeight - Self.restHeight) * history[distance]
                * Self.weights[distance]
            bar.frame = NSRect(
                x: left + CGFloat(index) * (Self.barWidth + gap), y: (Self.size.height - height) / 2,
                width: Self.barWidth, height: height)
        }
        CATransaction.commit()
    }
}
