import Foundation
import Testing
@testable import EngramCore

/// F19 — un partage n'est jamais perdu : la boîte est lue sans être vidée, chaque élément est acquitté seulement après son
/// enregistrement, un fichier illisible part en quarantaine avec son erreur, et un rejeu ne crée rien deux fois.
struct SharedImportTests {
    func inbox() throws -> SharedInbox {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)")
        return SharedInbox(directory: directory)
    }

    func item(_ text: String, at seconds: Double) -> SharedItem {
        SharedItem(text: text, link: nil, createdAt: Date(timeIntervalSince1970: 1_800_000_000 + seconds))
    }

    @Test func readingTheInboxRemovesNothing() throws {
        let box = try inbox()
        try box.add(item("Premier", at: 1))
        try box.add(item("Deuxième", at: 2))
        #expect(box.pending().items.map(\.item.text) == ["Premier", "Deuxième"])
        // Relue : toujours là, avec les mêmes identifiants.
        let again = box.pending().items
        #expect(again.map(\.item.text) == ["Premier", "Deuxième"])
        #expect(again.map(\.id) == box.pending().items.map(\.id))
        try box.acknowledge(again[0].id)
        #expect(box.pending().items.map(\.item.text) == ["Deuxième"])
    }

    @Test func anUnreadableFileGoesToQuarantineWithItsError() throws {
        let box = try inbox()
        try box.add(item("Lisible", at: 1))
        try Data("{ pas du json".utf8).write(to: box.directory.appendingPathComponent("0000-casse.json"))
        let reading = box.pending()
        #expect(reading.items.map(\.item.text) == ["Lisible"])
        #expect(reading.quarantined == ["0000-casse"])
        let kept = try FileManager.default.contentsOfDirectory(atPath: box.quarantineDirectory.path)
        #expect(kept.contains("0000-casse.json"))
        #expect(kept.contains { $0.hasPrefix("0000-casse") && $0.hasSuffix(".erreur.txt") })
    }

    @Test func aStorageFailureLosesNothingAndAReplayDuplicatesNothing() throws {
        let box = try inbox()
        try box.add(item("Un", at: 1))
        try box.add(item("Deux", at: 2))
        try box.add(item("Trois", at: 3))
        var stored: [String: String] = [:]
        // Le stockage refuse le deuxième élément : le premier et le troisième sont enregistrés, le deuxième reste.
        let first = SharedImporter.run(box) { share in
            if share.item.text == "Deux" { throw CocoaError(.fileWriteOutOfSpace) }
            if stored[share.id] != nil { return .duplicate }
            stored[share.id] = share.item.text
            return .saved
        }
        #expect(first.saved.count == 2)
        #expect(first.failed.count == 1)
        #expect(box.pending().items.map(\.item.text) == ["Deux"])
        // Arrêt de l'app juste après l'enregistrement, avant l'acquittement : le rejeu ne recrée rien.
        let id = try #require(box.pending().items.first?.id)
        stored[id] = "Deux"
        let replay = SharedImporter.run(box) { share in stored[share.id] != nil ? .duplicate : .saved }
        #expect(replay.duplicates == [id])
        #expect(replay.saved.isEmpty)
        #expect(box.pending().items.isEmpty)
        #expect(Set(stored.values) == ["Un", "Deux", "Trois"])
    }
}
