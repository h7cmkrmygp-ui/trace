import EngramCore
import Foundation
import Testing
@testable import EngramIntelligence

/// Juge factice : renvoie le verdict prévu, ou échoue (IA d'Apple indisponible).
struct FakeJudge: PrivacyJudge {
    let verdict: PrivacyVerdict?

    func judge(_ text: String) async throws -> PrivacyJudgement {
        guard let verdict else { throw AnalyzerError.unavailable("indisponible") }
        return PrivacyJudgement(verdict: verdict, reason: "jugement factice")
    }
}

/// Le contrôleur de confidentialité décide **sur l'iPhone** où une note peut être classée.
struct PrivacyGateTests {
    func level(_ text: String, judge verdict: PrivacyVerdict?, keepLocal: Bool = false,
               healthStaysLocal: Bool = false) async -> PrivacyLevel {
        await PrivacyGate.evaluate(text, keepLocal: keepLocal, healthStaysLocal: healthStaysLocal,
                                   judge: FakeJudge(verdict: verdict)).level
    }

    @Test func aClearlyNeutralNoteCanGoToTheNeutralService() async {
        #expect(await level("Acheter du lait et du pain", judge: .neutral) == .neutral)
    }

    @Test func withoutTheAppleJudgementTheNoteStaysOnTheIPhone() async {
        #expect(await level("Acheter du lait et du pain", judge: nil) == .secret)
        let decision = await PrivacyGate.evaluate("Acheter du lait", keepLocal: false, healthStaysLocal: false, judge: nil)
        #expect(decision.level == .secret)
    }

    @Test func doubtAlwaysGoesToTheMostProtectedLevel() async {
        #expect(await level("Rappeler le garage", judge: .unsure) == .secret)
    }

    /// Les mots-clés ne font que monter le niveau : une note de santé n'atteint jamais Gemini,
    /// même si le jugement d'Apple dit « neutre ».
    @Test func keywordsCanOnlyRaiseTheLevel() async {
        #expect(await level("Je pèse 75 kg ce matin", judge: .neutral) == .personal)
        #expect(await level("Acheter du lait", judge: .personal) == .personal)
        #expect(await level("Faut que je call mon manager pour mon shift", judge: .neutral) == .personal)
        #expect(await level("Payer 245 $ au plombier", judge: .neutral) == .personal)
    }

    @Test func healthCanBeKeptOnTheIPhone() async {
        #expect(await level("Je pèse 75 kg ce matin", judge: .neutral, healthStaysLocal: true) == .secret)
        #expect(await level("Prendre rendez-vous chez le dentiste", judge: .personal, healthStaysLocal: true) == .secret)
    }

    @Test func theOwnerCanKeepANoteOnTheIPhone() async {
        #expect(await level("Acheter du lait", judge: .neutral, keepLocal: true) == .secret)
    }

    @Test func secretsNeverLeaveTheIPhone() async {
        #expect(await level("Mon mot de passe du wifi est soleil123", judge: .personal) == .secret)
        #expect(await level("Ma carte 4111 1111 1111 1111 expire bientôt", judge: .neutral) == .secret)
        #expect(await level("Mon NIP est 4821", judge: .neutral) == .secret)
        #expect(await level("Renouveler mon passeport", judge: .neutral) == .secret)
        #expect(await level("Acheter un cadeau", judge: .secret) == .secret)
    }

    /// Un code suivi de chiffres (casier, cadenas, porte, alarme) est un secret, même sans le mot « mot de passe ».
    @Test func aCodeFollowedByDigitsIsASecret() async {
        #expect(await level("Mon code de casier est 4821", judge: .neutral) == .secret)
        #expect(await level("La combinaison du cadenas : 1 2 3 4", judge: .neutral) == .secret)
        #expect(await level("Lock code is 0000", judge: .neutral) == .secret)
        // Un code sans chiffres n'est pas un secret en soi.
        #expect(await level("Apprendre à coder en Swift", judge: .neutral) == .neutral)
    }

    @Test func detectorsFindContactDetailsAndAmounts() {
        let levels = { (text: String) in Set(SensitiveDetectors.signals(in: text).map(\.level)) }
        #expect(levels("Écrire à quelqu'un@example.com").contains(.personal))
        #expect(levels("Payer 245 $ demain").contains(.personal))
        #expect(levels("Mon compte 12345678 à la banque").contains(.secret))
        #expect(SensitiveDetectors.signals(in: "Acheter du lait et du pain").isEmpty)
    }

    @Test func cardNumbersAreCheckedWithLuhn() {
        #expect(SensitiveDetectors.isLuhnValid("4111111111111111"))
        #expect(!SensitiveDetectors.isLuhnValid("4111111111111112"))
    }

    @Test func lexiconMatchesWholeWordsWithoutAccents() {
        #expect(!SensitiveLexicon.signals(in: "Je pese 75 kg", healthStaysLocal: false).isEmpty)
        // « gymnase » ne déclenche pas « gym », « empereur » ne déclenche pas « père ».
        #expect(SensitiveLexicon.signals(in: "Visiter l'empereur", healthStaysLocal: false).isEmpty)
        // Un poids en livres est de la santé, pas des livres à lire.
        #expect(SensitiveLexicon.signals(in: "Acheter des livres pour l'école", healthStaysLocal: false).isEmpty)
        #expect(!SensitiveLexicon.signals(in: "Je pèse 162 livres", healthStaysLocal: false).isEmpty)
    }

    @Test func categoryNamesThatRevealSomethingPersonalAreNotSent() {
        #expect(PrivacyGate.shareableCategoryNames(["Santé", "Travail", "Maison › Jardin", "Écrire à quelqu'un@example.com"])
                == ["Santé", "Travail", "Maison › Jardin"])
    }

    @Test func theDecisionExplainsItself() async {
        let decision = await PrivacyGate.evaluate("Je pèse 75 kg", keepLocal: false, healthStaysLocal: false,
                                                  judge: FakeJudge(verdict: .neutral))
        #expect(!decision.reasons.isEmpty)
    }
}
