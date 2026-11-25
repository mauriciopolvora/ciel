import AppKit
import QuartzCore

@MainActor final class DictationPill {
    private let view = PillView()
    private var activity = Dictation.Activity.idle
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: PillLayout.canvas),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = view
        view.onRest = { [weak panel] in panel?.orderOut(nil) }
        return panel
    }()

    func show(_ next: Dictation.Activity) {
        activity = next
        switch next {
        case .idle: view.hide()
        case .listening:
            if !panel.isVisible { appear() }
            view.listen()
        case .transcribing: view.transcribe()
        }
    }

    func level(_ rms: [Float], every interval: Double) {
        if activity == .listening { view.hear(rms, every: interval) }
    }

    func text(committed: String, tentative: String) {
        if activity != .idle { view.text(committed: committed, tentative: tentative) }
    }

    private func appear() {
        let screen =
            NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(
                NSPoint(
                    x: frame.midX - PillLayout.canvas.width / 2, y: frame.minY + 24 - PillLayout.margin))
        }
        panel.orderFrontRegardless()
    }
}

final class PillView: NSView {
    var onRest: () -> Void = {}
    private let stack = CALayer()
    private let waveformPill = CALayer()
    private let bars = CAShapeLayer()
    private let transcriptPill = CALayer()
    private let words = TranscriptLayer()
    private let font = NSFont.systemFont(ofSize: 13)
    private var mode = Mode.idle
    private var resting = true
    private var reduceMotion = false
    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval?
    private var clock = 0.0
    private var meter = LevelMeter()
    private var waveform = Waveform()
    private var amplitudes = [Double](repeating: 0, count: Waveform.bars)
    private var layout = TranscriptLayout(maxWidth: PillLayout.textWidth)
    private var presence = Spring(0, response: PillView.enter)
    private var reveal = Spring(0, response: PillView.enter)
    private var width = Spring(PillLayout.waveform.width, response: PillView.grow)
    private var height = Spring(PillLayout.waveform.height, response: PillView.grow)
    private var lift = Spring(0, response: PillView.grow)
    private var scroll = Spring(0, response: PillView.grow)

    private enum Mode { case idle, listening, transcribing }

    init() {
        super.init(frame: NSRect(origin: .zero, size: PillLayout.canvas))
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.addSublayer(stack)
        stack.addSublayer(transcriptPill)
        stack.addSublayer(waveformPill)
        waveformPill.addSublayer(bars)
        transcriptPill.addSublayer(words)
        transcriptPill.cornerRadius = PillLayout.radius
        waveformPill.cornerRadius = PillLayout.radius
        words.needsDisplayOnBoundsChange = true
        words.baseline = (TranscriptLayout.lineHeight - font.ascender + font.descender) / 2 - font.descender
        stack.anchorPoint = CGPoint(x: 0.5, y: PillLayout.margin / bounds.height)
        stack.bounds = bounds
        stack.position = CGPoint(x: bounds.midX, y: PillLayout.margin)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Dictation")
        refreshColors()
        scale(window?.backingScaleFactor ?? 2)
        apply()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        scale(window?.backingScaleFactor ?? 2)
    }

    var visibility: Double { presence.value }
    var showsTranscript: Bool { reveal.value > 0 }
    var lineCount: Int { layout.lines.count }
    var olderLinesFade: CGFloat { words.placement.topFade }
    var transcriptFrame: CGRect {
        CGRect(
            x: (bounds.width - width.value) / 2, y: PillLayout.margin + lift.value, width: width.value,
            height: height.value)
    }

    func listen(reduceMotion: Bool = Theme.reduceMotion) {
        self.reduceMotion = reduceMotion
        mode = .listening
        resting = false
        refreshColors()
        if presence.isSettled, presence.value == 0 { reset() } else { collapse() }
        presence.response = Self.enter
        presence.target = 1
        changed()
    }

    func transcribe() {
        mode = .transcribing
        changed()
    }

    func hide() {
        mode = .idle
        presence.response = Self.exit
        presence.target = 0
        changed()
    }

    func hear(_ rms: [Float], every interval: Double) { meter.hear(rms, every: interval) }

