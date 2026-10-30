import CielCore
import CryptoKit
import Foundation
import Testing
import os

@testable import CielApp

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct SpeechModelStoreTests {
    /// URLSession holds back the first 512 bytes of a reply to sniff its type, so every reply that
    /// breaks off sends more than that.
    private let body = Data((0..<4000).map { UInt8($0 % 251) })

    @Test func aVerifiedDownloadIsReady() async throws {
        try await withStore(replies: [.init(status: 200, body: body)]) { store in
            store.download()
            #expect(store.state == .downloading(fraction: 0))
            await store.idle()
            #expect(store.state == .ready)
            let saved = try Data(contentsOf: store.fileURL)
            #expect(saved == body)
            #expect(!FileManager.default.fileExists(atPath: store.partialURL.path))
            let reopened = SpeechModelStore(
                model: store.model, folder: store.fileURL.deletingLastPathComponent())
            #expect(reopened.state == .ready)
        }
    }

    @Test func aChecksumMismatchFailsAndKeepsNoFiles() async throws {
        try await withStore(replies: [.init(status: 200, body: body)], sha256: hex(Data("other".utf8))) {
            store in
            store.download()
            await store.idle()
            #expect(store.state == .failed(ModelDownloadError.mismatch.localizedDescription))
            #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
            #expect(!FileManager.default.fileExists(atPath: store.partialURL.path))
        }
    }

    @Test func aRetryResumesAnInterruptedDownload() async throws {
        let replies: [StubURLProtocol.Reply] = [
            .init(status: 200, body: body.prefix(1600), ending: .drop),
            .init(status: 206, body: body.suffix(2400)),
        ]
        try await withStore(replies: replies) { store in
            store.download()
            await store.idle()
            guard case .failed = store.state else {
                Issue.record("Expected a failure, got \(store.state)")
                return
            }
            let partial = try Data(contentsOf: store.partialURL)
            #expect(partial.count == 1600)
            store.download()
            await store.idle()
            #expect(store.state == .ready)
            let saved = try Data(contentsOf: store.fileURL)
            #expect(saved == body)
            let ranges = StubURLProtocol.requests(for: store.model.url).map {
                $0.value(forHTTPHeaderField: "Range")
            }
            #expect(ranges == [nil, "bytes=1600-"])
        }
    }

    @Test func aServerThatIgnoresTheRangeStartsOver() async throws {
        let replies: [StubURLProtocol.Reply] = [
            .init(status: 200, body: body.prefix(1600), ending: .drop), .init(status: 200, body: body),
        ]
        try await withStore(replies: replies) { store in
            store.download()
            await store.idle()
            store.download()
            await store.idle()
            #expect(store.state == .ready)
            let saved = try Data(contentsOf: store.fileURL)
            #expect(saved == body)
            let ranges = StubURLProtocol.requests(for: store.model.url).map {
                $0.value(forHTTPHeaderField: "Range")
            }
            #expect(ranges == [nil, "bytes=1600-"])
        }
    }

    @Test func removeDeletesAReadyModel() async throws {
        try await withStore(replies: [.init(status: 200, body: body)]) { store in
            store.download()
            await store.idle()
            store.remove()
            #expect(store.state == .notDownloaded)
            await store.idle()
            #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        }
    }

    @Test func removeDuringADownloadStopsItAndKeepsNoFiles() async throws {
        try await withStore(replies: [.init(status: 200, body: body.prefix(2000), ending: .hang)]) { store in
            store.download()
            try await waitUntil { store.state == .downloading(fraction: 0.5) }
            store.remove()
            #expect(store.state == .notDownloaded)
            await store.idle()
            #expect(store.state == .notDownloaded)
            #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
            #expect(!FileManager.default.fileExists(atPath: store.partialURL.path))
        }
    }

    @Test func cancelStopsADownloadAndDeletesThePartialFile() async throws {
        try await withStore(replies: [.init(status: 200, body: body.prefix(2000), ending: .hang)]) { store in
            store.download()
            try await waitUntil { store.state == .downloading(fraction: 0.5) }
            store.cancel()
            #expect(store.state == .notDownloaded)
            await store.idle()
            #expect(!FileManager.default.fileExists(atPath: store.partialURL.path))
        }
    }

    @Test func aPartialOrWrongSizeFileIsNotReady() throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "ciel-speech-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = SpeechModel(
            fileName: "model.gguf", url: URL(string: "https://example.invalid/model.gguf")!,
            byteCount: Int64(body.count), sha256: hex(body))
        try body.write(to: ModelDownload.partialURL(for: folder.appending(path: model.fileName)))
        #expect(SpeechModelStore(model: model, folder: folder).state == .notDownloaded)
        try body.prefix(10).write(to: folder.appending(path: model.fileName))
        #expect(SpeechModelStore(model: model, folder: folder).state == .notDownloaded)
    }

    private func withStore(
        replies: [StubURLProtocol.Reply], sha256: String? = nil,
        _ run: (SpeechModelStore) async throws -> Void
    ) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "ciel-speech-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = URL(string: "https://example.invalid/\(UUID().uuidString)/model.gguf")!
        StubURLProtocol.queue(replies, for: url)
        let model = SpeechModel(
            fileName: "model.gguf", url: url, byteCount: Int64(body.count), sha256: sha256 ?? hex(body))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        try await run(SpeechModelStore(model: model, folder: folder, configuration: configuration))
    }

    private func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

final class StubURLProtocol: URLProtocol {
    struct Reply: Sendable {
        enum Ending: Sendable { case finish, drop, hang }

        let status: Int
        let body: Data
        var ending = Ending.finish
    }

    private static let replies = OSAllocatedUnfairLock<[URL: [Reply]]>(initialState: [:])
    private static let received = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])

    static func queue(_ queued: [Reply], for url: URL) { replies.withLock { $0[url] = queued } }

    static func requests(for url: URL) -> [URLRequest] { received.withLock { $0.filter { $0.url == url } } }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let request = request
        Self.received.withLock { $0.append(request) }
        let reply = Self.replies.withLock { $0[url]?.isEmpty == false ? $0[url]?.removeFirst() : nil }
        guard let reply,
            let response = HTTPURLResponse(
                url: url, statusCode: reply.status, httpVersion: nil,
                headerFields: ["Content-Type": "application/octet-stream"])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        switch reply.ending {
        case .finish: client?.urlProtocolDidFinishLoading(self)
        // A real connection drops after the bytes before it were delivered, so the failure waits for a
        // later turn of the loading thread's run loop.
        case .drop:
            perform(
                #selector(dropConnection), with: nil, afterDelay: 0.05,
                inModes: [RunLoop.current.currentMode ?? .default])
        case .hang: break
        }
    }

    override func stopLoading() { NSObject.cancelPreviousPerformRequests(withTarget: self) }

    @objc private func dropConnection() {
        client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
    }
}
