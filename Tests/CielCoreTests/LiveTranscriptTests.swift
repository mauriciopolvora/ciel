import CielCore
import Testing

@Suite struct LiveTranscriptTests {
    private static let second = 16_000

    @Test func wordsTwoPassesAgreeOnAreCommittedAndTheRestIsTentative() {
        var transcript = LiveTranscript()
        transcript.update(Self.speech("the quick brown"), heard: Self.quiet(2 * Self.second))
        #expect(transcript.committedText.isEmpty)
        #expect(transcript.tentativeText == "the quick brown")
        transcript.update(Self.speech("the quick brown fox"), heard: Self.quiet(3 * Self.second))
        #expect(transcript.committedText == "the quick brown")
        #expect(transcript.tentativeText == "fox")
    }

    @Test func aWordTheNextPassHearsDifferentlyStaysTentative() {
        var transcript = LiveTranscript()
        transcript.update(Self.speech("I scream today"), heard: Self.quiet(3 * Self.second))
        transcript.update(Self.speech("ice cream today"), heard: Self.quiet(4 * Self.second))
        #expect(transcript.committedText.isEmpty)
        #expect(transcript.tentativeText == "ice cream today")
    }

    @Test func aWordAtTheEdgeOfTheAudioStaysTentativeEvenWhenPassesAgree() {
        var transcript = LiveTranscript()
        let words = Self.speech("see you")
        transcript.update(words, heard: Self.quiet(words[1].end))
        transcript.update(words, heard: Self.quiet(words[1].end + Self.second / 4))
        #expect(transcript.committedText == "see")
        #expect(transcript.tentativeText == "you")
    }

    @Test func punctuationAndCaseChangesStillAgree() {
        var transcript = LiveTranscript()
        transcript.update(Self.speech("hello there"), heard: Self.quiet(3 * Self.second))
        transcript.update(Self.speech("Hello, there"), heard: Self.quiet(4 * Self.second))
        #expect(transcript.committedText == "Hello, there")
    }

    @Test func finishingAddsTheLastPassAfterTheCommittedWords() {
        var transcript = LiveTranscript()
        transcript.update(Self.speech("send the"), heard: Self.quiet(2 * Self.second))
        transcript.update(Self.speech("send the report"), heard: Self.quiet(3 * Self.second))
        #expect(transcript.finish(Self.speech("send the report today")) == "send the report today")
        #expect(transcript.tentativeText.isEmpty)
    }

    @Test func aCommittedWordHeardAgainLaterIsNotRepeated() {
        var transcript = LiveTranscript()
        let words = Self.speech("a b c")
        transcript.update(words, heard: Self.quiet(3 * Self.second))
        transcript.update(words, heard: Self.quiet(4 * Self.second))
        let drifted = SpokenWord(text: "c", start: words[2].start + 4_000, end: words[2].end + 4_000)
        transcript.update(
            Array(words.prefix(2)) + [drifted] + Self.speech("d e", from: drifted.end + 1_600),
            heard: Self.quiet(5 * Self.second))
        #expect(transcript.committedText == "a b c")
        #expect(transcript.tentativeText == "d e")
    }

    @Test func aWordSaidTwiceInARowIsKeptTwice() {
        var transcript = LiveTranscript()
        transcript.update(Self.speech("the words"), heard: Self.quiet(3 * Self.second))
        transcript.update(Self.speech("the words"), heard: Self.quiet(4 * Self.second))
        transcript.update(Self.speech("the words the words"), heard: Self.quiet(5 * Self.second))
        #expect(transcript.committedText == "the words")
        #expect(transcript.tentativeText == "the words")
    }

    @Test func aWordHeardLateIsKeptEvenWhenItStartsBeforeTheLastCommittedWordEnds() {
        var transcript = LiveTranscript()
        let stretched = [
            SpokenWord(text: "send", start: 0, end: 6_400),
            SpokenWord(text: "the", start: 8_000, end: 16_000),
        ]
        transcript.update(stretched, heard: Self.quiet(3 * Self.second))
        transcript.update(stretched, heard: Self.quiet(3 * Self.second))
        transcript.update(
            [
                stretched[0], SpokenWord(text: "the", start: 8_000, end: 12_800),
                SpokenWord(text: "report", start: 12_800, end: 17_600),
            ], heard: Self.quiet(4 * Self.second))
        #expect(transcript.committedText == "send the")
        #expect(transcript.tentativeText == "report")
    }

    @Test func theLastPassReplacesTheWordsItHeardAgain() {
        var transcript = LiveTranscript()
        transcript.update(Self.speech("turn left"), heard: Self.quiet(2 * Self.second))
        transcript.update(Self.speech("turn left"), heard: Self.quiet(3 * Self.second))
        #expect(transcript.committedText == "turn left")
        #expect(transcript.finish(Self.speech("turn right")) == "turn right")
    }

