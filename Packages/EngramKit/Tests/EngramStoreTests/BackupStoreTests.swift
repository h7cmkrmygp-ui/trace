import EngramCore
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// Sauvegarde et restauration de la base : copie cohérente, et rien de perdu en restaurant.
struct BackupStoreTests {
    func folder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aCopyOfTheDatabaseOpensWithTheSameNotes() throws {
        let directory = try folder("base")
        let database = try AppDatabase(DatabasePool(path: directory.appendingPathComponent("engram.sqlite").path,
                                                    configuration: AppDatabase.makeConfiguration()))
        _ = try MemoryStore(database: database).saveTextNoteWithoutAnalysis("Note inventée à sauvegarder")
        let copy = directory.appendingPathComponent("copie.sqlite")
        try database.backup(to: copy)
        let reopened = try AppDatabase(DatabaseQueue(path: copy.path, configuration: AppDatabase.makeConfiguration()))
        #expect(try reopened.writer.read { try Memory.fetchCount($0) } == 1)

        // Une sauvegarde ouverte est vérifiée avant d'être préparée : sa base s'ouvre et compte ses notes.
        let restored = try folder("ouverte")
        try database.backup(to: restored.appendingPathComponent("engram.sqlite"))
        #expect(try BackupRestore.noteCount(inRestored: restored) == 1)
        let broken = try folder("abimee")
        try Data("pas une base".utf8).write(to: broken.appendingPathComponent("engram.sqlite"))
        #expect(throws: (any Error).self) { try BackupRestore.noteCount(inRestored: broken) }
    }

    @Test func aRestoreKeepsTheCurrentDataAside() throws {
        let storage = try folder("engram")
        try Data("actuelle".utf8).write(to: storage.appendingPathComponent("engram.sqlite"))
        try FileManager.default.createDirectory(at: storage.appendingPathComponent("audio"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: storage.appendingPathComponent("audio/x.caf"))

        let restored = try folder("restauree")
        try Data("restauree".utf8).write(to: restored.appendingPathComponent("engram.sqlite"))
        try FileManager.default.createDirectory(at: restored.appendingPathComponent("audio"), withIntermediateDirectories: true)
        try Data("y".utf8).write(to: restored.appendingPathComponent("audio/y.caf"))

        try BackupRestore.stage(restored, in: storage)
        #expect(BackupRestore.hasPending(in: storage))
        let aside = try #require(try BackupRestore.applyPending(in: storage, at: Date(timeIntervalSince1970: 0)))

        #expect(try String(contentsOf: storage.appendingPathComponent("engram.sqlite"), encoding: .utf8) == "restauree")
        #expect(FileManager.default.fileExists(atPath: storage.appendingPathComponent("audio/y.caf").path))
        #expect(!FileManager.default.fileExists(atPath: storage.appendingPathComponent("audio/x.caf").path))
        // Les anciennes données sont gardées à part, jamais effacées.
        #expect(try String(contentsOf: aside.appendingPathComponent("engram.sqlite"), encoding: .utf8) == "actuelle")
        #expect(FileManager.default.fileExists(atPath: aside.appendingPathComponent("audio/x.caf").path))
        #expect(!BackupRestore.hasPending(in: storage))
        // Sans restauration en attente, rien ne bouge.
        #expect(try BackupRestore.applyPending(in: storage, at: Date()) == nil)
    }
}
