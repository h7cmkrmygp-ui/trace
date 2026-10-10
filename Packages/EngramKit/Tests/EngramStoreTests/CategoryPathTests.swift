import EngramCore
import Foundation
import Testing
@testable import EngramStore

struct CategoryPathTests {
    @Test func createsBothLevels() throws {
        let env = try StoreTestEnvironment()
        let corolla = try env.categories.resolvePath(["Automobile", "Corolla"], origin: .ai)
        #expect(corolla.name == "Corolla")
        let parent = try #require(try env.categories.activeCategories().first { $0.name == "Automobile" })
        #expect(corolla.parentID == parent.id)
        #expect(corolla.origin == .ai)
    }

    @Test(arguments: ["automobile", "Automobiles", "AUTOMOBILE", "  Automobile "])
    func reusesAnExistingLevelDespiteVariants(name: String) throws {
        let env = try StoreTestEnvironment()
        let first = try env.categories.resolvePath(["Automobile"], origin: .ai)
        #expect(try env.categories.resolvePath([name], origin: .ai).id == first.id)
        #expect(try env.categories.activeCategories().count == 1)
    }

    @Test func sameChildUnderTwoParentsGivesTwoCategories() throws {
        let env = try StoreTestEnvironment()
        let work = try env.categories.resolvePath(["Travail", "Projets"], origin: .ai)
        let personal = try env.categories.resolvePath(["Personnel", "Projets"], origin: .ai)
        #expect(work.id != personal.id)
    }

    @Test func rejectsAnEmptyPath() throws {
        let env = try StoreTestEnvironment()
        #expect(throws: StoreError.invalidName) { try env.categories.resolvePath([], origin: .ai) }
    }

    @Test func listsSortedFormattedPaths() throws {
        let env = try StoreTestEnvironment()
        _ = try env.categories.resolvePath(["Travail"], origin: .ai)
        _ = try env.categories.resolvePath(["Automobile", "Corolla"], origin: .ai)
        _ = try env.categories.resolvePath(["Finance"], origin: .ai)
        #expect(try env.categories.categoryPaths() == ["Automobile", "Automobile › Corolla", "Finance", "Travail"])
    }

    @Test func archivesOnlyUnusedSeeds() throws {
        let env = try StoreTestEnvironment()
        try env.categories.seedDefaultsIfNeeded()
        let memory = try env.saveNote("Préparer la réunion")
        let travail = try #require(try env.categories.activeCategories().first { $0.name == "Travail" })
        _ = try env.categories.assign(memoryID: memory.id, categoryID: travail.id, origin: .user)
        _ = try env.categories.resolvePath(["Automobile"], origin: .ai)
        #expect(try env.categories.archiveUnusedSeeds() == 8)
        #expect(try env.categories.activeCategories().map(\.name) == ["Automobile", "Travail"])
        #expect(try env.categories.archiveUnusedSeeds() == 0)
    }
}
