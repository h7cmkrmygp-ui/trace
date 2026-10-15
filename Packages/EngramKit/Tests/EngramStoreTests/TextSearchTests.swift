import EngramCore
import Foundation
import Testing
@testable import EngramStore

struct TextSearchTests {
    @Test func ignoresAccentsAndCase() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Réunion budget avec l'équipe")
        #expect(try env.memories.searchText("REUNION").map(\.memoryID) == [memory.id])
        #expect(try env.memories.searchText("equipe").map(\.memoryID) == [memory.id])
    }

    @Test func matchesWordPrefixes() throws {
        let env = try StoreTestEnvironment()
        let memory = try env.saveNote("Préparer le budget trimestriel")
        #expect(try env.memories.searchText("budg trim").map(\.memoryID) == [memory.id])
    }

    @Test func requiresEveryWord() throws {
        let env = try StoreTestEnvironment()
        try env.saveNote("Acheter du lait")
        try env.saveNote("Acheter un ordinateur")
        #expect(try env.memories.searchText("acheter lait").count == 1)
    }

    @Test(arguments: ["\"", "*", "-lait", "(lait", "lait:", "AND", "NEAR(lait)", "lait OR", "\"lait", "^lait"])
    func specialCharactersNeverThrow(query: String) throws {
        let env = try StoreTestEnvironment()
        try env.saveNote("Acheter du lait")
        _ = try env.memories.searchText(query)
    }

    @Test(arguments: ["", "   ", "!!!", "--"])
    func punctuationOnlyFindsNothing(query: String) throws {
        let env = try StoreTestEnvironment()
        try env.saveNote("Acheter du lait")
        #expect(try env.memories.searchText(query).isEmpty)
    }

    @Test func singleLettersAreIgnoredWhenOtherWordsExist() {
        #expect(FTSQuery.make(from: "l'été") == "\"été\"*")
        #expect(FTSQuery.make(from: "a") == "\"a\"*")
        #expect(FTSQuery.make(from: "?!") == nil)
    }

    @Test func excludesTrashAndOptionallyIncludesArchives() throws {
        let env = try StoreTestEnvironment()
        let trashed = try env.saveNote("Lait à jeter")
        let archived = try env.saveNote("Lait archivé")
        _ = try env.memories.setStatus(.trashed, for: trashed.id, actor: .user)
        _ = try env.memories.setStatus(.archived, for: archived.id, actor: .user)
        #expect(try env.memories.searchText("lait").isEmpty)
        #expect(try env.memories.searchText("lait", filters: SearchFilters(includeArchived: true)).map(\.memoryID) == [archived.id])
    }

    @Test func filtersByCategoryIncludingSubcategories() throws {
        let env = try StoreTestEnvironment()
        let sante = try env.categories.createCategory(name: "Santé", parentID: nil, origin: .seed).category
        let sport = try env.categories.createCategory(name: "Sport", parentID: sante.id, origin: .ai).category
        let inSport = try env.saveNote("Plan de course du mardi")
        let inSante = try env.saveNote("Course chez le pharmacien")
        try env.saveNote("Course de taxi")
        let rejected = try env.saveNote("Course annulée")
        _ = try env.categories.assign(memoryID: inSport.id, categoryID: sport.id, origin: .ai)
        _ = try env.categories.assign(memoryID: inSante.id, categoryID: sante.id, origin: .user)
        _ = try env.categories.assign(memoryID: rejected.id, categoryID: sante.id, origin: .ai)
        try env.categories.removeAssignment(memoryID: rejected.id, categoryID: sante.id, by: .user)
        let ids = Set(try env.memories.searchText("course", filters: SearchFilters(categoryID: sante.id)).map(\.memoryID))
        #expect(ids == [inSport.id, inSante.id])
    }

    @Test func filtersByTagKindAndDate() throws {
        let env = try StoreTestEnvironment()
        let early = try env.saveNote("Idée de jardin")
        env.dates.advance(by: 24 * 3600)
        let late = try env.saveNote("Idée de cuisine")
        let tag = try env.categories.upsertTag(name: "Idée", origin: .ai)
        _ = try env.categories.tag(memoryID: late.id, tagID: tag.id, origin: .ai)
        _ = try env.memories.updateMemory(early.id, with: MemoryEdit(kind: .idea), actor: .user)
        #expect(try env.memories.searchText("idee", filters: SearchFilters(tagID: tag.id)).map(\.memoryID) == [late.id])
        #expect(try env.memories.searchText("idee", filters: SearchFilters(kinds: [.idea])).map(\.memoryID) == [early.id])
        let from = Fixtures.date.addingTimeInterval(3600)
        #expect(try env.memories.searchText("idee", filters: SearchFilters(capturedFrom: from)).map(\.memoryID) == [late.id])
    }

    @Test func titleMatchesRankAboveContentMatches() throws {
        let env = try StoreTestEnvironment()
        let inContent = try env.saveNote("Notes diverses\nil faudra revoir le budget")
        let inTitle = try env.saveNote("Budget\nà revoir")
        #expect(try env.memories.searchText("budget").map(\.memoryID) == [inTitle.id, inContent.id])
    }
}
