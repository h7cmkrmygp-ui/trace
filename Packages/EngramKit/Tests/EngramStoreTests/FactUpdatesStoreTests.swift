import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// F21 — un fait qui change est mis à jour au lieu de s'additionner : une préférence qui change, un rendez-vous déplacé,
/// un montant corrigé, une décision révisée. L'ancienne note reste dans l'historique (archivée, reliée à la nouvelle) ;
/// une cible ambiguë ou protégée ne change rien et la correction reste à classer.
struct FactUpdatesStoreTests {
    @discardableResult
    func file(_ env: StoreTestEnvironment, _ text: String, kind: MemoryKind, intent: IntentType, people: [String] = [],
              dates: [String] = [], path: [String] = ["Divers"]) throws -> Memory {
        let interim = try env.saveNote(text)
        let memory = try #require(try env.filer.file([
            ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: kind, tags: [],
                         categoryPath: path, mentionedDates: dates, people: people, intent: intent),
        ], sourceID: interim.sourceID).memories.first)
        env.dates.advance(by: 3_600)
        return memory
    }

    @Test func aChangedPreferenceIsAnsweredAsItIsNow() throws {
        let env = try StoreTestEnvironment()
        try file(env, "Julie aime le café", kind: .preference, intent: .preference, people: ["Julie"], path: ["Famille"])
        let change = try file(env, "Julie n'aime plus le café", kind: .preference, intent: .preference, people: ["Julie"],
                              path: ["Famille"])
        let entities = EntityStore(database: env.database, dates: env.dates)
        #expect(try entities.personAnswer(to: "Qu'est-ce que Julie aime ?", now: Fixtures.date, calendar: Fixtures.calendar)
            == "D'après tes notes, Julie n'aime pas le café.")
        // La dernière note qui le disait part à la corbeille : le fait d'avant redevient l'actuel.
        _ = try env.memories.setStatus(.trashed, for: change.id, actor: .user)
        #expect(try entities.personAnswer(to: "Qu'est-ce que Julie aime ?", now: Fixtures.date, calendar: Fixtures.calendar)
            == "D'après tes notes, Julie aime le café.")
    }

    @Test func aMovedAppointmentReplacesTheOldOne() throws {
        let env = try StoreTestEnvironment()
        let old = try file(env, "Rendez-vous chez le dentiste mardi à 14 h", kind: .appointment, intent: .appointment,
                           dates: ["mardi à 14 h"], path: ["Santé"])
        let new = try file(env, "Finalement le rendez-vous chez le dentiste est jeudi à 10 h", kind: .appointment,
                           intent: .correction, dates: ["jeudi à 10 h"], path: ["Santé"])
        let replaced = try #require(try env.memories.memory(id: old.id))
        #expect(replaced.status == .archived)
        #expect(replaced.supersededBy == new.id)
        #expect(try env.memories.versions(of: old.id).first?.changedBy == .system)
        #expect(try env.memories.reminderItems().map(\.id) == [new.id])
        #expect(try env.memories.memory(id: new.id)?.kind == .appointment)
    }

    @Test func aCorrectedAmountAndARevisedDecisionReplaceTheirNote() throws {
        let env = try StoreTestEnvironment()
        let rent = try file(env, "Le loyer est de 1200 $", kind: .info, intent: .fact)
        let corrected = try file(env, "Correction : le loyer est de 1250 $", kind: .info, intent: .correction)
        #expect(try env.memories.memory(id: rent.id)?.supersededBy == corrected.id)
        let car = try file(env, "J'ai décidé de garder la voiture", kind: .decision, intent: .decision)
        let revised = try file(env, "Finalement j'ai décidé de vendre la voiture", kind: .decision, intent: .correction)
        #expect(try env.memories.memory(id: car.id)?.supersededBy == revised.id)
        #expect(try env.memories.memory(id: car.id)?.status == .archived)
    }

    @Test func anAmbiguousOrProtectedTargetChangesNothing() throws {
        let env = try StoreTestEnvironment()
        let mine = try file(env, "Rendez-vous chez le dentiste mardi à 14 h", kind: .appointment, intent: .appointment,
                            dates: ["mardi à 14 h"], path: ["Santé"])
        let julie = try file(env, "Rendez-vous chez le dentiste de Julie vendredi à 9 h", kind: .appointment,
                             intent: .appointment, dates: ["vendredi à 9 h"], path: ["Santé"])
        let correction = try file(env, "Finalement le rendez-vous chez le dentiste est jeudi", kind: .appointment,
                                  intent: .correction, dates: ["jeudi"], path: ["Santé"])
        #expect(try env.memories.memory(id: mine.id)?.supersededBy == nil)
        #expect(try env.memories.memory(id: julie.id)?.supersededBy == nil)
        #expect(try env.memories.memory(id: correction.id)?.status == .unsorted)
        // Une note modifiée à la main n'est jamais remplacée par une déduction de l'IA.
        let env2 = try StoreTestEnvironment()
        let edited = try file(env2, "Le loyer est de 1200 $", kind: .info, intent: .fact)
        _ = try env2.memories.updateMemory(edited.id, with: MemoryEdit(title: "Loyer"), actor: .user)
        let later = try file(env2, "Correction : le loyer est de 1250 $", kind: .info, intent: .correction)
        #expect(try env2.memories.memory(id: edited.id)?.supersededBy == nil)
        #expect(try env2.memories.memory(id: later.id)?.status == .unsorted)
    }
}
