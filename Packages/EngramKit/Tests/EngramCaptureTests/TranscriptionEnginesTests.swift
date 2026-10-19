import Foundation
import Testing
@testable import EngramCapture

struct TranscriptionEnginesTests {
    @Test func whisperIsTheDefaultAndThePaidEngineIsGone() {
        #expect(TranscriptionEngine.default == .whisper)
        #expect(TranscriptionEngine(rawValue: "whisper") == .whisper)
        #expect(TranscriptionEngine(rawValue: "apple") == .apple)
        #expect(TranscriptionEngine(rawValue: "openai") == nil)
        #expect(TranscriptionEngine.allCases.allSatisfy { !$0.label.isEmpty })
    }

    @Test func transcriptCollapsesWhitespace() {
        let transcript = Transcript(text: "  Appeler   le garage \n demain ", localeIdentifier: "fr")
        #expect(transcript.text == "Appeler le garage demain")
    }
}