    func text(committed: String, tentative: String) {
        let text = NSMutableAttributedString(string: committed, attributes: attributes(Theme.text))
        text.append(
            NSAttributedString(
                string: committed.isEmpty || tentative.isEmpty ? tentative : " " + tentative,
                attributes: attributes(Theme.secondary)))
        let next = TranscriptLayout(text, maxWidth: PillLayout.textWidth)
        transcriptChanged(text.string)
        guard !next.lines.isEmpty else {
            collapse()
            return changed()
        }
        if !layout.lines.isEmpty || reveal.value > 0 {
            let limit = CGFloat(PillLayout.maxLines) * TranscriptLayout.lineHeight
            let grown = CGFloat(next.lines.count - layout.lines.count) * TranscriptLayout.lineHeight
            scroll.shift(by: -min(max(grown, -limit), limit))
        }
        layout = next
        words.lines = zip(next.lines, next.widths).suffix(PillLayout.maxLines + 1)
        let size = PillLayout.transcript(next)
        width.target = size.width
        height.target = size.height
        lift.target = PillLayout.waveform.height + PillLayout.gap
        reveal.target = 1
        changed()
    }

    func advance(by seconds: Double) {
        clock += seconds
        meter.advance(by: seconds)
        waveform.advance(by: seconds, level: mode == .listening ? meter.level : 0)
        let target: [Double] =
            switch mode {
            case .listening: waveform.amplitudes(flowing: !reduceMotion)
            case .transcribing where !reduceMotion: Waveform.ripple(at: clock)
            case .transcribing: Array(repeating: 0, count: Waveform.bars)
            case .idle: amplitudes
            }
        let blend = 1 - exp(-seconds / 0.05)
        amplitudes = zip(amplitudes, target).map { $0 + ($1 - $0) * blend }
        for spring in springs { self[keyPath: spring].advance(by: seconds) }
        apply()
        restIfHidden()
    }

    private var springs: [ReferenceWritableKeyPath<PillView, Spring>] {
        [\.presence, \.reveal, \.width, \.height, \.lift, \.scroll]
    }

    private func changed() {
        if reduceMotion {
            for spring in springs { self[keyPath: spring].snap(to: self[keyPath: spring].target) }
        }
        apply()
        restIfHidden()
        if mode != .idle || !presence.isSettled { start() }
    }

    private func transcriptChanged(_ text: String) {
        guard text != accessibilityValue() as? String else { return }
        setAccessibilityValue(text)
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    private func collapse() {
        transcriptChanged("")
        layout = TranscriptLayout(maxWidth: PillLayout.textWidth)
        width.target = PillLayout.waveform.width
        height.target = PillLayout.waveform.height
        lift.target = 0
        reveal.target = 0
        scroll.target = 0
        if reveal.value == 0 {
            words.lines = []
            for spring in springs where spring != \.presence {
                self[keyPath: spring].snap(to: self[keyPath: spring].target)
            }
        }
    }

    private func reset() {
        meter = LevelMeter()
        waveform = Waveform()
        amplitudes = amplitudes.map { _ in 0 }
        reveal.snap(to: 0)
        collapse()
    }

    private func restIfHidden() {
        guard !resting, mode == .idle, presence.isSettled, presence.value == 0 else { return }
        resting = true
        link?.invalidate()
        link = nil
        reset()
        apply()
        onRest()
    }

    private func start() {
        guard link == nil, window != nil else { return }
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastFrame = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let seconds = lastFrame.map { link.targetTimestamp - $0 } ?? link.duration
        lastFrame = link.targetTimestamp
        advance(by: min(max(seconds, 0), 1.0 / 15))
    }

    private func attributes(_ color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): Theme.cg(color, in: self),
        ]
    }

    private func refreshColors() {
        for pill in [waveformPill, transcriptPill] {
            pill.backgroundColor = Theme.cg(Theme.surface, in: self)
            pill.borderWidth = 1
            pill.borderColor = Theme.cg(Theme.hairline, in: self)
        }
        bars.fillColor = Theme.cg(Theme.text, in: self)
        words.fade = CGGradient(
            colorsSpace: nil,
            colors: Self.fadeStops.map { Theme.cg(Theme.surface.withAlphaComponent($0.alpha), in: self) }
                as CFArray,
            locations: Self.fadeStops.map { $0.location })
    }

    private func scale(_ factor: CGFloat) {
        for layer in [bars, words] as [CALayer] { layer.contentsScale = factor }
        words.setNeedsDisplay()
    }

    private func apply() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let shown = unit(presence.value)
        stack.opacity = Float(shown)
        stack.setAffineTransform(
            CGAffineTransform(translationX: 0, y: (shown - 1) * 6).scaledBy(
                x: 0.96 + 0.04 * shown, y: 0.96 + 0.04 * shown))
        let waveformSize = PillLayout.waveform
        waveformPill.frame = CGRect(
            origin: CGPoint(x: (bounds.width - waveformSize.width) / 2, y: PillLayout.margin),
            size: waveformSize)
        bars.frame = waveformPill.bounds
        bars.path = barsPath()
        bars.opacity = mode == .transcribing && reduceMotion ? 0.5 : 1
        let frame = transcriptFrame
        transcriptPill.frame = frame
        transcriptPill.opacity = Float(unit(reveal.value))
        words.frame = CGRect(
            x: PillLayout.padding.width, y: 0, width: max(frame.width - 2 * PillLayout.padding.width, 0),
            height: frame.height)
        let textWidth = min(layout.width, PillLayout.textWidth)
        let bottom = PillLayout.padding.height + scroll.value
        let hidden =
            bottom + CGFloat(words.lines.count) * TranscriptLayout.lineHeight + PillLayout.padding.height
            - frame.height
        words.placement = TranscriptLayer.Placement(
            bottom: bottom, topFade: unit(hidden / TranscriptLayout.lineHeight),
            edgeFade: unit((textWidth - words.bounds.width) / 12))
        words.displayIfNeeded()
        CATransaction.commit()
    }

    private func barsPath() -> CGPath {
        let path = CGMutablePath()
        let count = CGFloat(Waveform.bars)
        let left = floor((PillLayout.waveform.width - count * Self.barWidth - (count - 1) * Self.barGap) / 2)
        for (index, amplitude) in amplitudes.enumerated() {
            let height =
                Self.restHeight + (Self.peakHeight - Self.restHeight) * CGFloat(min(max(amplitude, 0), 1))
            path.addRoundedRect(
                in: CGRect(
                    x: left + CGFloat(index) * (Self.barWidth + Self.barGap),
                    y: (PillLayout.waveform.height - height) / 2, width: Self.barWidth, height: height),
                cornerWidth: Self.barWidth / 2, cornerHeight: Self.barWidth / 2)
        }
        return path
    }

    private static let enter = 0.32
    private static let exit = 0.22
    private static let grow = 0.4
    private static let barWidth: CGFloat = 2
    private static let barGap: CGFloat = 3
    private static let restHeight: CGFloat = 2
    private static let peakHeight: CGFloat = 18
    private static let fadeStops: [(location: CGFloat, alpha: CGFloat)] = [
        (0, 0), (0.35, 0.3), (0.7, 0.75), (1, 1),
    ]
}

