import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

struct ExporterTests {
    @Test func exportsJSONMarkdownAndArchive() throws {
        let env = try StoreTestEnvironment()
        let classed = try env.saveNote("Préparer la réunion budget\nAvec les chiffres de mars")
        let trashed = try env.saveNote("Idée : une app de mémoire")
        _ = try env.memories.setStatus(.trashed, for: trashed.id, actor: .user)
        let travail = try env.categories.createCategory(name: "Travail", parentID: nil, origin: .user).category
        _ = try env.categories.assign(memoryID: classed.id, categoryID: travail.id, origin: .user)

        let out = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: out.url)
        #expect(result.memoryCount == 2)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: result.folderURL.appendingPathComponent("engram.json"))
        let document = try decoder.decode(ExportDocument.self, from: data)
        #expect(document.formatVersion == EngramCore.exportFormatVersion)
        #expect(Set(document.memories.map(\.id)) == [classed.id, trashed.id])
        #expect(document.categoryAssignments.count == 1)
        #expect(document.memoryVersions.count == 3)

        let markdown = result.folderURL.appendingPathComponent("markdown")
        #expect(try FileManager.default.contentsOfDirectory(atPath: markdown.appendingPathComponent("Travail").path).count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: markdown.appendingPathComponent("Corbeille").path).count == 1)
        #expect(FileManager.default.fileExists(atPath: result.folderURL.appendingPathComponent("LISEZMOI.txt").path))

        let archive = try Data(contentsOf: result.archiveURL)
        #expect(archive.prefix(2) == Data("PK".utf8))
    }

    @Test func copiesAudioFilesWhenPresent() throws {
        let env = try StoreTestEnvironment()
        let audio = try TemporaryDirectory()
        try Data("audio-de-test".utf8).write(to: audio.url.appendingPathComponent("capture-1.caf"))
        try env.database.writer.write { db in
            try Source(kind: .voice, audioPath: "capture-1.caf", contentHash: "h", capturedAt: Fixtures.date,
                       createdAt: Fixtures.date, updatedAt: Fixtures.date).insert(db)
        }
        let out = try TemporaryDirectory()
        let result = try Exporter(database: env.database, audioDirectory: audio.url, dates: env.dates).export(into: out.url)
        #expect(FileManager.default.fileExists(atPath: result.folderURL.appendingPathComponent("audio/capture-1.caf").path))
    }

    @Test func unsafeTitlesBecomeSafeFileNamesAndQuotedFrontMatter() throws {
        let env = try StoreTestEnvironment()
        try env.saveNote("Achats/Ventes : \"Q3\" <final>?")
        let out = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: out.url)
        let unsorted = result.folderURL.appendingPathComponent("markdown").appendingPathComponent("À classer")
        let files = try FileManager.default.contentsOfDirectory(atPath: unsorted.path)
        let name = try #require(files.first)
        #expect(files.count == 1)
        for forbidden in ["/", "\"", "<", ">", "?", ":"] { #expect(!name.contains(forbidden)) }
        let text = try String(contentsOf: unsorted.appendingPathComponent(name), encoding: .utf8)
        #expect(text.contains("titre: \"Achats/Ventes : \\\"Q3\\\" <final>?\""))
    }

    @Test func exportingTwiceReplacesThePreviousArchive() throws {
        let env = try StoreTestEnvironment()
        try env.saveNote("Une pensée")
        let out = try TemporaryDirectory()
        let exporter = Exporter(database: env.database, dates: env.dates)
        let first = try exporter.export(into: out.url)
        let second = try exporter.export(into: out.url)
        #expect(first.archiveURL == second.archiveURL)
        #expect(FileManager.default.fileExists(atPath: second.archiveURL.path))
    }
}
