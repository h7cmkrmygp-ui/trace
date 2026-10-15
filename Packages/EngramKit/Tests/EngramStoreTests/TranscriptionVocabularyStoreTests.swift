import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P37 — les noms donnés à la transcription : les personnes et les lieux les plus souvent cités, puis les dossiers.
struct TranscriptionVocabularyStoreTests {
    func file(_ env: StoreTestEnvironment, _ text: String, path: [String], people: [String] = [], places: [String] = []) throws {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .task, tags: [],
                                   categoryPath: path, mentionedDates: [], people: people, places: places)
        _ = try env.filer.file([thought], sourceID: interim.sourceID)
    }

    @Test func theMostCitedNamesComeFirstThenTheFolders() throws {
        let env = try StoreTestEnvironment()
        try file(env, "Appeler Julie", path: ["Famille"], people: ["Julie"])
        try file(env, "Souper avec Julie au Costco", path: ["Famille"], people: ["Julie"], places: ["Costco"])
        try file(env, "Voir Marc", path: ["Travail"], people: ["Marc"])
        let names = try EntityStore(database: env.database, dates: env.dates).transcriptionVocabulary()
        #expect(Array(names.prefix(3)) == ["Julie", "Costco", "Marc"])
        #expect(names.contains("Famille") && names.contains("Travail"))
        #expect(try EntityStore(database: env.database, dates: env.dates).transcriptionVocabulary(limit: 2) == ["Julie", "Costco"])
    }

    @Test func aHiddenNameIsNotGiven() throws {
        let env = try StoreTestEnvironment()
        try file(env, "Voir Marc", path: ["Travail"], people: ["Marc"])
        let people = EntityStore(database: env.database, dates: env.dates)
        let marc = try #require(try people.allEntities(kind: .person).first)
        try people.hide(marc.id)
        #expect(try !people.transcriptionVocabulary().contains("Marc"))
    }
}
