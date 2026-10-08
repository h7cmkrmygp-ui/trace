import EngramCore
import EngramTesting
import Foundation
import Testing
@testable import EngramStore

/// Copie de secours quand la base ne s'ouvre plus (spec §5.2 et §10).
struct DatabaseRecoveryTests {
    @Test func archivesTheRawDatabaseFilesWithoutOpeningThem() throws {
        let storage = try TemporaryDirectory()
        for name in ["engram.sqlite", "engram.sqlite-wal", "engram.sqlite-shm", "autre.txt"] {
            try Data("contenu fictif".utf8).write(to: storage.url.appendingPathComponent(name))
        }
        let out = try TemporaryDirectory()
        let archive = try DatabaseRecovery.archiveRawFiles(from: storage.url, into: out.url, at: Fixtures.date)
        #expect(archive.fileNames == ["engram.sqlite", "engram.sqlite-shm", "engram.sqlite-wal"])
        #expect(archive.archiveURL.pathExtension == "zip")
        #expect(try Data(contentsOf: archive.archiveURL).prefix(2) == Data("PK".utf8))
    }

    @Test func refusesWhenThereIsNoDatabaseFile() throws {
        let storage = try TemporaryDirectory()
        let out = try TemporaryDirectory()
        #expect(throws: StoreError.notFound) {
            try DatabaseRecovery.archiveRawFiles(from: storage.url, into: out.url, at: Fixtures.date)
        }
    }
}
