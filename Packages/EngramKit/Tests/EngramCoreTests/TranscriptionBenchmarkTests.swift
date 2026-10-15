import Foundation
import Testing
@testable import EngramCore

/// Banc d'essai Turbo / Large V3 : mesures et règle de décision (aucun changement sans validation suffisante).
struct TranscriptionBenchmarkTests {
    @Test func wordsIgnoreCaseAndPunctuationButKeepAccents() {
        #expect(WordErrorRate.words("Faut que j'aille au dépanneur, OK?") == ["faut", "que", "j", "aille", "au", "dépanneur", "ok"])
        #expect(WordErrorRate.words("Rendez-vous à 14h30 — 245 $") == ["rendez", "vous", "à", "14", "h", "30", "245"])
        #expect(WordErrorRate.words("  ") == [])
    }

    @Test func wordErrorRateCountsSubstitutionsDeletionsAndInsertions() {
        #expect(WordErrorRate.rate(reference: "faut que je call mon manager", hypothesis: "Faut que je call mon manager.") == 0)
        // « call » remplacé, « manager » supprimé : 2 erreurs sur 6 mots.
        #expect(abs(WordErrorRate.rate(reference: "faut que je call mon manager", hypothesis: "faut que je colle mon") - 2.0 / 6.0) < 1e-9)
        // Un mot inséré.
        #expect(WordErrorRate.errors(reference: ["a", "b"], hypothesis: ["a", "x", "b"]) == 1)
        #expect(WordErrorRate.rate(reference: "", hypothesis: "") == 0)
        #expect(WordErrorRate.rate(reference: "", hypothesis: "bonjour") == 1)
    }

    @Test func englishRetentionMeasuresAnglicismsKeptAsSpoken() {
        let words = ["call", "manager", "shift"]
        #expect(EnglishRetention.rate(englishWords: words, hypothesis: "Faut que je call mon manager pour changer mon shift") == 1)
        #expect(abs((EnglishRetention.rate(englishWords: words, hypothesis: "Faut que j'appelle mon gestionnaire pour mon shift") ?? -1) - 1.0 / 3.0) < 1e-9)
        #expect(EnglishRetention.rate(englishWords: [], hypothesis: "Acheter du lait") == nil)
    }

    @Test func pairedBootstrapIsReproducibleAndDetectsAClearImprovement() throws {
        let items = (0..<30).map { _ in BenchmarkItem(referenceWords: 10, baselineErrors: 2, candidateErrors: 0) }
        let comparison = try #require(PairedBootstrap.compare(items, iterations: 500, seed: 7))
        #expect(abs(comparison.baselineRate - 0.2) < 1e-9)
        #expect(abs(comparison.candidateRate) < 1e-9)
        #expect(comparison.upper < 0)
        #expect(comparison == PairedBootstrap.compare(items, iterations: 500, seed: 7))
        #expect(PairedBootstrap.compare([], iterations: 500, seed: 7) == nil)
    }

    @Test func noisyEqualModelsGiveAnIntervalThatIncludesZero() throws {
        let items = (0..<40).map { index in
            BenchmarkItem(referenceWords: 10, baselineErrors: index % 2 == 0 ? 1 : 2, candidateErrors: index % 2 == 0 ? 2 : 1)
        }
        let comparison = try #require(PairedBootstrap.compare(items, iterations: 1_000, seed: 3))
        #expect(comparison.lower < 0 && comparison.upper > 0)
    }

    func evidence(sentences: Int = 40, notes: Int = 25, baseline: Int = 3, candidate: Int = 1,
                  runsWell: Bool = true) -> BenchmarkEvidence {
        let items = (0..<(sentences + notes)).map { _ in
            BenchmarkItem(referenceWords: 10, baselineErrors: baseline, candidateErrors: candidate)
        }
        return BenchmarkEvidence(sentencesRead: sentences, sentencesTotal: 40, correctedNotes: notes, items: items,
                                 candidateRunsWell: runsWell)
    }

    @Test func proposesTheCandidateOnlyWithEnoughClearEvidence() {
        guard case .proposeSwitch = ModelRecommendation.evaluate(evidence()) else {
            Issue.record("une nette amélioration sur tout le jeu d'essai doit être proposée")
            return
        }
    }

    @Test func neverDecidesAfterAFewTests() {
        guard case .needMoreData = ModelRecommendation.evaluate(evidence(sentences: 10, notes: 0)) else {
            Issue.record("dix essais ne suffisent pas")
            return
        }
        guard case .needMoreData = ModelRecommendation.evaluate(evidence(notes: 5)) else {
            Issue.record("il faut aussi des notes réelles corrigées")
            return
        }
    }

    @Test func keepsTheCurrentModelWhenTheGainIsSmallOrTheDeviceStruggles() {
        // 3 % → 2,9 % : moins de 2 points.
        let small = BenchmarkEvidence(sentencesRead: 40, sentencesTotal: 40, correctedNotes: 25,
                                      items: (0..<65).map { BenchmarkItem(referenceWords: 100, baselineErrors: 3, candidateErrors: $0 % 10 == 0 ? 2 : 3) },
                                      candidateRunsWell: true)
        guard case .keepCurrent = ModelRecommendation.evaluate(small) else {
            Issue.record("un gain minime ne justifie pas de changer")
            return
        }
        guard case .keepCurrent = ModelRecommendation.evaluate(evidence(runsWell: false)) else {
            Issue.record("un modèle trop lent ou trop lourd n'est pas proposé")
            return
        }
    }

    @Test func theBilingualTestSetIsRepresentative() {
        let set = BilingualTestSet.sentences
        #expect(set.count >= 40)
        #expect(Set(set.map(\.id)).count == set.count)
        #expect(set.filter { $0.kind == .mixed }.count >= 15)
        #expect(set.filter { $0.kind == .english }.count >= 5)
        #expect(set.filter { $0.kind == .french }.count >= 5)
        // Les mots anglais annotés figurent bien dans la phrase.
        for sentence in set where sentence.kind == .mixed {
            let words = Set(WordErrorRate.words(sentence.text))
            #expect(!sentence.englishWords.isEmpty)
            #expect(sentence.englishWords.allSatisfy { words.contains($0) }, "\(sentence.text)")
        }
        // Une phrase en anglais : tous ses mots comptent.
        let english = set.first { $0.kind == .english }
        #expect(english?.englishWords == english.map { WordErrorRate.words($0.text) })
    }
}
