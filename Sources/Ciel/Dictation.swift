import AVFoundation
import Accelerate
import AppKit
import Carbon
import CielCore
import os

@MainActor protocol AudioRecorder {
    func start() throws
    func recorded(from start: Int) -> AudioClip
    func stop() -> AudioClip
}

@MainActor final class Dictation {
    enum Activity { case idle, listening, transcribing }

    private enum Phase {
        case idle
        case holding(since: ContinuousClock.Instant)
        case toggled
        case stopping
        case transcribing

        var activity: Activity {
            switch self {
            case .idle: .idle
            case .holding, .toggled, .stopping: .listening
            case .transcribing: .transcribing
            }
        }
    }

    private var phase = Phase.idle {
        didSet { if phase.activity != oldValue.activity { onActivity(phase.activity) } }
    }
    private var transcript = LiveTranscript()
    private var live: Task<Void, Never>?
    private let recorder: any AudioRecorder
    private let tapLimit: Duration
    private let interval: Duration
    private let transcriber: () throws -> any Transcriber
    private let deliver: (String) -> Void
    private let fail: (String) -> Void
    private let onActivity: (Activity) -> Void
    private let onText: (_ committed: String, _ tentative: String) -> Void

    init(
        recorder: any AudioRecorder, tapLimit: Duration = .milliseconds(300),
        interval: Duration = .milliseconds(500), transcriber: @escaping () throws -> any Transcriber,
        deliver: @escaping (String) -> Void, fail: @escaping (String) -> Void,
        onActivity: @escaping (Activity) -> Void = { _ in },
        onText: @escaping (_ committed: String, _ tentative: String) -> Void = { _, _ in }
    ) {
        self.recorder = recorder
        self.tapLimit = tapLimit
        self.interval = interval
        self.transcriber = transcriber
        self.deliver = deliver
        self.fail = fail
        self.onActivity = onActivity
        self.onText = onText
    }

    func press() {
        switch phase {
        case .idle:
            do {
                let engine = try transcriber()
                try recorder.start()
                phase = .holding(since: .now)
                listen(engine)
            } catch {
                fail(error.localizedDescription)
            }
        case .toggled: phase = .stopping
        case .holding, .stopping, .transcribing: break
        }
    }

    func release() {
        switch phase {
        case .holding(let since) where ContinuousClock.now - since < tapLimit: phase = .toggled
        case .holding, .stopping: finish()
        case .idle, .toggled, .transcribing: break
        }
    }

    /// A cancel while stopping means the key joined another shortcut, so listening goes on.
    func cancel() {
        switch phase {
        case .stopping: phase = .toggled
        case .holding, .toggled:
            _ = recorder.stop()
            live?.cancel()
            phase = .idle
        case .idle, .transcribing: break
        }
    }

    /// Transcribes the newest audio every `interval` while listening, so release only waits for the last few seconds.
    private func listen(_ engine: any Transcriber) {
        transcript = LiveTranscript()
        live = Task { [weak self, interval] in
            try? await engine.prepare()
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                await self.refresh(engine)
            }
        }
    }

    private func refresh(_ engine: any Transcriber) async {
        let clip = recorder.recorded(from: transcript.start)
        guard clip.samples.count >= Self.shortestPass, let words = try? await engine.transcribe(clip).words,
            !Task.isCancelled
        else { return }
        transcript.update(words, heard: clip.samples)
        onText(transcript.committedText, transcript.tentativeText)
    }

    private func finish() {
        let clip = recorder.stop()
        live?.cancel()
        guard let engine = try? transcriber() else {
            phase = .idle
            return
        }
        phase = .transcribing
        let tail = AudioClip(samples: Array(clip.samples.dropFirst(transcript.start)))
        Task {
            do {
                let text = transcript.finish(try await engine.transcribe(tail).words)
                if !text.isEmpty { deliver(text) }
            } catch {
                fail(error.localizedDescription)
            }
            phase = .idle
        }
    }

    private static let shortestPass = 8_000
}

enum DictationError: LocalizedError {
    case off, notReady

