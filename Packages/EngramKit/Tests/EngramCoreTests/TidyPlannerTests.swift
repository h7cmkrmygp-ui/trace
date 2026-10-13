import Foundation
import Testing
@testable import EngramCore

/// P40 — le ménage automatique des dossiers : doublons fusionnés, noms anglais en français, petits sous-dossiers repliés,
/// notes clairement mal rangées déplacées. Jamais un dossier ni une note choisis par le propriétaire.
struct TidyPlannerTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    func folder(_ name: String, parent: UUID? = nil, notes: Int, byOwner: Bool = false, daysOld: Double = 30,
                ownerNotes: Bool = false, hasChildren: Bool = false) -> TidyFolder {
        TidyFolder(id: UUID(), name: name, parentID: parent, createdByOwner: byOwner, noteCount: notes,
                   createdAt: Self.now.addingTimeInterval(-daysOld * 86_400), hasOwnerNotes: ownerNotes,
                   hasChildren: hasChildren)
    }

    @Test func duplicateFoldersAreMergedIntoTheBiggestOrTheOwnersOwn() {
        let auto = folder("Auto", notes: 2)
        let automobile = folder("Automobile", notes: 5)
        #expect(TidyPlanner.merges([auto, automobile]) == [.merge(source: auto.id, into: automobile.id)])
        // Le dossier du propriétaire reste, même plus petit, et n'est jamais fusionné dans un autre.
        let voiture = folder("Voiture", notes: 1, byOwner: true)
        #expect(TidyPlanner.merges([auto, automobile, voiture])
            == [.merge(source: auto.id, into: voiture.id), .merge(source: automobile.id, into: voiture.id)])
        // Deux dossiers sans rapport ne bougent pas ; deux sous-dossiers de parents différents non plus.
        let parentA = UUID()
        let parentB = UUID()
        #expect(TidyPlanner.merges([folder("Auto", notes: 2), folder("Finances", notes: 3)]).isEmpty)
        #expect(TidyPlanner.merges([folder("Assurance", parent: parentA, notes: 2),
                                    folder("Insurance", parent: parentB, notes: 2)]).isEmpty)
    }

    @Test func englishNamesBecomeFrench() {
        let carPart = folder("car part", parent: UUID(), notes: 3)
        let groceries = folder("Groceries", notes: 4)
        let mine = folder("Work", notes: 2, byOwner: true)
        #expect(TidyPlanner.renames([carPart, groceries, mine])
            == [.rename(folder: carPart.id, to: "Pièces auto"), .rename(folder: groceries.id, to: "Épicerie")])
        // Le nom français existe déjà à côté : pas de doublon, la fusion s'en charge.
        let epicerie = folder("Épicerie", notes: 1)
        #expect(TidyPlanner.renames([groceries, epicerie]).isEmpty)
    }

    @Test func smallSubfoldersFoldBackAfterTwoWeeks() {
        let parent = folder("Automobile", notes: 6, hasChildren: true)
        let tiny = folder("Wipers", parent: parent.id, notes: 1)
        let enough = folder("Corolla", parent: parent.id, notes: 3)
        let young = folder("Pneus", parent: parent.id, notes: 1, daysOld: 5)
        let chosen = folder("Garage", parent: parent.id, notes: 1, ownerNotes: true)
        let owners = folder("Assurance", parent: parent.id, notes: 1, byOwner: true)
        #expect(TidyPlanner.folds([parent, tiny, enough, young, chosen, owners], now: Self.now)
            == [.fold(folder: tiny.id, into: parent.id)])
    }

    @Test func aClearlyMisfiledNoteJoinsItsSimilarNotes() {
        let note = UUID()
        let wrong = TidyNote(id: note, paths: ["Automobile › Pièces"],
                             evidence: [FolderEvidence(path: "Finances › Assurances", notes: 4, byOwner: 1)])
        #expect(TidyPlanner.moves([wrong]) == [.move(memory: note, from: "Automobile › Pièces", to: "Finances › Assurances")])
        // Des notes semblables aussi dans son dossier, ou trop peu d'indices : elle reste.
        let mixed = TidyNote(id: UUID(), paths: ["Automobile"],
                             evidence: [FolderEvidence(path: "Finances", notes: 4, byOwner: 0),
                                        FolderEvidence(path: "Automobile", notes: 2, byOwner: 0)])
        let weak = TidyNote(id: UUID(), paths: ["Automobile"], evidence: [FolderEvidence(path: "Finances", notes: 2, byOwner: 0)])
        #expect(TidyPlanner.moves([mixed, weak]).isEmpty)
    }

    @Test func eachChangeIsDescribedForTheOwner() {
        #expect(TidyPlanner.summary(merged: "Auto", into: "Automobile", notes: 2)
            == "« Auto » fusionné dans « Automobile » (2 notes).")
        #expect(TidyPlanner.summary(renamed: "car part", to: "Pièces auto") == "« car part » renommé « Pièces auto ».")
        #expect(TidyPlanner.summary(folded: "Wipers", into: "Automobile", notes: 1)
            == "« Wipers » replié dans « Automobile » (1 note).")
        #expect(TidyPlanner.summary(moved: "Réévaluer l'assurance", from: "Automobile › Pièces", to: "Finances › Assurances")
            == "« Réévaluer l'assurance » déplacée de « Automobile › Pièces » vers « Finances › Assurances ».")
    }
}
