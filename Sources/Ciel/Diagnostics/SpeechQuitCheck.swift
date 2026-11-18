import AppKit
import CielCore

/// Loads the model named by `CIEL_SPEECH_MODEL` into the app's own transcriber, runs one transcription, then quits
/// through `NSApp.terminate`. `check.sh` fails the step unless the process then exits with status 0.
@MainActor enum SpeechQuitCheck {
    static func run(loadSpeech: (URL) -> TranscribeCppTranscriber) {
        guard let model = ProcessInfo.processInfo.environment["CIEL_SPEECH_MODEL"] else {
            print("FAIL the speech quit check needs CIEL_SPEECH_MODEL to name a speech model file")
            exit(1)
        }
        let transcriber = loadSpeech(URL(fileURLWithPath: model))
        // One second of a quiet 440 Hz tone at 16 kHz, enough to allocate the run-time buffers.
        let tone = AudioClip(
            samples: (0..<16_000).map { Float(0.1 * sin(2 * .pi * 440 * Double($0) / 16_000)) })
        Task { @MainActor in
            do {
                try await transcriber.prepare()
                _ = try await transcriber.transcribe(tone)
            } catch {
                print("FAIL speech model load or transcription: \(error.localizedDescription)")
                exit(1)
            }
            print("PASS speech model loaded and ran one transcription")
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                print("FAIL quitting with the speech model loaded did not finish within 30 s")
                exit(1)
            }
            NSApp.terminate(nil)
        }
    }
}
