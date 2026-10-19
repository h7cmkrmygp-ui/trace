import EngramCore
import Foundation
import Testing
@testable import EngramStore

struct CategoryStoreTests {
    @Test func seedsDefaultRootsOnlyOnce() throws {
        let env = try StoreTestEnvironment()
        try env.categories.seedDefaultsIfNeeded()
        try env.categories.seedDefaultsIfNeeded()
        let names = try env.categories.activeCategories().map(\.name)
        #expect(Set(names) == Set(CategoryStore.defaultRootNames))
        #expect(names.count == 9)
    }

    @Test func archivedSeedIsNotRecreated() throws {
        let env = try StoreTestEnvironment()
        try env.categories.seedDefaultsIfNeeded()
        let voyages = try #require(try env.categories.activeCategories().first { $0.name == "Voyages" })
        try env.categories.archiveCategory(voyages.id)
        try env.categories.seedDefaultsIfNeeded()
        #expect(try env.categories.activeCategories().contains { $0.name == "Voyages" } == false)
    }

    @Test(arguments: ["voyage", "VOYAGES", "  Voyagés ", "voyages"])
    func equivalentNamesReuseTheExistingCategory(name: String) throws {
        let env = try StoreTestEnvironment()
        let original = try env.categories.createCategory(name: "Voyages", parentID: nil, origin: .user).category
        guard case .existing(let reused) = try env.categories.createCategory(name: name, parentID: nil, origin: .ai) else {
            Issue.record("« \(name) » aurait dû réutiliser « Voyages »")
            return
        }
        #expect(reused.id == original.id)
    }

    @Test func sameNameIsAllowedUnderDifferentParents() throws {
        let env = try StoreTestEnvironment()
        let sante = try env.categories.createCategory(name: "Santé", parentID: nil, origin: .user).category
        let child = try env.categories.createCategory(name: "Course à pied", parentID: sante.id, origin: .ai)
        let root = try env.categories.createCategory(name: "Course à pied", parentID: nil, origin: .user)
        guard case .created = child, case .created = root else {
            Issue.record("deux catégories distinctes étaient attendues")
            return
        }
        #expect(try env.categories.descendantIDs(of: sante.id).count == 2)
    }

