import EngramCore
import EngramTesting
import Foundation
@testable import EngramStore

/// Base en mémoire + services, avec une horloge contrôlable.
struct StoreTestEnvironment {
    let database: AppDatabase
    let dates: TestDateProvider
    let memories: MemoryStore

    init() throws {
        database = try AppDatabase.inMemory()
        dates = TestDateProvider(Fixtures.date)
        memories = MemoryStore(database: database, dates: dates)
    }

    @discardableResult
    func saveNote(_ text: String) throws -> Memory {
        guard case .saved(let memory) = try memories.saveTextNoteWithoutAnalysis(text) else {
            throw StoreTestFailure.unexpectedDuplicate
        }
        return memory
    }
}

enum StoreTestFailure: Error { case unexpectedDuplicate }
