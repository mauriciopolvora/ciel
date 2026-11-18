import CielCore
import Foundation
import Testing

@testable import CielApp

@Suite struct TranscriberTests {
    private let missing = FileManager.default.temporaryDirectory.appending(
        path: "ciel-\(UUID().uuidString).gguf")

    @Test func aMissingModelFileThrows() async {
        let transcriber = TranscribeCppTranscriber(modelURL: missing)
        await #expect(throws: TranscriptionError.self) {
            try await transcriber.transcribe(AudioClip(samples: [Float](repeating: 0, count: 16_000)))
        }
    }

    @Test func preparingTheTranscriberItselfLoadsTheModel() async {
        let transcriber = TranscribeCppTranscriber(modelURL: missing)
        await #expect(throws: TranscriptionError.self) { try await transcriber.prepare() }
    }

    @Test func aClosedTranscriberNeverOpensTheModelAgain() async {
        let transcriber = TranscribeCppTranscriber(modelURL: missing)
        await transcriber.close()
        await #expect(throws: CancellationError.self) {
            try await transcriber.transcribe(AudioClip(samples: [Float](repeating: 0, count: 16_000)))
        }
        await #expect(throws: CancellationError.self) { try await transcriber.prepare() }
    }

    @Test func anEmptyClipIsEmptyText() async throws {
        let transcriber = TranscribeCppTranscriber(modelURL: missing)
        #expect(try await transcriber.transcribe(AudioClip(samples: [])) == Transcript(words: []))
    }
}
