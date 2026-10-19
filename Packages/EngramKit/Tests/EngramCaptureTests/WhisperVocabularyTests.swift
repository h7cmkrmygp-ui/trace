import Foundation
import Testing
@testable import EngramCapture

/// P37 — la transcription connaît les noms du propriétaire (personnes, lieux, dossiers) : moins de noms mal entendus.
struct WhisperVocabularyTests {
    @Test func theNamesAreAddedToWhispersPrompt() {
        let prompt = WhisperPrompt.make(names: ["Julie", "Marc Tremblay", "Costco", "Corolla"])
        #expect(prompt.hasPrefix(WhisperPrompt.bilingual))
        #expect(prompt.hasSuffix("Julie, Marc Tremblay, Costco, Corolla."))
        #expect(WhisperPrompt.make(names: []) == WhisperPrompt.bilingual)
    }

    @Test func theListStaysShortAndClean() {
        let many = (1...200).map { "Personne\($0)" }
        let prompt = WhisperPrompt.make(names: many)
        #expect(prompt.count <= WhisperPrompt.bilingual.count + 1 + WhisperPrompt.maxNamesLength + 1)
        // Doublons (majuscules, accents) et noms d'une lettre écartés.
        #expect(WhisperPrompt.make(names: ["Léa", "lea", "J", "Marc"]).hasSuffix("Léa, Marc."))
    }

    @Test func repeatingTheNamesIsAnEchoNotSpeech() {
        let prompt = WhisperPrompt.make(names: ["Julie", "Costco"])
        #expect(WhisperPrompt.isEcho("Julie, Costco.", prompt: prompt))
        #expect(WhisperPrompt.isEcho(WhisperPrompt.bilingual, prompt: prompt))
        #expect(!WhisperPrompt.isEcho("Appeler Julie avant d'aller au Costco", prompt: prompt))
    }
}
