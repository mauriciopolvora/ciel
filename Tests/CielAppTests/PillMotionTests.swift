import AppKit
import CoreText
import Testing

@testable import CielApp

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct PillMotionTests {
    @Test func aSpringSettlesOnItsTargetWithoutOvershoot() {
        var spring = Spring(0, response: 0.4)
        spring.target = 10
        var last = 0.0
        for _ in 0..<120 {
            spring.advance(by: 1.0 / 60)
            #expect(spring.value >= last && spring.value <= 10)
            last = spring.value
        }
        #expect(spring.isSettled && spring.value == 10)
    }

    @Test func aRetargetedSpringKeepsItsValueAndVelocity() {
        var spring = Spring(0, response: 0.4)
        spring.target = 10
        spring.advance(by: 0.1)
        let value = spring.value
        let velocity = spring.velocity
        spring.target = 0
        #expect(spring.value == value && spring.velocity == velocity && velocity > 0)
        spring.advance(by: 1.0 / 240)
        #expect(spring.value > value)
        spring.snap(to: 3)
        #expect(spring.isSettled && spring.value == 3)
    }

    @Test func loudnessMapsFiftyToTenDecibelsBelowFullScale() {
        #expect(LevelMeter.loudness(0) == 0)
        #expect(LevelMeter.loudness(0.001) == 0)
        #expect(abs(LevelMeter.loudness(0.01) - 0.25) < 0.001)
        #expect(abs(LevelMeter.loudness(0.1) - 0.75) < 0.001)
        #expect(LevelMeter.loudness(1) == 1)
    }

    @Test func theMeterRisesFastAndFallsSlowly() {
        var meter = LevelMeter()
        meter.hear([0.1], every: 0.01)
        meter.advance(by: LevelMeter.attack)
        #expect(meter.level > 0.6 * LevelMeter.loudness(0.1))
        meter.advance(by: 0.3)
        let loud = meter.level
        meter.hear([0], every: 0.01)
        meter.advance(by: LevelMeter.attack)
        #expect(meter.level > 0.8 * loud)
        meter.advance(by: 1)
        #expect(meter.level < 0.01)
    }

    @Test func levelsPlayBackAtTheirRecordedPace() {
        var meter = LevelMeter()
        meter.hear([0.1, 0], every: 0.05)
        meter.advance(by: 0.05)
        let first = meter.level
        meter.advance(by: 0.05)
        #expect(first > 0.5 * LevelMeter.loudness(0.1))
        #expect(meter.level < first)
    }

    @Test func levelsLaggingPastTheLatencyCapAreDropped() {
        var meter = LevelMeter()
        meter.hear(Array(repeating: 0, count: 10) + Array(repeating: 0.1, count: 10), every: 0.02)
        meter.advance(by: LevelMeter.attack)
        #expect(meter.level > 0.6 * LevelMeter.loudness(0.1))
    }

    @Test func withoutFlowEveryBarShowsTheCurrentLevelTaperedToTheEdges() {
        var waveform = Waveform()
        waveform.advance(by: 0.01, level: 0.8)
        let bars = waveform.amplitudes(flowing: false)
        #expect(bars.count == Waveform.bars)
        #expect(bars == bars.reversed())
        #expect(abs(bars[Waveform.bars / 2] - 0.8) < 0.000_1)
        #expect(abs(bars[0] - 0.8 * 0.35) < 0.000_1)
        #expect(zip(bars, bars.dropFirst()).prefix(Waveform.bars / 2).allSatisfy { $0 < $1 })
    }

    @Test func theNewestLevelSitsInTheMiddleAndFlowsOut() {
        var waveform = Waveform()
        for _ in 0..<10 { waveform.advance(by: Waveform.period, level: 1) }
        waveform.advance(by: Waveform.period, level: 0)
        let bars = waveform.amplitudes(flowing: true)
        let middle = Waveform.bars / 2
        #expect(bars == bars.reversed())
        #expect(bars[middle] == 0)
        #expect(bars[middle + 1] > 0.9)
        #expect(bars[middle + 2] > 0.5)
    }

    @Test func theTranscribingRippleStaysLowAndSymmetric() {
        for time in stride(from: 0.0, to: 2.2, by: 0.1) {
            let bars = Waveform.ripple(at: time)
            #expect(bars.count == Waveform.bars && bars == bars.reversed())
            #expect(bars.allSatisfy { $0 >= 0 && $0 <= 0.2 })
        }
    }

    @Test func aShortTranscriptIsOneLineAndNeverNarrowerThanTheWaveform() {
        let short = TranscriptLayout(Self.text("hi"), maxWidth: PillLayout.textWidth)
        #expect(short.lines.count == 1)
        #expect(PillLayout.transcript(short) == PillLayout.waveform)
        let line = TranscriptLayout(Self.text("Send the quarterly report"), maxWidth: PillLayout.textWidth)
        let size = PillLayout.transcript(line)
        #expect(line.lines.count == 1 && line.width > 96 && line.width < PillLayout.textWidth)
        #expect(size == CGSize(width: line.width + 2 * PillLayout.padding.width, height: 32))
    }

    @Test func eachLineIsCenteredWithoutItsTrailingSpace() {
        let words = Array(repeating: "check the numbers before Friday", count: 3).joined(separator: " ")
        let layout = TranscriptLayout(Self.text(words), maxWidth: PillLayout.textWidth)
        #expect(layout.lines.count == 2 && layout.widths.count == 2)
        let last = layout.widths[1]
        #expect(last < layout.widths[0])
        #expect(layout.widths[0] <= layout.width && layout.width - layout.widths[0] < 1)
        let space = layout.width
        #expect(abs(TranscriptLayout.start(of: last, in: space) * 2 + last - space) < 0.001)
        #expect(TranscriptLayout.start(of: layout.widths[0], in: space) < 0.5)
        #expect(TranscriptLayout.start(of: space, in: space - 40) == -20)
    }

    @Test func aLongTranscriptWrapsAtTheWidthCapAndStopsGrowingAtThreeLines() {
        let words = Array(repeating: "check the numbers before Friday", count: 12).joined(separator: " ")
        let layout = TranscriptLayout(Self.text(words), maxWidth: PillLayout.textWidth)
        #expect(layout.lines.count > PillLayout.maxLines)
        #expect(layout.width <= PillLayout.textWidth && layout.width > PillLayout.textWidth - 60)
        for line in layout.lines {
            let width =
                CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)
            #expect(width <= PillLayout.textWidth)
        }
        let size = PillLayout.transcript(layout)
        #expect(size == CGSize(width: layout.width + 2 * PillLayout.padding.width, height: 64))
        let canvas = PillLayout.canvas
        #expect(size.width + 2 * PillLayout.margin <= canvas.width)
        #expect(
            size.height + PillLayout.waveform.height + PillLayout.gap + 2 * PillLayout.margin <= canvas.height
        )
    }

    @Test func reducedMotionMakesEveryChangeInstant() {
        let pill = PillView()
        var rested = 0
        pill.onRest = { rested += 1 }
        pill.listen(reduceMotion: true)
        #expect(pill.visibility == 1)
        pill.text(committed: "hello there", tentative: "")
        #expect(pill.showsTranscript)
        #expect(pill.transcriptFrame.height == 32)
        #expect(pill.transcriptFrame.minY == PillLayout.margin + PillLayout.waveform.height + PillLayout.gap)
        pill.hide()
        #expect(pill.visibility == 0 && rested == 1)
    }

    @Test func voiceOverReadsTheLiveTranscript() {
        let pill = PillView()
        pill.listen(reduceMotion: true)
        #expect(pill.isAccessibilityElement() && pill.accessibilityRole() == .staticText)
        pill.text(committed: "send the", tentative: "report")
        #expect(pill.accessibilityValue() as? String == "send the report")
        pill.text(committed: "", tentative: "")
        #expect(pill.accessibilityValue() as? String == "")
    }

    @Test func withMotionTheTranscriptGrowsOutOfTheWaveformWithoutJumps() {
        let pill = PillView()
        var rested = 0
        pill.onRest = { rested += 1 }
        pill.listen(reduceMotion: false)
        #expect(pill.visibility == 0)
        pill.text(committed: "Send the quarterly report", tentative: "to Maria")
        let start = pill.transcriptFrame
        #expect(start.size == PillLayout.waveform && start.minY == PillLayout.margin)
        var last = start
        for _ in 0..<60 {
            pill.advance(by: 1.0 / 60)
            let frame = pill.transcriptFrame
            #expect(frame.width >= last.width && frame.width - last.width < 30)
            #expect(frame.minY >= last.minY && frame.minY - last.minY < 6)
            last = frame
        }
        #expect(pill.visibility == 1)
        #expect(last.minY == PillLayout.margin + PillLayout.waveform.height + PillLayout.gap)
        pill.hide()
        #expect(rested == 0)
        for _ in 0..<60 { pill.advance(by: 1.0 / 60) }
        #expect(pill.visibility == 0 && rested == 1 && !pill.showsTranscript)
    }

    @Test func anOverflowingTranscriptFadesItsOlderLines() {
        let pill = PillView()
        pill.listen(reduceMotion: true)
        pill.text(committed: "Send the quarterly report", tentative: "")
        #expect(pill.olderLinesFade == 0)
        let words = Array(repeating: "check the numbers before Friday", count: 12).joined(separator: " ")
        pill.text(committed: words, tentative: "")
        #expect(pill.lineCount > PillLayout.maxLines)
        #expect(pill.transcriptFrame.height == 64)
        #expect(pill.olderLinesFade == 1)
    }

    private static func text(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 13)])
    }
}
