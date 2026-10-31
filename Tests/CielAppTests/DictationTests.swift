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

    @Test func aTapKeepsListeningUntilTheNextPress() async throws {
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
        #expect(!recorder.isRecording)
        dictation.release()
        try await waitUntil { delivered == ["hello"] }
        #expect(recorder.starts == 1)
    }

    @Test func aCancelledHoldDropsTheRecording() async throws {
        let recorder = FakeRecorder()
        var delivered: [String] = []
        var activities: [Dictation.Activity] = []
        let dictation = Dictation(
            recorder: recorder, tapLimit: .zero, transcriber: { FakeTranscriber(text: "copy") },
            deliver: { delivered.append($0) }, fail: { Issue.record("Unexpected failure: \($0)") },
            onActivity: { activities.append($0) })
        dictation.press()
        dictation.cancel()
        dictation.release()
        #expect(!recorder.isRecording)
        try await Task.sleep(for: .milliseconds(50))
        #expect(delivered.isEmpty)
        #expect(activities == [.listening, .idle])
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

    @Test func resamplingTurnsOneSecondIntoSixteenThousandSamples() {
        let second = (0..<48_000).map { Float(sin(Double($0) * 2 * .pi * 440 / 48_000)) * 0.5 }
        let resampled = Microphone.resample(second, from: 48_000)
        #expect(abs(resampled.count - 16_000) <= 800)
        #expect(Microphone.resample(second, from: 16_000) == second)
    }
}

@MainActor private final class FakeRecorder: AudioRecorder {
    private(set) var isRecording = false
    private(set) var starts = 0

    func start() throws {
        starts += 1
        isRecording = true
    }

    func stop() -> AudioClip {
        isRecording = false
        return AudioClip(samples: [0.1, 0.2])
    }
}

private struct FakeTranscriber: Transcriber {
    let text: String

    func transcribe(_ clip: AudioClip) async throws -> Transcript { Transcript(text: text) }
}
