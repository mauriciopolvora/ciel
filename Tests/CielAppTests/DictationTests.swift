import CielCore
import Foundation
import Testing

@testable import CielApp

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct DictationTests {
    @Test func aHoldDeliversItsTranscriptOnRelease() async throws {
        let recorder = FakeRecorder()
        var delivered: [String] = []
        let dictation = Dictation(
            recorder: recorder, tapLimit: .zero, transcriber: { FakeTranscriber(text: "hello there") },
            deliver: { delivered.append($0) }, fail: { Issue.record("Unexpected failure: \($0)") })
        dictation.press()
        #expect(recorder.isRecording)
        dictation.release()
        #expect(!recorder.isRecording)
        try await waitUntil { delivered == ["hello there"] }
    }

    @Test func aTapKeepsListeningUntilItIsTappedAgain() async throws {
        let recorder = FakeRecorder()
        var delivered: [String] = []
        let dictation = Dictation(
            recorder: recorder, tapLimit: .seconds(10), transcriber: { FakeTranscriber(text: "hello") },
            deliver: { delivered.append($0) }, fail: { Issue.record("Unexpected failure: \($0)") })
        dictation.press()
        dictation.release()
        #expect(recorder.isRecording)
        try await Task.sleep(for: .milliseconds(50))
        #expect(delivered.isEmpty)
        dictation.press()
        dictation.release()
        #expect(!recorder.isRecording)
        try await waitUntil { delivered == ["hello"] }
        #expect(recorder.starts == 1)
    }

    @Test func aCancelledHoldDropsTheRecording() async throws {
        let recorder = FakeRecorder()
        var delivered: [String] = []
        let dictation = Dictation(
            recorder: recorder, tapLimit: .zero, transcriber: { FakeTranscriber(text: "copy") },
            deliver: { delivered.append($0) }, fail: { Issue.record("Unexpected failure: \($0)") })
        dictation.press()
        dictation.cancel()
        dictation.release()
        #expect(!recorder.isRecording)
        try await Task.sleep(for: .milliseconds(50))
        #expect(delivered.isEmpty)
    }

    @Test func aChordNeverShowsListening() async throws {
        let recorder = FakeRecorder()
        var activities: [Dictation.Activity] = []
        let dictation = Dictation(
            recorder: recorder, tapLimit: .zero, transcriber: { FakeTranscriber(text: "copy") },
            deliver: { _ in }, fail: { Issue.record("Unexpected failure: \($0)") },
            onActivity: { activities.append($0) })
        dictation.press()
        #expect(recorder.isRecording)
        dictation.cancel()
        try await Task.sleep(for: .milliseconds(300))
        #expect(activities.isEmpty)
    }

    @Test func aHoldShowsListeningOnceItOutlastsTheGrace() async throws {
        var activities: [Dictation.Activity] = []
        let dictation = Dictation(
            recorder: FakeRecorder(), tapLimit: .zero, transcriber: { FakeTranscriber(text: "hi") },
            deliver: { _ in }, fail: { Issue.record("Unexpected failure: \($0)") },
            onActivity: { activities.append($0) })
        dictation.press()
        #expect(activities.isEmpty)
        try await waitUntil { activities == [.listening] }
        try await Task.sleep(for: .milliseconds(200))
        #expect(activities == [.listening])
    }

    @Test func aTapShowsListeningAtOnce() {
        var activities: [Dictation.Activity] = []
        let dictation = Dictation(
            recorder: FakeRecorder(), tapLimit: .seconds(10), transcriber: { FakeTranscriber(text: "hi") },
            deliver: { _ in }, fail: { Issue.record("Unexpected failure: \($0)") },
            onActivity: { activities.append($0) })
        dictation.press()
        dictation.release()
        #expect(activities == [.listening])
    }

    @Test func aChordWhileTappedKeepsListeningWithoutPasting() async throws {
        let recorder = FakeRecorder()
        var delivered: [String] = []
        let dictation = Dictation(
            recorder: recorder, tapLimit: .seconds(10), transcriber: { FakeTranscriber(text: "notes") },
            deliver: { delivered.append($0) }, fail: { Issue.record("Unexpected failure: \($0)") })
        dictation.press()
        dictation.release()
        dictation.press()
        dictation.cancel()
        dictation.release()
        #expect(recorder.isRecording)
        try await Task.sleep(for: .milliseconds(50))
        #expect(delivered.isEmpty)
        dictation.press()
        dictation.release()
        try await waitUntil { delivered == ["notes"] }
    }

    @Test func aCancelWhileTappedStopsTheMicrophone() async throws {
        let recorder = FakeRecorder()
        var delivered: [String] = []
        let dictation = Dictation(
            recorder: recorder, tapLimit: .seconds(10), transcriber: { FakeTranscriber(text: "notes") },
            deliver: { delivered.append($0) }, fail: { Issue.record("Unexpected failure: \($0)") })
        dictation.press()
        dictation.release()
        dictation.cancel()
        #expect(!recorder.isRecording)
        try await Task.sleep(for: .milliseconds(50))
        #expect(delivered.isEmpty)
    }

    @Test func activityFollowsListeningThenTranscribing() async throws {
        var activities: [Dictation.Activity] = []
        let dictation = Dictation(
            recorder: FakeRecorder(), tapLimit: .zero, transcriber: { FakeTranscriber(text: "hi") },
            deliver: { _ in }, fail: { _ in }, onActivity: { activities.append($0) })
        dictation.press()
        try await waitUntil { activities == [.listening] }
        dictation.release()
        #expect(activities == [.listening, .transcribing])
        try await waitUntil { activities == [.listening, .transcribing, .idle] }
    }

    @Test func anUnavailableModelReportsWithoutRecording() {
        let recorder = FakeRecorder()
        var failures: [String] = []
        let dictation = Dictation(
            recorder: recorder, transcriber: { throw DictationError.notReady }, deliver: { _ in },
            fail: { failures.append($0) })
        dictation.press()
        #expect(!recorder.isRecording)
        #expect(recorder.starts == 0)
        #expect(failures == [DictationError.notReady.localizedDescription])
    }

    @Test func aRepeatedPressWhileListeningIsIgnored() {
        let recorder = FakeRecorder()
        let dictation = Dictation(
            recorder: recorder, transcriber: { FakeTranscriber(text: "") }, deliver: { _ in }, fail: { _ in })
        dictation.press()
        dictation.press()
        #expect(recorder.starts == 1)
    }

    @Test func whatIsHeardShowsWhileListeningAndIsPastedOnRelease() async throws {
        let recorder = FakeRecorder(seconds: 3)
        var shown: [String] = []
        var delivered: [String] = []
        let dictation = Dictation(
            recorder: recorder, tapLimit: .zero, interval: .milliseconds(5),
            transcriber: { FakeTranscriber(text: "hello there") }, deliver: { delivered.append($0) },
            fail: { Issue.record("Unexpected failure: \($0)") }, onText: { shown.append("\($0)|\($1)") })
        dictation.press()
        try await waitUntil { shown.contains("hello there|") }
        #expect(shown.first == "|hello there")
        dictation.release()
        try await waitUntil { delivered == ["hello there"] }
    }

    @Test func thePasteComesFromTheFinalPassNotThePreview() async throws {
        let recorder = FakeRecorder(seconds: 3)
        var shown: [String] = []
        var delivered: [String] = []
        let transcriber = DraftingTranscriber(final: recorder.stopped.count)
        let dictation = Dictation(
            recorder: recorder, tapLimit: .zero, interval: .milliseconds(5), transcriber: { transcriber },
            deliver: { delivered.append($0) }, fail: { Issue.record("Unexpected failure: \($0)") },
            onText: { shown.append($1) })
        dictation.press()
        try await waitUntil { shown.count >= 2 }
        #expect(shown.allSatisfy { $0.hasPrefix("draft") })
        dictation.release()
        try await waitUntil { delivered == ["the final words"] }
    }

    @Test func aCancelStopsTheLiveTranscript() async throws {
        let recorder = FakeRecorder(seconds: 3)
        var shown = 0
        let dictation = Dictation(
            recorder: recorder, tapLimit: .zero, interval: .milliseconds(5),
            transcriber: { FakeTranscriber(text: "hello") }, deliver: { _ in }, fail: { _ in },
            onText: { _, _ in shown += 1 })
        dictation.press()
        try await waitUntil { shown > 0 }
        dictation.cancel()
        let seen = shown
        try await Task.sleep(for: .milliseconds(50))
        #expect(shown == seen)
    }

    @Test func resamplingBufferByBufferTurnsOneSecondIntoSixteenThousandSamples() throws {
        let second = (0..<48_000).map { Float(sin(Double($0) * 2 * .pi * 440 / 48_000)) * 0.5 }
        let resampler = try #require(Resampler(from: 48_000))
        let resampled = stride(from: 0, to: second.count, by: 4096).flatMap { start in
            second[start..<min(start + 4096, second.count)].withUnsafeBufferPointer { resampler.convert($0) }
        }
        #expect(abs(resampled.count - 16_000) <= 800)
        let same = try #require(Resampler(from: 16_000))
        #expect(second.withUnsafeBufferPointer { same.convert($0) } == second)
    }
}

