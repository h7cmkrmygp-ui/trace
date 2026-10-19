import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramIntelligence

/// F03, F16, F07 — un seul contrat pour Apple et le nuage : intention, polarité, sujet, action, objet, bénéficiaire et
/// dates avec leur rôle ; une réponse refusée reçoit ses erreurs précises pour un seul nouvel essai.
struct IntentContractPromptTests {
    @Test func theCloudContractAsksForTheIntentAndItsArguments() throws {
        let system = CloudPrompt.system
        for word in ["intent", "polarity", "subject", "action", "object", "beneficiary"] {
            #expect(system.contains(word), "\(word)")
        }
        #expect(system.contains("obligation"))
        #expect(system.contains("hypothesis"))
        let schema = CloudSchema.response(.gemini)
        let note = try #require(((schema["properties"] as? [String: Any])?["notes"] as? [String: Any])?["items"] as? [String: Any])
        let order = try #require(note["propertyOrdering"] as? [String])
        for field in ["intent", "polarity", "subject", "action", "object", "beneficiary"] {
            #expect(order.contains(field), "\(field)")
        }
        // L'intention vient avant la liste et le dossier : le modèle comprend, puis range.
        let intent = try #require(order.firstIndex(of: "intent"))
        #expect(intent < (order.firstIndex(of: "list") ?? 0))
        #expect(intent < (order.firstIndex(of: "category") ?? 0))
    }

    @Test func theDecoderKeepsTheIntentAndTheRoleOfEachDate() throws {
        let answer = #"{"notes":[{"title":"Dentiste","excerpt":"Rendez-vous mardi à 14 h, rappelle-le-moi lundi à 18 h","kind":"appointment","intent":"appointment","polarity":"affirmative","subject":"moi","action":"aller","object":"dentiste","beneficiary":"","category":"Santé","dates":[{"phrase":"mardi à 14 h","role":"event"},{"phrase":"lundi à 18 h","role":"reminder"}]}]}"#
        let thought = try #require(try CloudDecoder.decode(answer).thoughts.first)
        #expect(thought.intent == .appointment)
        #expect(thought.polarity == .affirmative)
        #expect(thought.subject == "moi")
        #expect(thought.action == "aller")
        #expect(thought.beneficiary == nil)
        #expect(thought.temporal == [TemporalMention(role: .event, phrase: "mardi à 14 h"),
                                     TemporalMention(role: .reminder, phrase: "lundi à 18 h")])
        // Une intention inconnue ne devient pas une intention par défaut.
        let unknown = #"{"notes":[{"title":"x","excerpt":"x","kind":"task","intent":"buy_stuff","category":"Divers"}]}"#
        #expect(try CloudDecoder.decode(unknown).thoughts.first?.intent == nil)
    }

    @Test func aRefusedAnswerGetsItsPreciseErrorsOnce() {
        let context = CloudContext(now: Date(timeIntervalSince1970: 1_791_475_200),
                                   timeZone: TimeZone(identifier: "America/Toronto")!,
                                   repairNotes: ["L'extrait « Call the garage » n'est pas dans la note : recopie les mots exacts."])
        let prompt = CloudPrompt.user(text: "Faut que j'appelle le garage", categories: [], context: context)
        #expect(prompt.contains("Corrections demandées"))
        #expect(prompt.contains("Call the garage"))
        #expect(!CloudPrompt.user(text: "x", categories: [], context: CloudContext(now: Date(), timeZone: .current))
            .contains("Corrections demandées"))
        #expect(CloudPrompt.version == "p50-cloud-v1")
    }

    #if canImport(FoundationModels)
    @Test func theAppleModelUsesTheSameContract() {
        #expect(AnalysisPrompt.version == "p50-v1")
        for word in ["intent", "polarity", "subject", "action", "object"] {
            #expect(AnalysisPrompt.instructions.contains(word), "\(word)")
        }
        #expect(AnalysisPrompt.prompt(text: "x", categories: [], likely: [], repairNotes: ["Recopie les mots exacts."])
            .contains("Corrections requested"))
    }
    #endif
}