    @Test(arguments: [10, 45, 120])
    func longSpeechStitchesEveryWordOnceWithShortPassesThatStartInPauses(seconds: Int) {
        let script = Self.script(seconds: seconds)
        let audio = Self.audio(script, seconds: seconds)
        var transcript = LiveTranscript()
        var longest = 0
        for end in stride(from: Self.second, through: seconds * Self.second, by: Self.second) {
            longest = max(longest, end - transcript.start)
            transcript.update(
                Self.heard(script, from: transcript.start, to: end),
                heard: Array(audio[transcript.start..<end]))
            #expect(!script.contains { $0.start <= transcript.start && transcript.start < $0.end })
        }
        let finalPass = seconds * Self.second - transcript.start
        let text = transcript.finish(Self.heard(script, from: transcript.start, to: seconds * Self.second))
        #expect(text == script.map(\.text).joined(separator: " "))
        #expect(longest <= 11 * Self.second)
        #expect(finalPass <= 11 * Self.second)
    }

    @Test func passesThatNeverAgreeStillStayBoundedAndKeepEveryWord() {
        let script = Self.script(seconds: 60)
        let audio = Self.audio(script, seconds: 60)
        var transcript = LiveTranscript()
        var longest = 0
        for (pass, end) in stride(from: Self.second, through: 60 * Self.second, by: Self.second).enumerated()
        {
            longest = max(longest, end - transcript.start)
            let heard = Self.heard(script, from: transcript.start, to: end).map {
                SpokenWord(
                    text: $0.text + String(repeating: "x", count: pass % 2), start: $0.start, end: $0.end)
            }
            transcript.update(heard, heard: Array(audio[transcript.start..<end]))
        }
        let text = transcript.finish(Self.heard(script, from: transcript.start, to: 60 * Self.second))
        #expect(text.split(separator: " ").count == script.count)
        #expect(longest <= 21 * Self.second)
    }

    @Test func speechWithNoPauseIsNeverCutInside() {
        let words = (0..<30).map {
            SpokenWord(text: "w\($0)", start: $0 * Self.second / 2, end: ($0 + 1) * Self.second / 2)
        }
        let audio = [Float](repeating: 0.3, count: 15 * Self.second)
        var transcript = LiveTranscript()
        for end in stride(from: Self.second, through: 15 * Self.second, by: Self.second) {
            transcript.update(words.filter { $0.end <= end }, heard: Array(audio[..<end]))
        }
        #expect(transcript.start == 0)
    }

    @Test func aPassThatHearsNothingKeepsWhatWasHeard() {
        var transcript = LiveTranscript()
        transcript.update(Self.speech("the quick brown"), heard: Self.quiet(2 * Self.second))
        transcript.update(Self.speech("the quick brown fox"), heard: Self.quiet(3 * Self.second))
        let heard = transcript
        transcript.update([], heard: Self.quiet(4 * Self.second))
        #expect(transcript == heard)
    }

    @Test func aPassThatHearsNothingRightAfterACutUndoesIt() {
        let script = Self.script(seconds: 30)
        let audio = Self.audio(script, seconds: 30)
        var transcript = LiveTranscript()
        var end = Self.second
        while transcript.start == 0 {
            transcript.update(
                Self.heard(script, from: 0, to: end), heard: Array(audio[..<end]))
            end += Self.second
        }
        transcript.update([], heard: Array(audio[transcript.start..<end]))
        #expect(transcript.start == 0)
    }

    @Test func aLastPassThatHearsNothingKeepsTheTentativeWords() {
        var transcript = LiveTranscript()
        transcript.update(Self.speech("send the"), heard: Self.quiet(2 * Self.second))
        transcript.update(Self.speech("send the report"), heard: Self.quiet(3 * Self.second))
        #expect(transcript.finish([]) == "send the report")
    }

    private static func quiet(_ count: Int) -> [Float] { [Float](repeating: 0, count: count) }

    private static func speech(_ text: String, from start: Int = 0) -> [SpokenWord] {
        text.split(separator: " ").enumerated().map { index, word in
            let begin = start + index * second / 2
            return SpokenWord(text: String(word), start: begin, end: begin + second * 2 / 5)
        }
    }

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

    private static func audio(_ script: [SpokenWord], seconds: Int) -> [Float] {
        var audio = [Float](repeating: 0.001, count: seconds * second)
        for word in script {
            audio.replaceSubrange(
                word.start..<word.end, with: repeatElement(0.3, count: word.end - word.start))
        }
        return audio
    }

    /// Each word runs on to the next one, the way the model times them.
    private static func heard(_ script: [SpokenWord], from start: Int, to end: Int) -> [SpokenWord] {
        let inside = script.filter { $0.start >= start && $0.end <= end }
        return zip(inside, inside.dropFirst().map(\.start) + [inside.last?.end ?? end]).map { word, next in
            SpokenWord(text: word.text, start: word.start - start, end: next - start)
        }
    }
}