@MainActor private final class FakeRecorder: AudioRecorder {
    private(set) var isRecording = false
    private(set) var starts = 0
    let heard: [Float]
    let stopped: [Float]

    init(seconds: Int = 0) {
        heard = [Float](repeating: 0, count: seconds * 16_000)
        stopped = heard + [0.1, 0.2]
    }

    func start() throws {
        starts += 1
        isRecording = true
    }

    func recorded(from start: Int) -> AudioClip { AudioClip(samples: Array(heard.dropFirst(start))) }

    func stop() -> AudioClip {
        isRecording = false
        return AudioClip(samples: stopped)
    }
}

private struct FakeTranscriber: Transcriber {
    let text: String

    func transcribe(_ clip: AudioClip) async throws -> Transcript { Transcript(words: words(text)) }
}

private actor DraftingTranscriber: Transcriber {
    let final: Int
    private var passes = 0

    init(final: Int) { self.final = final }

    func transcribe(_ clip: AudioClip) async throws -> Transcript {
        passes += 1
        return Transcript(words: words(clip.samples.count == final ? "the final words" : "draft\(passes)"))
    }
}

private func words(_ text: String) -> [SpokenWord] {
    text.split(separator: " ").enumerated().map { index, word in
        SpokenWord(text: String(word), start: index * 8_000, end: index * 8_000 + 6_400)
    }
}
