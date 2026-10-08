import Foundation
import Testing
@testable import EngramCapture

/// Stratégie bilingue de Whisper : le français n'est jamais imposé ; une phrase mélangée est décodée
/// dans les deux langues et on garde ce que le modèle juge le plus probable.
struct BilingualStrategyTests {
    @Test(arguments: [
        ("fr", 0.95, LanguagePlan.single("fr")),
        ("en", 0.90, LanguagePlan.single("en")),
        ("fr", 0.60, LanguagePlan.both),
        ("en", 0.84, LanguagePlan.both),
        ("pt", 0.99, LanguagePlan.both),
    ])
    func decidesWhichLanguagesToDecode(detected: String, probability: Double, expected: LanguagePlan) {
        #expect(LanguagePlan.decide(detected: detected, probability: probability) == expected)
    }

    @Test func plansListTheirLanguages() {
        #expect(LanguagePlan.single("en").languages == ["en"])
        #expect(LanguagePlan.both.languages == ["fr", "en"])
    }

    @Test func convertsALogProbabilitySafely() {
        #expect(abs(LanguagePlan.probability(fromLog: log(0.9)) - 0.9) < 1e-9)
        #expect(LanguagePlan.probability(fromLog: .nan) == 0)
        #expect(LanguagePlan.probability(fromLog: -.infinity) == 0)
        #expect(LanguagePlan.probability(fromLog: 5) == 1)
    }

    @Test func picksTheHypothesisTheModelIsMostSureOf() {
        let french = Hypothesis(language: "fr", text: "Faut que je call mon manager", averageLogProbability: -0.2)
        let english = Hypothesis(language: "en", text: "I have to call my manager", averageLogProbability: -0.9)
        #expect(HypothesisPicker.best([english, french]) == french)
    }

    @Test func ignoresEmptyOrEchoedHypothesesAndPrefersFrenchOnATie() {
        let empty = Hypothesis(language: "en", text: "  ", averageLogProbability: -0.01)
        let echo = Hypothesis(language: "fr", text: WhisperPrompt.bilingual, averageLogProbability: -0.05)
        let french = Hypothesis(language: "fr", text: "Pis après le gym", averageLogProbability: -0.5)
        let english = Hypothesis(language: "en", text: "And then the gym", averageLogProbability: -0.5)
        #expect(HypothesisPicker.best([empty, echo, english, french]) == french)
        #expect(HypothesisPicker.best([empty, echo]) == nil)
    }

    @Test func assemblesChunksAndReportsTheLanguagesUsed() {
        let pieces = [
            Hypothesis(language: "fr", text: " Faut que je call mon manager demain. ", averageLogProbability: -0.2),
            Hypothesis(language: "en", text: "Then I'll book the meeting.", averageLogProbability: -0.3),
            Hypothesis(language: "fr", text: "", averageLogProbability: -0.1),
        ]
        let transcript = TranscriptAssembler.assemble(pieces)
        #expect(transcript.text == "Faut que je call mon manager demain. Then I'll book the meeting.")
        #expect(transcript.localeIdentifier == "fr+en")
        #expect(TranscriptAssembler.assemble([pieces[0]]).localeIdentifier == "fr")
        #expect(TranscriptAssembler.assemble([]).text.isEmpty)
    }

    @Test func modelsHaveStableIdentifiersAndTurboIsTheDefault() {
        #expect(WhisperModel.default == .largeV3Turbo)
        #expect(WhisperModel.largeV3Turbo.rawValue == "openai_whisper-large-v3-v20240930_626MB")
        #expect(WhisperModel.largeV3.rawValue == "openai_whisper-large-v3_947MB")
        #expect(Set(WhisperModel.allCases.map(\.engineName)).count == WhisperModel.allCases.count)
        #expect(WhisperModel.allCases.allSatisfy { !$0.label.isEmpty && $0.approximateSizeMB > 500 })
    }

    /// Les trois stratégies comparées par le banc d'essai ; la bilingue est celle par défaut.
    @Test func strategiesAreStableAndBilingualIsTheDefault() {
        #expect(TranscriptionStrategy.default == .bilingual)
        #expect(TranscriptionStrategy.allCases.map(\.rawValue) == ["bilingual", "french", "automatic"])
        #expect(TranscriptionStrategy.allCases.allSatisfy { !$0.label.isEmpty })
        #expect(TranscriptionStrategy.frenchOnly.fixedPlan == .single("fr"))
        #expect(TranscriptionStrategy.bilingual.fixedPlan == nil)
        #expect(TranscriptionStrategy.automatic.fixedPlan == nil)
    }

    @Test func thePromptMixesBothLanguagesAndIsPunctuated() {
        #expect(WhisperPrompt.bilingual.contains("call"))
        #expect(WhisperPrompt.bilingual.contains("meeting"))
        #expect(WhisperPrompt.bilingual.contains(","))
        #expect(WhisperPrompt.bilingual.hasSuffix("."))
    }
}
