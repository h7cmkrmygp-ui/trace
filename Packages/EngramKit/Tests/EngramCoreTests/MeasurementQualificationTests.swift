import Foundation
import Testing
@testable import EngramCore

/// F15 — une mesure n'entre dans les suivis que si c'est un fait actuel du propriétaire : dit par lui (« je », ou sans
/// sujet), affirmé, ni ancien, ni souhaité, ni supposé, ni rapporté, ni à propos de quelqu'un d'autre. Les expressions
/// régulières ne lisent la valeur et l'unité qu'après ce contrôle.
struct MeasurementQualificationTests {
    @Test func theOwnersCurrentMeasurementCounts() {
        #expect(MeasurementParser.parse("Je pèse 162,5 livres").map(\.value) == [162.5])
        #expect(MeasurementParser.parse("Pesée ce matin : 165 livres").map(\.value) == [165])
        #expect(MeasurementParser.parse("Mon poids : 74 kg").map(\.value) == [74])
        #expect(MeasurementParser.parse("Je pèse 166 livres avant-hier").map(\.daysBefore) == [2])
        #expect(MeasurementParser.parse("J'ai dormi 7 h 30").map(\.value) == [7.5])
        #expect(MeasurementParser.parse("Tension 118 sur 76").map(\.value) == [118])
    }

    @Test func theSameNumberIsNotTheOwnersMeasurementOtherwise() {
        for text in ["Mon frère pèse 80 kg", "Julie pèse 60 kg", "Elle pèse 60 kg", "Mon chien pèse 30 livres",
                     "Je ne pèse pas 80 kg", "Je pesais 180 livres l'an passé",
                     "Si je pèse plus de 170 livres, je recommence le gym", "Le médecin m'a dit que je pèse 180 livres",
                     "Je voudrais peser 150 livres", "Est-ce que je pèse 160 livres ?",
                     "La tension de mon père est 140 sur 90", "Julie a dormi 7 h", "Je n'ai pas dormi 8 heures"] {
            #expect(MeasurementParser.parse(text).isEmpty, "\(text)")
        }
    }

    @Test func engramOnlyTellsTheModelAboutTheOwnersMeasurements() {
        #expect(NoteFacts.describe("Mon frère pèse 80 kg").isEmpty)
        #expect(NoteFacts.describe("Je pèse 162 livres") == ["une mesure de poids"])
    }

    @Test func aHabitIsNotDoneWhenItIsOnlySupposedOrReported() {
        #expect(HabitParser.parse("J'ai médité 10 minutes").map(\.habit) == [.meditation])
        #expect(HabitParser.parse("Si j'ai médité 10 minutes ce soir, je dormirai mieux").isEmpty)
        #expect(HabitParser.parse("Paul dit que j'ai couru trop vite").isEmpty)
    }
}