private func unit(_ value: some BinaryFloatingPoint) -> CGFloat { CGFloat(min(max(value, 0), 1)) }

private final class TranscriptLayer: CALayer {
    struct Placement: Equatable {
        var bottom: CGFloat = 0
        var topFade: CGFloat = 0
        var edgeFade: CGFloat = 0
    }

    var lines: [(CTLine, CGFloat)] = [] { didSet { setNeedsDisplay() } }
    var placement = Placement() { didSet { if placement != oldValue { setNeedsDisplay() } } }
    var baseline: CGFloat = 0
    var fade: CGGradient? { didSet { setNeedsDisplay() } }

    override init() { super.init() }
    override init(layer: Any) {
        super.init(layer: layer)
        guard let other = layer as? TranscriptLayer else { return }
        lines = other.lines
        placement = other.placement
        baseline = other.baseline
        fade = other.fade
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(in context: CGContext) {
        context.textMatrix = .identity
        for (index, (line, width)) in lines.reversed().enumerated() {
            context.textPosition = CGPoint(
                x: TranscriptLayout.start(of: width, in: bounds.width),
                y: placement.bottom + CGFloat(index) * TranscriptLayout.lineHeight + baseline)
            CTLineDraw(line, context)
        }
        guard let fade else { return }
        context.setBlendMode(.destinationOut)
        if placement.topFade > 0 {
            context.setAlpha(placement.topFade)
            context.drawLinearGradient(
                fade, start: CGPoint(x: 0, y: bounds.height - Self.fadeLength),
                end: CGPoint(x: 0, y: bounds.height), options: [])
        }
        if placement.edgeFade > 0 {
            context.setAlpha(placement.edgeFade)
            context.drawLinearGradient(
                fade, start: CGPoint(x: bounds.width - Self.fadeLength, y: 0),
                end: CGPoint(x: bounds.width, y: 0), options: [])
            context.drawLinearGradient(
                fade, start: CGPoint(x: Self.fadeLength, y: 0), end: .zero, options: [])
        }
    }

    private static let fadeLength: CGFloat = 20
}
