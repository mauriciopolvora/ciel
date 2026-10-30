import CielCore
import CryptoKit
import Foundation

/// Owns the speech model file. Download is the only network request in the app.
@MainActor final class SpeechModelStore {
    let model: SpeechModel
    let fileURL: URL
    var onChange: () -> Void = {}
    private(set) var state: ModelState {
        didSet { if state != oldValue { onChange() } }
    }
    private let configuration: URLSessionConfiguration
    private var work: Task<Void, Never>?

    static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(
            path: Bundle.main.bundleIdentifier ?? AppIdentity.bundleIdentifier
        )
        .appending(path: "Models")
    }

    init(
        model: SpeechModel = .parakeetUltra, folder: URL = defaultFolder,
        configuration: URLSessionConfiguration = .default
    ) {
        self.model = model
        self.configuration = configuration
        fileURL = folder.appending(path: model.fileName)
        let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        state = size.map(Int64.init) == model.byteCount ? .ready : .notDownloaded
    }

    var partialURL: URL { ModelDownload.partialURL(for: fileURL) }

    func download() {
        let started = state.applying(.start)
        guard started != state else { return }
        state = started
        let (chunks, continuation) = AsyncThrowingStream.makeStream(of: ModelDownload.Chunk.self)
        let session = URLSession(
            configuration: configuration, delegate: ModelDownload.Delegate(continuation), delegateQueue: nil)
        let previous = work
        work = Task { [model, fileURL] in
            await previous?.value
            do {
                try await ModelDownload.fetch(model, to: fileURL, session: session, chunks: chunks) {
                    [weak self] fraction in await self?.apply(.progress(fraction))
                }
                apply(.verified)
            } catch is CancellationError {
                // Cancel and Remove have already moved the state.
            } catch {
                apply(.failed(error.localizedDescription))
            }
        }
    }

    func cancel() {
        guard case .downloading = state else { return }
        work?.cancel()
        state = state.applying(.cancelled)
    }

    func remove() {
        work?.cancel()
        state = state.applying(.removed)
        let previous = work
        work = Task { [fileURL, partialURL] in
            await previous?.value
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: partialURL)
        }
    }

    /// Waits until queued file work has finished.
    func idle() async {
        while let current = work {
            await current.value
            if work == current { return }
        }
    }

    /// Lets the smoke check render every state without a network or a model file.
    func showForCheck(_ state: ModelState) { self.state = state }

    private func apply(_ event: ModelState.Event) { state = state.applying(event) }
}

enum ModelDownload {
    struct Chunk: Sendable {
        let data: Data
        let status: Int?
    }

    final class Delegate: NSObject, URLSessionDataDelegate, Sendable {
        private let continuation: AsyncThrowingStream<Chunk, any Error>.Continuation

        init(_ continuation: AsyncThrowingStream<Chunk, any Error>.Continuation) {
            self.continuation = continuation
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            continuation.yield(Chunk(data: data, status: (dataTask.response as? HTTPURLResponse)?.statusCode))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?)
        {
            if error == nil, let status = (task.response as? HTTPURLResponse)?.statusCode,
                !(200..<300).contains(status)
            {
                continuation.finish(throwing: ModelDownloadError.status(status))
            } else {
                continuation.finish(throwing: error)
            }
        }
    }

    static func partialURL(for file: URL) -> URL { file.appendingPathExtension("partial") }

    /// Resumes from any partial file and hashes as it writes, so only a file with the pinned size and
    /// SHA-256 ever reaches its final name.
    static func fetch(
        _ model: SpeechModel, to file: URL, session: URLSession,
        chunks: AsyncThrowingStream<Chunk, any Error>,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        defer { session.finishTasksAndInvalidate() }
        let manager = FileManager.default
        let partial = partialURL(for: file)
        do {
            try Task.checkCancellation()
            try manager.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !manager.fileExists(atPath: partial.path) {
                manager.createFile(atPath: partial.path, contents: nil)
            }
            let handle = try FileHandle(forUpdating: partial)
            defer { try? handle.close() }
            var hasher = SHA256()
            var received: Int64 = 0
            while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty {
                hasher.update(data: data)
                received += Int64(data.count)
            }
            if received > model.byteCount {
                try handle.truncate(atOffset: 0)
                hasher = SHA256()
                received = 0
            }
            if received < model.byteCount {
                var request = URLRequest(url: model.url)
                if received > 0 { request.setValue("bytes=\(received)-", forHTTPHeaderField: "Range") }
                let task = session.dataTask(with: request)
                try await withTaskCancellationHandler {
                    task.resume()
                    var first = true
                    var percent = Int(received * 100 / model.byteCount)
                    for try await chunk in chunks {
                        if first {
                            first = false
                            // A server that ignores the range sends the whole file again.
                            if chunk.status == 200 {
                                try handle.truncate(atOffset: 0)
                                hasher = SHA256()
                                received = 0
                            } else if chunk.status != 206 {
                                throw ModelDownloadError.status(chunk.status ?? 0)
                            }
                        }
                        try handle.write(contentsOf: chunk.data)
                        hasher.update(data: chunk.data)
                        received += Int64(chunk.data.count)
                        guard received <= model.byteCount else { throw ModelDownloadError.mismatch }
                        let now = Int(received * 100 / model.byteCount)
                        if now != percent {
                            percent = now
                            await progress(Double(now) / 100)
                        }
                    }
                } onCancel: {
                    task.cancel()
                }
            }
            try Task.checkCancellation()
            guard received == model.byteCount else { throw ModelDownloadError.incomplete }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == model.sha256 else {
                try? manager.removeItem(at: partial)
                throw ModelDownloadError.mismatch
            }
            try? manager.removeItem(at: file)
            try manager.moveItem(at: partial, to: file)
        } catch {
            guard Task.isCancelled else { throw error }
            try? manager.removeItem(at: partial)
            throw CancellationError()
        }
    }
}

enum ModelDownloadError: LocalizedError, Equatable {
    case status(Int)
    case incomplete, mismatch

    var errorDescription: String? {
        switch self {
        case .status(let code): "Download failed (HTTP \(code))"
        case .incomplete: "Download interrupted"
        case .mismatch: "Download corrupted"
        }
    }
}