    @Test func rejectsBlankOrTooLongNames() throws {
        let env = try StoreTestEnvironment()
        #expect(throws: StoreError.invalidName) { try env.categories.createCategory(name: "  !! ", parentID: nil, origin: .user) }
        #expect(throws: StoreError.invalidName) {
            try env.categories.createCategory(name: String(repeating: "x", count: 41), parentID: nil, origin: .user)
        }
    }

    @Test func renameRefusesASiblingName() throws {
        let env = try StoreTestEnvironment()
        _ = try env.categories.createCategory(name: "Travail", parentID: nil, origin: .user)
        let perso = try env.categories.createCategory(name: "Perso", parentID: nil, origin: .user).category
        #expect(throws: StoreError.nameConflict) { try env.categories.rename(perso.id, to: "travail") }
        #expect(try env.categories.rename(perso.id, to: "Personnel").name == "Personnel")
    }

    @Test func aiAssignmentActivatesAnUnsortedMemory() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Préparer la réunion budget")
        let travail = try env.categories.createCategory(name: "Travail", parentID: nil, origin: .seed).category
        #expect(try env.categories.assign(memoryID: memory.id, categoryID: travail.id, origin: .ai, confidence: 0.8) == .assigned)
        #expect(try env.status(of: memory) == .active)
        #expect(try env.categories.categories(for: memory.id).map(\.id) == [travail.id])
    }

    @Test func userRemovalIsRememberedAndBlocksTheAI() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Préparer la réunion budget")
        let travail = try env.categories.createCategory(name: "Travail", parentID: nil, origin: .seed).category
        _ = try env.categories.assign(memoryID: memory.id, categoryID: travail.id, origin: .ai)
        try env.categories.removeAssignment(memoryID: memory.id, categoryID: travail.id, by: .user)
        #expect(try env.status(of: memory) == .unsorted)
        #expect(try env.categories.assign(memoryID: memory.id, categoryID: travail.id, origin: .ai) == .skippedRejectedByUser)
        #expect(try env.categories.categories(for: memory.id).isEmpty)
        #expect(try env.categories.assign(memoryID: memory.id, categoryID: travail.id, origin: .user) == .assigned)
        #expect(try env.status(of: memory) == .active)
    }

    @Test func aiCannotRemoveAConfirmedAssignment() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Facture garage")
        let finances = try env.categories.createCategory(name: "Finances", parentID: nil, origin: .seed).category
        _ = try env.categories.assign(memoryID: memory.id, categoryID: finances.id, origin: .ai)
        try env.categories.confirm(memoryID: memory.id, categoryID: finances.id)
        #expect(throws: StoreError.protectedByUser) {
            try env.categories.removeAssignment(memoryID: memory.id, categoryID: finances.id, by: .ai)
        }
    }

    @Test func archivingACategoryMovesChildrenUpAndUnsortsOrphans() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Plan de course")
        let sante = try env.categories.createCategory(name: "Santé", parentID: nil, origin: .seed).category
        let sport = try env.categories.createCategory(name: "Sport", parentID: sante.id, origin: .ai).category
        _ = try env.categories.assign(memoryID: memory.id, categoryID: sante.id, origin: .user)
        try env.categories.archiveCategory(sante.id)
        #expect(try env.status(of: memory) == .unsorted)
        let movedSport = try #require(try env.categories.activeCategories().first { $0.id == sport.id })
        #expect(movedSport.parentID == nil)
    }

    @Test func mergeMovesAssignmentsAndKeepsTheStrongestDecision() throws {
        let env = try StoreTestEnvironment()
        let both = try env.saveNote("Réservation hôtel")
        let onlyOld = try env.saveNote("Billet de train")
        let voyagesPerso = try env.categories.createCategory(name: "Voyages perso", parentID: nil, origin: .ai).category
        let voyages = try env.categories.createCategory(name: "Voyages", parentID: nil, origin: .seed).category
        _ = try env.categories.assign(memoryID: both.id, categoryID: voyagesPerso.id, origin: .user)
        _ = try env.categories.assign(memoryID: both.id, categoryID: voyages.id, origin: .ai)
        _ = try env.categories.assign(memoryID: onlyOld.id, categoryID: voyagesPerso.id, origin: .ai)
        try env.categories.merge(voyagesPerso.id, into: voyages.id)
        #expect(try env.categories.activeCategories().contains { $0.id == voyagesPerso.id } == false)
        #expect(try env.categories.categories(for: both.id).map(\.id) == [voyages.id])
        #expect(try env.categories.categories(for: onlyOld.id).map(\.id) == [voyages.id])
        #expect(throws: StoreError.protectedByUser) {
            try env.categories.removeAssignment(memoryID: both.id, categoryID: voyages.id, by: .ai)
        }
    }

    @Test func cannotMergeIntoOwnDescendant() throws {
        let env = try StoreTestEnvironment()
        let parent = try env.categories.createCategory(name: "Projets", parentID: nil, origin: .seed).category
        let child = try env.categories.createCategory(name: "Engram", parentID: parent.id, origin: .user).category
        #expect(throws: StoreError.self) { try env.categories.merge(parent.id, into: child.id) }
    }

    @Test func tagsAreDeduplicatedAndRespectUserRemoval() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Idée de widget")
        let tag = try env.categories.upsertTag(name: "Idée", origin: .ai)
        #expect(try env.categories.upsertTag(name: "idee", origin: .user).id == tag.id)
        #expect(try env.categories.tag(memoryID: memory.id, tagID: tag.id, origin: .ai) == .assigned)
        try env.categories.untag(memoryID: memory.id, tagID: tag.id, by: .user)
        #expect(try env.categories.tag(memoryID: memory.id, tagID: tag.id, origin: .ai) == .skippedRejectedByUser)
        #expect(try env.categories.tags(for: memory.id).isEmpty)
    }

    @Test func librarySummaryCountsByCategoryAndStatus() async throws {
        let env = try StoreTestEnvironment()
        let sante = try env.categories.createCategory(name: "Santé", parentID: nil, origin: .seed).category
        _ = try env.categories.createCategory(name: "Sport", parentID: sante.id, origin: .ai)
        let classed = try env.saveNote("Rendez-vous médecin")
        _ = try env.categories.assign(memoryID: classed.id, categoryID: sante.id, origin: .user)
        try env.saveNote("Pensée en vrac")
        let trashed = try env.saveNote("À jeter")
        _ = try env.memories.setStatus(.trashed, for: trashed.id, actor: .user)

        var iterator = env.categories.librarySummaryStream().makeAsyncIterator()
        let summary = try #require(try await iterator.next())
        #expect(summary.unsortedCount == 1)
        #expect(summary.trashedCount == 1)
        #expect(summary.archivedCount == 0)
        // « Sport » ne contient rien : la bibliothèque ne l'affiche pas.
        #expect(summary.categories.map(\.category.name) == ["Santé"])
        #expect(summary.categories.map(\.depth) == [0])
        #expect(summary.categories.first?.memoryCount == 1)
    }
}
