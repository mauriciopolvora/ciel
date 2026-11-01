import AVFoundation
import AppKit
import CielCore
import Foundation
import Testing

@testable import CielApp

/// Times release to paste with the real model, once for the old whole-clip pass and once for live passes.
/// Runs only when `CIEL_SPEECH_MODEL` and `CIEL_SPEECH_FIXTURES` are set, as the speech workflow does.
@Suite(.enabled(if: SpeechBench.model != nil), .timeLimit(.minutes(10)))
@MainActor
struct SpeechBenchTests {
    @Test func releaseToPaste() async throws {
        let model = try #require(SpeechBench.model)
        let fixtures = try #require(SpeechBench.fixtures)
        let engine = TranscribeCppTranscriber(modelURL: model)
        let load = try await SpeechBench.time { try await engine.prepare() }
        var lines = ["load \(SpeechBench.ms(load)) ms"]
        var report: [[String: Any]] = []
        for seconds in [3, 10, 30] {
            let samples = try SpeechBench.read(fixtures.appending(path: "\(seconds).wav"))
            let reference = try String(
                contentsOf: fixtures.appending(path: "\(seconds).txt"), encoding: .utf8)
            let clip = AudioClip(samples: samples)
            let first = try await SpeechBench.time { _ = try await engine.transcribe(clip) }
            var whole = ""
            let wholeTime = try await SpeechBench.time { whole = try await engine.transcribe(clip).text }
            let paste = try await SpeechBench.time {
                _ = TextPaster.paste(whole, into: SpeechBench.pasteboard)
            }
            let (live, liveTime) = try await SpeechBench.dictate(samples, with: engine)
            let row: [String: Any] = [
                "seconds": seconds, "firstPassMs": SpeechBench.ms(first),
                "wholeClipMs": SpeechBench.ms(wholeTime),
                "liveReleaseToPasteMs": SpeechBench.ms(liveTime), "pasteMs": SpeechBench.ms(paste),
                "wholeClipWordErrorRate": SpeechBench.errorRate(whole, reference),
                "liveWordErrorRate": SpeechBench.errorRate(live, reference), "whole": whole, "live": live,
            ]
            report.append(row)
            lines.append(
                "\(seconds) s: first pass \(row["firstPassMs"]!) ms, whole clip \(row["wholeClipMs"]!) ms,"
                    + " live \(row["liveReleaseToPasteMs"]!) ms, paste \(row["pasteMs"]!) ms,"
                    + " WER whole \(row["wholeClipWordErrorRate"]!) live \(row["liveWordErrorRate"]!)")
            #expect(!live.isEmpty)
        }
        for line in lines { print("SPEECH BENCH \(line)") }
        let json = try JSONSerialization.data(
            withJSONObject: ["loadMs": SpeechBench.ms(load), "clips": report],
            options: [.prettyPrinted, .sortedKeys])
        let output = URL(fileURLWithPath: ".build/performance/speech-bench.json")
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: output)
    }
}

enum SpeechBench {
    static let model = ProcessInfo.processInfo.environment["CIEL_SPEECH_MODEL"].map(
        URL.init(fileURLWithPath:))
    static let fixtures = ProcessInfo.processInfo.environment["CIEL_SPEECH_FIXTURES"].map(
        URL.init(fileURLWithPath:))
    @MainActor static let pasteboard = NSPasteboard(name: NSPasteboard.Name("ciel-speech-bench"))

    /// Holds the key for the length of the clip while the audio arrives in real time, then times release to paste.
    @MainActor static func dictate(_ samples: [Float], with engine: any Transcriber) async throws -> (
        String, Duration
    ) {
        let recorder = RealTimeRecorder(samples: samples)
        var pasted: (String, ContinuousClock.Instant)?
        let dictation = Dictation(
            recorder: recorder, tapLimit: .zero, transcriber: { engine },
            deliver: { text in
                _ = TextPaster.paste(text, into: pasteboard)
                pasted = (text, .now)
            }, fail: { Issue.record("Unexpected failure: \($0)") })
        dictation.press()
        try await Task.sleep(for: .milliseconds(samples.count / 16))
        let released = ContinuousClock.now
        dictation.release()
        while pasted == nil { try await Task.sleep(for: .milliseconds(5)) }
        return (pasted!.0, pasted!.1 - released)
    }

    @MainActor static func time(_ work: () async throws -> Void) async throws -> Duration {
        let start = ContinuousClock.now
        try await work()
        return ContinuousClock.now - start
    }

    static func ms(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        try #require(file.processingFormat.sampleRate == 16_000)
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    /// Word error rate against the script, ignoring case and punctuation.
    static func errorRate(_ text: String, _ reference: String) -> Double {
        let words = normalized(text)
        let expected = normalized(reference)
        var row = Array(0...words.count)
        for (index, word) in expected.enumerated() {
            var next = [index + 1]
            for (column, heard) in words.enumerated() {
                next.append(min(row[column] + (word == heard ? 0 : 1), row[column + 1] + 1, next[column] + 1))
            }
            row = next
        }
        return (Double(row[words.count]) / Double(max(expected.count, 1)) * 1_000).rounded() / 1_000
    }

    private static func normalized(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: \.isWhitespace).map {
            String($0.filter { $0.isLetter || $0.isNumber })
        }
        .filter { !$0.isEmpty }
    }
}

/// Hands out audio as fast as a microphone would.
@MainActor private final class RealTimeRecorder: AudioRecorder {
    private let samples: [Float]
    private var started = ContinuousClock.now

    init(samples: [Float]) { self.samples = samples }

    func start() throws { started = .now }

    func recorded(from start: Int) -> AudioClip {
        let elapsed = ContinuousClock.now - started
        let available = min(SpeechBench.ms(elapsed) * 16, samples.count)
        return AudioClip(samples: Array(samples[min(start, available)..<available]))
    }

    func stop() -> AudioClip { AudioClip(samples: samples) }
}
