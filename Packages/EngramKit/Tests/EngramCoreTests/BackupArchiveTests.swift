import Foundation
import Testing
@testable import EngramCore

/// Sauvegarde chiffrée : on retrouve exactement ses fichiers avec le bon mot de passe, et rien sinon.
struct BackupArchiveTests {
    /// Peu de tours dans les tests (le vrai réglage est 600 000).
    static let iterations: UInt32 = 1_000

    func folder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Un dossier inventé : une « base » et deux enregistrements, dont un plus gros qu'un morceau de 1 Mo.
    func sampleSource() throws -> URL {
        let source = try folder("source")
        try Data("base de test".utf8).write(to: source.appendingPathComponent("engram.sqlite"))
        try FileManager.default.createDirectory(at: source.appendingPathComponent("audio"), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 2_500_000).write(to: source.appendingPathComponent("audio/a.caf"))
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("audio/b.caf"))
        return source
    }

    @Test func aBackupComesBackIdenticalWithTheRightPassword() throws {
        let source = try sampleSource()
        let archive = try folder("archive").appendingPathComponent("test.engrambackup")
        try BackupArchive.write(files: ["engram.sqlite", "audio/a.caf", "audio/b.caf"], from: source, to: archive,
                                password: "mot de passe inventé", iterations: Self.iterations)
        // Rien n'est lisible en clair dans le fichier.
        let raw = try Data(contentsOf: archive)
        #expect(raw.range(of: Data("base de test".utf8)) == nil)

        let restored = try folder("restored")
        let names = try BackupArchive.read(archive, password: "mot de passe inventé", into: restored)
        #expect(Set(names) == ["engram.sqlite", "audio/a.caf", "audio/b.caf"])
        for name in names {
            #expect(try Data(contentsOf: restored.appendingPathComponent(name)) == Data(contentsOf: source.appendingPathComponent(name)))
        }
    }

    @Test func theWrongPasswordOpensNothing() throws {
        let source = try sampleSource()
        let archive = try folder("archive").appendingPathComponent("test.engrambackup")
        try BackupArchive.write(files: ["engram.sqlite"], from: source, to: archive, password: "bon", iterations: Self.iterations)
        let restored = try folder("restored")
        #expect(throws: BackupArchive.Failure.wrongPasswordOrDamaged) {
            try BackupArchive.read(archive, password: "mauvais", into: restored)
        }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: restored.path))?.isEmpty ?? true)
    }

    @Test func aTruncatedOrModifiedFileIsRefused() throws {
        let source = try sampleSource()
        let archive = try folder("archive").appendingPathComponent("test.engrambackup")
        try BackupArchive.write(files: ["engram.sqlite", "audio/a.caf"], from: source, to: archive, password: "bon",
                                iterations: Self.iterations)
        let full = try Data(contentsOf: archive)

        let truncated = archive.deletingLastPathComponent().appendingPathComponent("coupe.engrambackup")
        try full.prefix(full.count - 40_000).write(to: truncated)
        #expect(throws: (any Error).self) { try BackupArchive.read(truncated, password: "bon", into: try folder("t")) }

        var bytes = [UInt8](full)
        bytes[bytes.count / 2] ^= 0xFF
        let modified = archive.deletingLastPathComponent().appendingPathComponent("modifie.engrambackup")
        try Data(bytes).write(to: modified)
        #expect(throws: (any Error).self) { try BackupArchive.read(modified, password: "bon", into: try folder("m")) }
    }

    @Test func aFileThatIsNotABackupIsRecognized() throws {
        let other = try folder("x").appendingPathComponent("photo.jpg")
        try Data("pas une sauvegarde".utf8).write(to: other)
        #expect(throws: BackupArchive.Failure.notABackup) { try BackupArchive.read(other, password: "bon", into: try folder("y")) }
    }

    @Test func pathsCannotEscapeTheRestoreFolder() {
        #expect(BackupArchive.isSafe("audio/a.caf"))
        #expect(!BackupArchive.isSafe("../engram.sqlite"))
        #expect(!BackupArchive.isSafe("/etc/passwd"))
        #expect(!BackupArchive.isSafe("audio/../../x"))
    }
}
