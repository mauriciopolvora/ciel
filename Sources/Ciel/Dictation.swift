import AVFoundation
import AppKit
import Carbon
import CielCore
import os

@MainActor protocol AudioRecorder {
    func start() throws
    func stop() -> AudioClip
}

/// Hold to talk: the shortcut press starts the microphone and its release transcribes and delivers the text.
@MainActor final class Dictation {
    private enum Phase {
        case idle
        case listening(since: ContinuousClock.Instant)
        case transcribing
    }

    private var phase = Phase.idle
    private let recorder: any AudioRecorder
    private let minimumHold: Duration
    private let transcriber: () throws -> any Transcriber
    private let deliver: (String) -> Void
    private let fail: (String) -> Void

    init(
        recorder: any AudioRecorder, minimumHold: Duration = .milliseconds(250),
        transcriber: @escaping () throws -> any Transcriber, deliver: @escaping (String) -> Void,
        fail: @escaping (String) -> Void
    ) {
        self.recorder = recorder
        self.minimumHold = minimumHold
        self.transcriber = transcriber
        self.deliver = deliver
        self.fail = fail
    }

    func press() {
        guard case .idle = phase else { return }
        do {
            _ = try transcriber()
            try recorder.start()
            phase = .listening(since: .now)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func release() {
        guard case .listening(let since) = phase else { return }
        let clip = recorder.stop()
        guard ContinuousClock.now - since >= minimumHold, let engine = try? transcriber() else {
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

/// Captures the default input and hands back 16 kHz mono samples.
@MainActor final class Microphone: AudioRecorder {
    private let engine = AVAudioEngine()
    private let samples = OSAllocatedUnfairLock<[Float]>(initialState: [])
    private var sampleRate: Double = 0

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
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable [samples] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            samples.withLock { $0 += chunk }
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
        case .asking: "Allow the microphone, then hold the shortcut again."
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
