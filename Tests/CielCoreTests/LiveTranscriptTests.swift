import CielCore
import Testing

@Suite struct LiveTranscriptTests {
    private static let second = 16_000

    @Test func wordsTwoPassesAgreeOnAreCommittedAndTheRestIsTentative() {
        var transcript = LiveTranscript()
        transcript.update(Self.speech("the quick brown"), end: 2 * Self.second)
        #expect(transcript.committedText.isEmpty)
        #expect(transcript.tentativeText == "the quick brown")
        transcript.update(Self.speech("the quick brown fox"), end: 3 * Self.second)
        #expect(transcript.committedText == "the quick brown")
        #expect(transcript.tentativeText == "fox")
    }

    @Test func aWordTheNextPassHearsDifferentlyStaysTentative() {
        var transcript = LiveTranscript()
        transcript.update(Self.speech("I scream today"), end: 3 * Self.second)
        transcript.update(Self.speech("ice cream today"), end: 4 * Self.second)
        #expect(transcript.committedText.isEmpty)
        #expect(transcript.tentativeText == "ice cream today")
    }

    @Test func aWordAtTheEdgeOfTheAudioStaysTentativeEvenWhenPassesAgree() {
        var transcript = LiveTranscript()
        let words = Self.speech("see you")
        transcript.update(words, end: words[1].end)
        transcript.update(words, end: words[1].end + Self.second / 4)
        #expect(transcript.committedText == "see")
        #expect(transcript.tentativeText == "you")
    }

    @Test func punctuationAndCaseChangesStillAgree() {
        var transcript = LiveTranscript()
        transcript.update(Self.speech("hello there"), end: 3 * Self.second)
        transcript.update(Self.speech("Hello, there"), end: 4 * Self.second)
        #expect(transcript.committedText == "Hello, there")
    }

    @Test func finishingAddsTheLastPassAfterTheCommittedWords() {
        var transcript = LiveTranscript()
        transcript.update(Self.speech("send the"), end: 2 * Self.second)
        transcript.update(Self.speech("send the report"), end: 3 * Self.second)
        #expect(transcript.finish(Self.speech("send the report today")) == "send the report today")
        #expect(transcript.tentativeText.isEmpty)
    }

    @Test func aCommittedWordHeardAgainLaterIsNotRepeated() {
        var transcript = LiveTranscript()
        let words = Self.speech("a b c")
        transcript.update(words, end: 3 * Self.second)
        transcript.update(words, end: 4 * Self.second)
        #expect(transcript.committedText == "a b c")
        let drifted = SpokenWord(text: "c", start: words[2].start + 4_000, end: words[2].end + 4_000)
        let next = Self.speech("d e", from: drifted.end + 1_600)
        #expect(transcript.finish([drifted] + next) == "a b c d e")
    }

    @Test(arguments: [10, 45, 120])
    func longSpeechStitchesEveryWordOnceWithShortPasses(seconds: Int) {
        let script = Self.script(seconds: seconds)
        var transcript = LiveTranscript()
        var longest = 0
        for end in stride(from: Self.second, through: seconds * Self.second, by: Self.second) {
            longest = max(longest, end - transcript.start)
            transcript.update(Self.heard(script, from: transcript.start, to: end), end: end)
        }
        let finalPass = seconds * Self.second - transcript.start
        let text = transcript.finish(Self.heard(script, from: transcript.start, to: seconds * Self.second))
        #expect(text == script.map(\.text).joined(separator: " "))
        #expect(longest <= 11 * Self.second)
        #expect(finalPass <= 11 * Self.second)
    }

    @Test func passesThatNeverAgreeStillStayBoundedAndKeepEveryWord() {
        let script = Self.script(seconds: 60)
        var transcript = LiveTranscript()
        var longest = 0
        for (pass, end) in stride(from: Self.second, through: 60 * Self.second, by: Self.second).enumerated()
        {
            longest = max(longest, end - transcript.start)
            let heard = Self.heard(script, from: transcript.start, to: end).map {
                SpokenWord(
                    text: $0.text + String(repeating: "x", count: pass % 2), start: $0.start, end: $0.end)
            }
            transcript.update(heard, end: end)
        }
        let text = transcript.finish(Self.heard(script, from: transcript.start, to: 60 * Self.second))
        #expect(text.split(separator: " ").count == script.count)
        #expect(longest <= 21 * Self.second)
    }

    @Test func silenceDoesNotGrowThePass() {
        var transcript = LiveTranscript()
        for end in stride(from: Self.second, through: 60 * Self.second, by: Self.second) {
            #expect(end - transcript.start <= 11 * Self.second)
            transcript.update([], end: end)
        }
        #expect(transcript.finish([]).isEmpty)
    }

    private static func speech(_ text: String, from start: Int = 0) -> [SpokenWord] {
        text.split(separator: " ").enumerated().map { index, word in
            let begin = start + index * second / 2
            return SpokenWord(text: String(word), start: begin, end: begin + second * 2 / 5)
        }
    }

    /// Words of varied length with a longer pause after every seventh word.
    private static func script(seconds: Int) -> [SpokenWord] {
        var words: [SpokenWord] = []
        var at = second / 5
        while at < seconds * second - second {
            let length = second / 5 + (words.count % 4) * second / 10
            words.append(SpokenWord(text: "w\(words.count)", start: at, end: at + length))
            at += length + (words.count % 7 == 0 ? second * 3 / 5 : second / 20)
        }
        return words
    }

    /// What a pass over `start..<end` hears: the words inside it, timed from `start`.
    private static func heard(_ script: [SpokenWord], from start: Int, to end: Int) -> [SpokenWord] {
        script.filter { $0.start >= start && $0.end <= end }.map {
            SpokenWord(text: $0.text, start: $0.start - start, end: $0.end - start)
        }
    }
}
