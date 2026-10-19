import Foundation
import Testing
import WhisperKit
@testable import EngramCapture

/// Garde-fou : quelle que soit la langue choisie, Whisper transcrit et ne traduit jamais.
struct WhisperOptionsTests {
    @Test(arguments: ["fr", "en"])
    func aChosenLanguageIsDecodedAsIsWithoutTranslation(language: String) {
        let options = WhisperTranscriber.options(language: language, prompt: [1, 2, 3])
        #expect(options.task == .transcribe)
        #expect(options.language == language)
        #expect(options.detectLanguage == false)
        #expect(options.promptTokens == [1, 2, 3])
        #expect(options.withoutTimestamps)
    }

    @Test func freeDetectionLetsWhisperChooseButStillNeverTranslates() {
        let options = WhisperTranscriber.options(language: nil, prompt: nil)
        #expect(options.task == .transcribe)
        #expect(options.language == nil)
        #expect(options.detectLanguage)
    }

    @Test func aHypothesisAveragesItsSegmentsConfidence() {
        let empty = WhisperTranscriber.hypothesis(language: "fr", results: [])
        #expect(empty.text.isEmpty)
        #expect(empty.averageLogProbability == -.infinity)
    }
}
