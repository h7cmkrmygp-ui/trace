import EngramCore
import EngramTesting
import Foundation
@testable import EngramStore

/// Base en mémoire + services, avec une horloge contrôlable.
struct StoreTestEnvironment {
    let database: AppDatabase
    let dates: TestDateProvider
    let memories: MemoryStore
    let categories: CategoryStore
    let filer: ThoughtFiler

    init() throws {
        database = try AppDatabase.inMemory()
        dates = TestDateProvider(Fixtures.date)
        memories = MemoryStore(database: database, dates: dates)
        categories = CategoryStore(database: database, dates: dates)
        filer = ThoughtFiler(database: database, dates: dates)
    }

    @discardableResult
    func saveNote(_ text: String) throws -> Memory {
        guard case .saved(let memory) = try memories.saveTextNoteWithoutAnalysis(text) else {
            throw StoreTestFailure.unexpectedDuplicate
        }
        return memory
    }

    func status(of memory: Memory) throws -> MemoryStatus? {
        try memories.memory(id: memory.id)?.status
    }
}

enum StoreTestFailure: Error { case unexpectedDuplicate }