    var errorDescription: String? {
        switch self {
        case .off: "Turn on Speech to text in Settings."
        case .notReady: "Download the speech model in Settings."
        }
    }
}

@MainActor final class Microphone: AudioRecorder {
    private let engine = AVAudioEngine()
    private let samples = OSAllocatedUnfairLock<[Float]>(initialState: [])
    private let onLevel: @MainActor @Sendable (Float) -> Void

    init(onLevel: @escaping @MainActor @Sendable (Float) -> Void = { _ in }) { self.onLevel = onLevel }

    func start() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw MicrophoneError.asking
        default: throw MicrophoneError.denied
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let resampler = Resampler(from: format.sampleRate) else {
            throw MicrophoneError.unavailable
        }
        samples.withLock { $0.removeAll() }
        // The tap runs on an audio thread, so it must not inherit the main actor.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) {
            @Sendable [samples, onLevel, resampler] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            var level: Float = 0
            vDSP_rmsqv(channel, 1, &level, vDSP_Length(buffer.frameLength))
            let chunk = resampler.convert(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            samples.withLock { $0 += chunk }
            Task { @MainActor [level] in onLevel(level) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func recorded(from start: Int) -> AudioClip {
        AudioClip(samples: samples.withLock { Array($0.dropFirst(start)) })
    }

    func stop() -> AudioClip {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return AudioClip(
            samples: samples.withLock { buffer in
                defer { buffer = [] }
                return buffer
            })
    }
}

/// One converter serves every buffer so its filter state carries across buffer boundaries.
struct Resampler: Sendable {
    private let converter: OSAllocatedUnfairLock<AVAudioConverter>?
    private let ratio: Double

    init?(from rate: Double) {
        ratio = 16_000 / rate
        guard rate != 16_000 else {
            converter = nil
            return
        }
        guard let source = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
            let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
            let converter = AVAudioConverter(from: source, to: target)
        else { return nil }
        self.converter = OSAllocatedUnfairLock(uncheckedState: converter)
    }

    func convert(_ samples: UnsafeBufferPointer<Float>) -> [Float] {
        guard let converter else { return Array(samples) }
        return converter.withLockUnchecked { converter in
            guard
                let input = AVAudioPCMBuffer(
                    pcmFormat: converter.inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                let inputChannel = input.floatChannelData?[0],
                let output = AVAudioPCMBuffer(
                    pcmFormat: converter.outputFormat,
                    frameCapacity: AVAudioFrameCount(Double(samples.count) * ratio) + 64)
            else { return [] }
            input.frameLength = input.frameCapacity
            _ = UnsafeMutableBufferPointer(start: inputChannel, count: samples.count).update(
                fromContentsOf: samples)
            let pending = OSAllocatedUnfairLock<AVAudioPCMBuffer?>(uncheckedState: input)
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                let next = pending.withLockUnchecked { buffer in
                    defer { buffer = nil }
                    return buffer
                }
                inputStatus.pointee = next == nil ? .noDataNow : .haveData
                return next
            }
            guard status != .error, let channel = output.floatChannelData?[0] else { return [] }
            return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        }
    }
}

enum MicrophoneError: LocalizedError {
    case asking, denied, unavailable

    var errorDescription: String? {
        switch self {
        case .asking: "Allow the microphone, then press the shortcut again."
        case .denied: "Allow Ciel in System Settings → Privacy & Security → Microphone."
        case .unavailable: "No microphone is available."
        }
    }
}

/// Pastes through the clipboard, then puts back what was there unless something else changed it meanwhile.
@MainActor enum TextPaster {
    static func paste(_ text: String, into pasteboard: NSPasteboard = .general) -> Bool {
        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard WindowController.isTrusted else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        let changeCount = pasteboard.changeCount
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard pasteboard.changeCount == changeCount, let saved else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(
                saved.map { pairs in
                    let item = NSPasteboardItem()
                    for (type, data) in pairs { item.setData(data, forType: type) }
                    return item
                })
        }
        return true
    }
}
