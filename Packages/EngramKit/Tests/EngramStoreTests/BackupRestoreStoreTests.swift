import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// F28 — une restauration vérifie sa sauvegarde sans rien fabriquer (base présente, manifeste et empreintes, contrôle
/// SQLite en lecture seule, audios référencés) et résiste à un arrêt après chaque déplacement grâce à un journal de
/// reprise. Une sauvegarde d'une version plus ancienne reste restaurable.
struct BackupRestoreStoreTests {
    static let database = DatabaseRecovery.databaseFileName

    /// Une base d'Engram avec une note (texte fictif), créée dans `folder`.
    func makeDatabase(in folder: URL, note: String, audioPath: String? = nil) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: folder.appendingPathComponent(Self.database).path,
                                      configuration: AppDatabase.makeConfiguration())
        let app = try AppDatabase(queue)
        let memories = MemoryStore(database: app, dates: TestDateProvider(Date(timeIntervalSince1970: 1_800_000_000)))
        if let audioPath {
            _ = try memories.saveVoiceNote(audioPath: audioPath, duration: 2, transcript: note, languages: [], engine: nil)
        } else {
            _ = try memories.saveTextNoteWithoutAnalysis(note)
        }
        try queue.close()
    }

    @Test func aBackupWithoutItsDatabaseIsRefusedAndNothingIsCreated() throws {
        let folder = try TemporaryDirectory()
        try Data("audio".utf8).write(to: folder.url.appendingPathComponent("note.caf"))
        #expect(throws: BackupRestore.Failure.missingDatabase) { try BackupRestore.validate(folder.url) }
        #expect(!FileManager.default.fileExists(atPath: folder.url.appendingPathComponent(Self.database).path))
    }

    @Test func aCorruptedBackupIsRefused() throws {
        let folder = try TemporaryDirectory()
        try makeDatabase(in: folder.url, note: "Une note fictive")
        try BackupManifest.write(in: folder.url, files: [Self.database], schemaVersion: "v24", createdAt: Date())
        // Le fichier change après le manifeste : son empreinte ne correspond plus.
        let handle = try FileHandle(forWritingTo: folder.url.appendingPathComponent(Self.database))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("modifié".utf8))
        try handle.close()
        #expect(throws: BackupRestore.Failure.self) { try BackupRestore.validate(folder.url) }
        // Un fichier qui n'est pas une base SQLite, même avec un manifeste juste.
        let garbage = try TemporaryDirectory()
        try Data(repeating: 7, count: 4_096).write(to: garbage.url.appendingPathComponent(Self.database))
        try BackupManifest.write(in: garbage.url, files: [Self.database], schemaVersion: "v24", createdAt: Date())
        #expect(throws: BackupRestore.Failure.self) { try BackupRestore.validate(garbage.url) }
    }

    @Test func aValidBackupGivesItsNotesAndItsMissingAudio() throws {
        let folder = try TemporaryDirectory()
        try makeDatabase(in: folder.url, note: "Une note vocale fictive", audioPath: "audio/absent.caf")
        try BackupManifest.write(in: folder.url, files: [Self.database], schemaVersion: "v24", createdAt: Date())
        let check = try BackupRestore.validate(folder.url)
        #expect(check.noteCount == 1)
        #expect(check.missingAudio == ["audio/absent.caf"])
        #expect(check.hasManifest)
    }

    @Test func anOlderBackupIsStillRestorable() throws {
        let folder = try TemporaryDirectory()
        let queue = try DatabaseQueue(path: folder.url.appendingPathComponent(Self.database).path)
        try Schema.migrator.migrate(queue, upTo: "v18_tidy_history")
        try queue.close()
        let check = try BackupRestore.validate(folder.url)
        #expect(check.noteCount == 0)
        #expect(!check.hasManifest)
    }

    @Test func aRestoreSurvivesAStopAfterEachStep() throws {
        for stop in 1...BackupRestore.stepCount {
            let storage = try TemporaryDirectory()
            try makeDatabase(in: storage.url, note: "Note actuelle fictive")
            try FileManager.default.createDirectory(at: storage.url.appendingPathComponent("audio"),
                                                    withIntermediateDirectories: true)
            try Data("ancien".utf8).write(to: storage.url.appendingPathComponent("audio/ancien.caf"))
            let restored = try TemporaryDirectory()
            let work = restored.url.appendingPathComponent("work")
            try makeDatabase(in: work, note: "Note restaurée fictive")
            try BackupRestore.stage(work, in: storage.url)
            #expect(throws: BackupRestore.Failure.interrupted) {
                _ = try BackupRestore.applyPending(in: storage.url, at: Date(), interruptAfter: stop)
            }
            #expect(BackupRestore.hasPending(in: storage.url), "étape \(stop)")
            let aside = try #require(try BackupRestore.applyPending(in: storage.url, at: Date()), "étape \(stop)")
            #expect(!BackupRestore.hasPending(in: storage.url))
            #expect(FileManager.default.fileExists(atPath: aside.appendingPathComponent(Self.database).path))
            #expect(FileManager.default.fileExists(atPath: aside.appendingPathComponent("audio/ancien.caf").path))
            let app = try AppDatabase(DatabaseQueue(path: storage.url.appendingPathComponent(Self.database).path,
                                                    configuration: AppDatabase.makeConfiguration()))
            let titles = try MemoryStore(database: app).memories(statuses: [.unsorted, .active]).map(\.content)
            #expect(titles == ["Note restaurée fictive"], "étape \(stop)")
        }
    }
}
