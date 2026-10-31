import AVFoundation
import Accelerate
import AppKit
import Carbon
import CielCore
import os

@MainActor protocol AudioRecorder {
    func start() throws
    func stop() -> AudioClip
}

@MainActor final class Dictation {
    enum Activity { case idle, listening, transcribing }

    private enum Phase {
        case idle
        case holding(since: ContinuousClock.Instant)
        case toggled
        case transcribing

        var activity: Activity {
            switch self {
            case .idle: .idle
            case .holding, .toggled: .listening
            case .transcribing: .transcribing
            }
        }
    }

    private var phase = Phase.idle {
        didSet { if phase.activity != oldValue.activity { onActivity(phase.activity) } }
    }
    private let recorder: any AudioRecorder
    private let tapLimit: Duration
    private let transcriber: () throws -> any Transcriber
    private let deliver: (String) -> Void
    private let fail: (String) -> Void
    private let onActivity: (Activity) -> Void

    init(
        recorder: any AudioRecorder, tapLimit: Duration = .milliseconds(300),
        transcriber: @escaping () throws -> any Transcriber, deliver: @escaping (String) -> Void,
        fail: @escaping (String) -> Void, onActivity: @escaping (Activity) -> Void = { _ in }
    ) {
        self.recorder = recorder
        self.tapLimit = tapLimit
        self.transcriber = transcriber
        self.deliver = deliver
        self.fail = fail
        self.onActivity = onActivity
    }

    func press() {
        switch phase {
        case .idle:
            do {
                _ = try transcriber()
                try recorder.start()
                phase = .holding(since: .now)
            } catch {
                fail(error.localizedDescription)
            }
        case .toggled: finish()
        case .holding, .transcribing: break
        }
    }

    func release() {
        guard case .holding(let since) = phase else { return }
        if ContinuousClock.now - since < tapLimit {
            phase = .toggled
        } else {
            finish()
        }
    }

    func cancel() {
        guard case .holding = phase else { return }
        _ = recorder.stop()
        phase = .idle
    }

    private func finish() {
        let clip = recorder.stop()
        guard let engine = try? transcriber() else {
            phase = .idle
            return
        }
        phase = .transcribing
        Task {
            do {
                let text = try await engine.transcribe(clip).text
                if !text.isEmpty { deliver(text) }
            } catch {
                fail(error.localizedDescription)
            }
            phase = .idle
        }
    }
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
    private var sampleRate: Double = 0

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
        guard format.sampleRate > 0 else { throw MicrophoneError.unavailable }
        sampleRate = format.sampleRate
        samples.withLock { $0.removeAll() }
        // The tap runs on an audio thread, so it must not inherit the main actor.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) {
            @Sendable [samples, onLevel] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            var level: Float = 0
            vDSP_rmsqv(channel, 1, &level, vDSP_Length(buffer.frameLength))
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
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

    func stop() -> AudioClip {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let recorded = samples.withLock { buffer in
            defer { buffer = [] }
            return buffer
        }
        return AudioClip(samples: Self.resample(recorded, from: sampleRate))
    }

    nonisolated static func resample(_ samples: [Float], from rate: Double) -> [Float] {
        guard rate != 16_000 else { return samples }
        guard !samples.isEmpty, rate > 0,
            let source = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
            let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
            let converter = AVAudioConverter(from: source, to: target),
            let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
            let inputChannel = input.floatChannelData?[0],
            let output = AVAudioPCMBuffer(
                pcmFormat: target,
                frameCapacity: AVAudioFrameCount(Double(samples.count) * 16_000 / rate) + 1024)
        else { return [] }
        input.frameLength = input.frameCapacity
        inputChannel.update(from: samples, count: samples.count)
        let pending = OSAllocatedUnfairLock<AVAudioPCMBuffer?>(uncheckedState: input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            let next = pending.withLockUnchecked { buffer in
                defer { buffer = nil }
                return buffer
            }
            inputStatus.pointee = next == nil ? .endOfStream : .haveData
            return next
        }
        guard status != .error, let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
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
