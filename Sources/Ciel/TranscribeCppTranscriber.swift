import CTranscribe
import CielCore
import Foundation
import os

/// The only code that touches transcribe.cpp. An actor, because a session runs one transcription at a time.
actor TranscribeCppTranscriber: Transcriber {
    private let modelURL: URL
    private var session: OpaquePointer?
    private var release: Cleanup?
    private let abort = AbortFlag()

    init(modelURL: URL) { self.modelURL = modelURL }

    func prepare() async throws { _ = try loadedSession() }

    func transcribe(_ clip: AudioClip) async throws -> Transcript {
        abort.requested.withLock { $0 = false }
        // Calling an isolated method keeps the run on the actor, so a queued pass cannot start mid-run and clear the flag.
        return try await withTaskCancellationHandler {
            try run(clip)
        } onCancel: { [abort] in
            abort.requested.withLock { $0 = true }
        }
    }

    private func run(_ clip: AudioClip) throws -> Transcript {
        try Task.checkCancellation()
        guard !clip.samples.isEmpty else { return Transcript(words: []) }
        let session = try loadedSession()
        let status = clip.samples.withUnsafeBufferPointer {
            transcribe_run(session, $0.baseAddress, Int32($0.count), nil)
        }
        // Truncated and looping decodes still carry a readable partial transcript.
        guard
            [TRANSCRIBE_OK, TRANSCRIBE_ERR_OUTPUT_TRUNCATED, TRANSCRIBE_ERR_OUTPUT_REPETITION].contains(
                status)
        else { throw TranscriptionError(status) }
        let words = (0..<transcribe_n_words(session)).compactMap { index -> SpokenWord? in
            var word = transcribe_word()
            transcribe_word_init(&word)
            guard transcribe_get_word(session, index, &word) == TRANSCRIBE_OK, let text = word.text else {
                return nil
            }
            let spoken = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
            return spoken.isEmpty
                ? nil
                : SpokenWord(
                    text: spoken, start: Int(word.t0_ms) * Self.samplesPerMillisecond,
                    end: Int(word.t1_ms) * Self.samplesPerMillisecond)
        }
        return Transcript(words: words)
    }

    private static let samplesPerMillisecond = 16

    private func loadedSession() throws -> OpaquePointer {
        if let session { return session }
        var opened: OpaquePointer?
        let status = transcribe_open(modelURL.path, nil, nil, &opened)
        guard status == TRANSCRIBE_OK, let opened else { throw TranscriptionError(status) }
        session = opened
        release = Cleanup { transcribe_session_free(opened) }
        transcribe_set_abort_callback(opened, abortRequested, Unmanaged.passUnretained(abort).toOpaque())
        return opened
    }
}

/// transcribe.cpp polls this from its run thread, so cancelling the calling task stops the run at its next decode step
/// and the pass queued behind it starts sooner.
private final class AbortFlag: Sendable {
    let requested = OSAllocatedUnfairLock(initialState: false)
}

private func abortRequested(_ flag: UnsafeMutableRawPointer?) -> Bool {
    Unmanaged<AbortFlag>.fromOpaque(flag!).takeUnretainedValue().requested.withLock { $0 }
}

struct TranscriptionError: LocalizedError, Equatable {
    let message: String

    init(_ status: transcribe_status) {
        message = String(cString: transcribe_status_string(Int32(status.rawValue)))
    }

    var errorDescription: String? { "Speech to text failed: \(message)" }
}
