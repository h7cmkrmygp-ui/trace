import Foundation
import Testing
@testable import EngramCore

/// F01/F13/F17 — une seule règle de confidentialité pour toutes les sorties ; une politique inconnue interdit toute sortie
/// automatique ; un ensemble (une liste) est aussi protégé que sa contribution la plus protégée.
struct PrivacyPolicyTests {
    static let unknown = PrivacyFacts(keepLocal: false, level: nil, basis: nil)
    static let neutral = PrivacyFacts(keepLocal: false, level: .neutral, basis: .judged)
    static let personal = PrivacyFacts(keepLocal: false, level: .personal, basis: .judged)
    static let keptLocal = PrivacyFacts(keepLocal: true, level: .secret, basis: .ownerKeepLocal)
    static let judgedSecret = PrivacyFacts(keepLocal: false, level: .secret, basis: .judged)
    static let offline = PrivacyFacts(keepLocal: false, level: .secret, basis: .noCloudService)
    static let everythingLocal = PrivacyFacts(keepLocal: false, level: .secret, basis: .everythingLocal)

    func allowed(_ facts: PrivacyFacts) -> Set<PrivacyDestination> {
        Set(PrivacyDestination.allCases.filter { PrivacyPolicy.allows(facts, $0) })
    }

    @Test func anUnknownPolicyForbidsEveryAutomaticOutput() {
        #expect(allowed(Self.unknown).isEmpty)
        // « Garder sur l'iPhone » choisi avant même l'analyse : connu, et seulement le calendrier de l'iPhone.
        #expect(allowed(PrivacyFacts(keepLocal: true, level: nil, basis: nil)) == [.localCalendar])
    }

    @Test func eachDecisionHasItsDestinations() {
        #expect(allowed(Self.neutral) == Set(PrivacyDestination.allCases))
        #expect(allowed(Self.personal) == [.lockScreen, .assistantExport, .syncedCalendar, .localCalendar, .cloudPersonal])
        #expect(allowed(Self.keptLocal) == [.localCalendar])
        #expect(allowed(Self.judgedSecret) == [.localCalendar])
        // Classée sur l'iPhone faute de service : son contenu n'a pas été jugé ; ses dérivés ne partent vers aucun service.
        #expect(allowed(Self.offline) == [.lockScreen, .assistantExport, .syncedCalendar, .localCalendar])
        // « Tout garder sur l'iPhone » : un calendrier synchronisé ou un assistant sont des destinations externes.
        #expect(allowed(Self.everythingLocal) == [.lockScreen, .localCalendar])
    }

    @Test func anAggregateIsAsProtectedAsItsMostProtectedContribution() {
        #expect(!PrivacyPolicy.allows([Self.neutral, Self.keptLocal], .lockScreen))
        #expect(!PrivacyPolicy.allows([Self.neutral, Self.personal], .cloudNeutral))
        #expect(PrivacyPolicy.allows([Self.neutral, Self.personal], .cloudPersonal))
        // Aucune contribution connue : rien ne sort.
        #expect(!PrivacyPolicy.allows([], .lockScreen))
        // Le masque des destinations interdites dit la même chose, et ne fait qu'accumuler.
        let mask = PrivacyPolicy.forbiddenMask(Self.neutral) | PrivacyPolicy.forbiddenMask(Self.keptLocal)
        #expect(!PrivacyPolicy.allows(mask: mask, .lockScreen))
        #expect(PrivacyPolicy.allows(mask: mask, .localCalendar))
        #expect(PrivacyPolicy.allows(mask: PrivacyPolicy.forbiddenMask(Self.neutral), .cloudNeutral))
        #expect(!PrivacyPolicy.allows(mask: PrivacyPolicy.forbiddenMask(Self.unknown), .localCalendar))
    }

    @Test func aRouteKnowsItsBasis() {
        #expect(AnalysisRoute(level: .secret, provider: "apple", reason: RouteReasons.noCloudService, needsCloudRetry: true)
            .effectiveBasis == .noCloudService)
        #expect(AnalysisRoute(level: .secret, provider: "apple", reason: "Contient un mot de passe.", needsCloudRetry: false)
            .effectiveBasis == .judged)
        #expect(AnalysisRoute(level: .secret, provider: "apple", reason: "x", needsCloudRetry: false, basis: .ownerKeepLocal)
            .effectiveBasis == .ownerKeepLocal)
    }
}
