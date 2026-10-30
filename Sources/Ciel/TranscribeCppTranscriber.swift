import CTranscribe
import CielCore
import Foundation

/// The only code that touches transcribe.cpp. An actor, because a session runs one transcription at a time.
actor TranscribeCppTranscriber: Transcriber {
    private let modelURL: URL
    private var session: OpaquePointer?
    private var release: Cleanup?

    init(modelURL: URL) { self.modelURL = modelURL }

    func transcribe(_ clip: AudioClip) throws -> Transcript {
        guard !clip.samples.isEmpty else { return Transcript(text: "") }
        let session = try loadedSession()
        let status = clip.samples.withUnsafeBufferPointer {
            transcribe_run(session, $0.baseAddress, Int32($0.count), nil)
        }
        // Truncated and looping decodes still carry a readable partial transcript.
        guard
            [TRANSCRIBE_OK, TRANSCRIBE_ERR_OUTPUT_TRUNCATED, TRANSCRIBE_ERR_OUTPUT_REPETITION].contains(
                status)
        else { throw TranscriptionError(status) }
        let text = transcribe_full_text(session).map { String(cString: $0) } ?? ""
        return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func loadedSession() throws -> OpaquePointer {
        if let session { return session }
        var opened: OpaquePointer?
        let status = transcribe_open(modelURL.path, nil, nil, &opened)
        guard status == TRANSCRIBE_OK, let opened else { throw TranscriptionError(status) }
        session = opened
        release = Cleanup { transcribe_session_free(opened) }
        return opened
    }
}

struct TranscriptionError: LocalizedError, Equatable {
    let message: String

    init(_ status: transcribe_status) {
        message = String(cString: transcribe_status_string(Int32(status.rawValue)))
    }

    var errorDescription: String? { "Speech to text failed: \(message)" }
}
