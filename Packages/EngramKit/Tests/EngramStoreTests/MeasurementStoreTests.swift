import EngramCore
import EngramTesting
import Foundation
import GRDB
import Testing
@testable import EngramStore

/// P10 — les mesures des notes deviennent des suivis : relevées au classement et au lancement, jamais à la corbeille.
struct MeasurementStoreTests {
    func store(_ env: StoreTestEnvironment) -> MeasurementStore {
        MeasurementStore(database: env.database, dates: env.dates, calendar: Fixtures.calendar)
    }

    @discardableResult
    func file(_ env: StoreTestEnvironment, _ text: String) throws -> Memory {
        let interim = try env.saveNote(text)
        let thought = ValidThought(title: text, summary: nil, excerpt: text, spanStart: nil, spanEnd: nil, kind: .info,
                                   tags: [], categoryPath: ["Santé"], mentionedDates: [])
        return try #require(try env.filer.file([thought], sourceID: interim.sourceID).memories.first)
    }

    @Test func theMigrationCreatesTheTable() throws {
        let env = try StoreTestEnvironment()
        #expect(try env.database.writer.read { db in try db.tableExists("measurement") })
    }

    @Test func filingANoteRecordsItsMeasurements() throws {
        let env = try StoreTestEnvironment()
        let memory = try file(env, "Je pèse 162,5 livres aujourd'hui")
        let found = try store(env).measurements(for: memory.id)
        #expect(found.count == 1)
        #expect(found.first?.metric == .weight && found.first?.value == 162.5 && found.first?.unit == "lb")
        #expect(found.first?.measuredAt == memory.capturedAt)
    }

    @Test func yesterdayMovesTheMeasurementBackADay() throws {
        let env = try StoreTestEnvironment()
        let memory = try file(env, "J'ai dormi 7 h 30 hier")
        let measured = try #require(try store(env).measurements(for: memory.id).first?.measuredAt)
        #expect(Fixtures.calendar.dateComponents([.day], from: measured, to: memory.capturedAt).day == 1)
    }

    @Test func pointsAreConvertedAndLeaveOutTrashedNotes() throws {
        let env = try StoreTestEnvironment()
        try file(env, "Je pèse 165 livres")
        env.dates.advance(by: 86_400)
        let kilos = try file(env, "Poids : 74 kg")
        env.dates.advance(by: 86_400)
        let trashed = try file(env, "Je pèse 170 livres")
        _ = try env.memories.setStatus(.trashed, for: trashed.id, actor: .user)
        let points = try store(env).points(metric: .weight, weightUnit: "lb")
        #expect(points.count == 2)
        #expect(abs(points[1].value - MetricUnits.pounds(fromKilograms: 74)) < 1e-9)
        #expect(try store(env).points(metric: .weight, weightUnit: "kg").first.map { abs($0.value - MetricUnits.kilograms(fromPounds: 165)) < 1e-9 } == true)
        #expect(try store(env).metricsWithData() == [.weight])
        let entries = try store(env).entries(metric: .weight, weightUnit: "lb")
        #expect(entries.first?.memoryID == kilos.id)
        // Supprimée pour de bon : ses mesures disparaissent.
        _ = try env.memories.setStatus(.trashed, for: kilos.id, actor: .user)
        _ = try env.memories.deletePermanently(kilos.id)
        #expect(try store(env).measurements(for: kilos.id).isEmpty)
        #expect(try store(env).points(metric: .weight, weightUnit: "lb").count == 1)
    }

    @Test func oldAndEditedNotesAreReadAgainAtLaunch() throws {
        let env = try StoreTestEnvironment()
        let old = try env.saveNote("Ce matin : pouls 62")
        #expect(try store(env).backfill() == 1)
        #expect(try store(env).measurements(for: old.id).map(\.value) == [62])
        #expect(try store(env).backfill() == 0)
        env.dates.advance(by: 60)
        _ = try env.memories.updateMemory(old.id, with: MemoryEdit(content: "Ce matin : pouls 58"), actor: .user)
        #expect(try store(env).backfill() == 1)
        #expect(try store(env).measurements(for: old.id).map(\.value) == [58])
    }

    /// Au retour dans l'app, seules les notes nouvelles ou modifiées depuis la dernière relecture sont relues
    /// (l'app reste rapide avec des centaines de notes).
    @Test func onlyNotesChangedSinceTheLastReadAreReadAgain() throws {
        let env = try StoreTestEnvironment()
        let note = try env.saveNote("Ce matin : pouls 62")
        let before = env.dates.now().addingTimeInterval(-1)
        let after = env.dates.now().addingTimeInterval(1)
        #expect(try store(env).backfill(since: after) == 0)
        #expect(try store(env).measurements(for: note.id).isEmpty)
        #expect(try store(env).backfill(since: before) == 1)
        #expect(try store(env).measurements(for: note.id).map(\.value) == [62])
    }

    @Test func theExportContainsTheMeasurements() throws {
        let env = try StoreTestEnvironment()
        try file(env, "Tension 120 sur 80")
        let directory = try TemporaryDirectory()
        let result = try Exporter(database: env.database, dates: env.dates).export(into: directory.url)
        let json = try String(contentsOf: result.folderURL.appendingPathComponent("engram.json"), encoding: .utf8)
        #expect(json.contains("\"measurements\""))
        #expect(json.contains("blood_pressure"))
    }
}
