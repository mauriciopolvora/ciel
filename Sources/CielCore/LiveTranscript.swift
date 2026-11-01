/// Builds a transcript while someone is still speaking, from repeated passes over the newest audio.
///
/// A word is committed once two passes in a row agree on it and it ends at least `settle` before
/// the newest audio. The rest stays tentative. When the audio a pass must cover grows past
/// `window`, the next pass starts in the latest pause among the committed words, so every pass and
/// the final one stay short however long the speech runs. A pause is found in the audio, not the
/// word times, because the model hears little or nothing in a pass that starts inside speech. A
/// pass that hears nothing changes nothing, except that it undoes the cut just before it.
public struct LiveTranscript: Sendable, Equatable {
    public private(set) var committed: [SpokenWord] = []
    public private(set) var tentative: [SpokenWord] = []
    /// The first sample the next pass needs.
    public private(set) var start = 0
    private var uncut: Int?
    private let settle: Int
    private let window: Int

    public init(settle: Int = 8_000, window: Int = 160_000) {
        self.settle = settle
        self.window = window
    }

    public var committedText: String { Transcript(words: committed).text }
    public var tentativeText: String { Transcript(words: tentative).text }

    /// Takes the words a pass heard in `audio`, recorded from `start`.
    public mutating func update(_ words: [SpokenWord], heard audio: [Float]) {
        guard !words.isEmpty else {
            start = uncut ?? start
            uncut = nil
            return
        }
        uncut = nil
        let end = start + audio.count
        let fresh = unseen(words)
        let agreed = zip(fresh, tentative).prefix { $0.key == $1.key && $0.end <= end - settle }.count
        committed += fresh.prefix(agreed)
        tentative = Array(fresh.dropFirst(agreed))
        if end - start > 2 * window {
            let settled = tentative.prefix { $0.end <= end - settle }.count
            committed += tentative.prefix(settled)
            tentative.removeFirst(settled)
        }
        if end - start > window { cut(audio) }
    }

    /// Takes the words of the last pass, over the rest of the audio from `start`, and returns the whole transcript.
    public mutating func finish(_ words: [SpokenWord]) -> String {
        committed += words.isEmpty ? tentative : unseen(words)
        tentative = []
        return committedText
    }

    private func unseen(_ words: [SpokenWord]) -> [SpokenWord] {
        var fresh = words.map { $0.shifted(by: start) }
        guard let last = committed.last else { return fresh }
        fresh.removeFirst(fresh.prefix { $0.start + $0.end <= 2 * last.end }.count)
        if let first = fresh.first, first.start < last.end + Self.repeatGap {
            let repeated = (1...min(3, committed.count, fresh.count)).last {
                committed.suffix($0).map(\.key) == fresh.prefix($0).map(\.key)
            }
            fresh.removeFirst(repeated ?? 0)
        }
        return fresh
    }

    /// Moves `start` to the middle of the latest pause, a stretch much quieter than the pass, that the committed words cover.
    private mutating func cut(_ audio: [Float]) {
        guard let last = committed.last, last.end > start else { return }
        let energy = audio.reduce(into: [0.0]) { $0.append($0.last! + Double($1 * $1)) }
        let quiet = energy.last! / Double(audio.count) / 100
        let pause = stride(from: last.end - start - Self.pause, through: 0, by: -Self.hop).first {
            (energy[$0 + Self.pause] - energy[$0]) / Double(Self.pause) <= quiet
        }
        guard let pause else { return }
        uncut = start
        start += pause + Self.pause / 2
    }

    private static let repeatGap = 4_800
    private static let pause = 4_800
    private static let hop = 160
}

/// A word and where it was spoken, in samples at 16 kHz.
public struct SpokenWord: Sendable, Equatable {
    public let text: String
    public let start: Int
    public let end: Int

    public init(text: String, start: Int, end: Int) {
        self.text = text
        self.start = start
        self.end = end
    }

    var key: String { String(text.lowercased().filter { $0.isLetter || $0.isNumber }) }

    func shifted(by offset: Int) -> SpokenWord {
        SpokenWord(text: text, start: start + offset, end: end + offset)
    }
}
