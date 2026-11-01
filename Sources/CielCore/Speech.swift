import Foundation

/// 16 kHz mono samples in [-1, 1].
public struct AudioClip: Sendable {
    public let samples: [Float]

    public init(samples: [Float]) { self.samples = samples }
}

public struct Transcript: Sendable, Equatable {
    public let words: [SpokenWord]

    public init(words: [SpokenWord]) { self.words = words }

    public var text: String { words.map(\.text).joined(separator: " ") }
}

public protocol Transcriber: Sendable {
    func prepare() async throws
    func transcribe(_ clip: AudioClip) async throws -> Transcript
}

extension Transcriber {
    public func prepare() async throws {}
}

public struct SpeechModel: Sendable, Equatable {
    public let fileName: String
    public let url: URL
    public let byteCount: Int64
    public let sha256: String

    public init(fileName: String, url: URL, byteCount: Int64, sha256: String) {
        self.fileName = fileName
        self.url = url
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    /// Pinned to one Hugging Face commit, so the size and hash below can never drift from the file.
    public static let parakeetUltra = SpeechModel(
        fileName: "parakeet-ultra-Q5_K_M.gguf",
        url: URL(
            string: huggingFace + "a1539be1b849ea7463b88343e5277b373d0c4ea9/parakeet-ultra-Q5_K_M.gguf")!,
        byteCount: 549_800_864, sha256: "f6e3d8172547a3bb468e92ff395696e6d2e0371a9e52690a27741b4e8561c997")

    private static let huggingFace = "https://huggingface.co/handy-computer/parakeet-ultra-gguf/resolve/"
}

public enum ModelState: Sendable, Equatable {
    case notDownloaded
    case downloading(fraction: Double)
    case ready
    case failed(String)

    public enum Event: Sendable, Equatable {
        case start
        case progress(Double)
        case verified
        case failed(String)
        case cancelled
        case removed
    }

    public func applying(_ event: Event) -> ModelState {
        switch (self, event) {
        case (.notDownloaded, .start), (.failed, .start): .downloading(fraction: 0)
        case (.downloading, .progress(let fraction)): .downloading(fraction: min(max(fraction, 0), 1))
        case (.downloading, .verified): .ready
        case (.downloading, .failed(let message)): .failed(message)
        case (.downloading, .cancelled), (_, .removed): .notDownloaded
        default: self
        }
    }
}

public struct ModelStatus: Sendable, Equatable {
    public enum Tone: Sendable { case quiet, ready, error }
    public enum Action: String, Sendable {
        case download = "Download"
        case cancel = "Cancel"
        case remove = "Remove"
    }

    public let text: String
    public let tone: Tone
    public let action: Action
}

extension ModelState {
    public var status: ModelStatus {
        switch self {
        case .notDownloaded: ModelStatus(text: "Not downloaded", tone: .quiet, action: .download)
        case .downloading(let fraction):
            ModelStatus(text: "Downloading \(Int(fraction * 100))%", tone: .quiet, action: .cancel)
        case .ready: ModelStatus(text: "Ready", tone: .ready, action: .remove)
        case .failed(let message): ModelStatus(text: message, tone: .error, action: .download)
        }
    }
}
