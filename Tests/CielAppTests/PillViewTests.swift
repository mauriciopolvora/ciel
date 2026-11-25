import AppKit
import CielCore
import Testing

@testable import CielApp

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct PillViewTests {
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
}
