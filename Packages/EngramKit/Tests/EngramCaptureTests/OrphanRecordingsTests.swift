import EngramTesting
import Foundation
import Testing
@testable import EngramCapture

/// Important 7 — un enregistrement interrompu par la fermeture de l'app est retrouvé au lancement suivant.
struct OrphanRecordingsTests {
    @Test func findsOldUnreferencedRecordingsOnly() throws {
        let base = try TemporaryDirectory()
        let known = try AudioFiles.newRecording(in: base.url)
        let orphan = try AudioFiles.newRecording(in: base.url)
        let fresh = try AudioFiles.newRecording(in: base.url)
        for recording in [known, orphan, fresh] { try Data("x".utf8).write(to: recording.url) }
        let old = Date().addingTimeInterval(-3600)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: known.url.path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: orphan.url.path)
        let found = try AudioFiles.orphanedRecordings(in: base.url, referenced: [known.relativePath],
                                                      olderThan: Date().addingTimeInterval(-600))
        #expect(found == [orphan.relativePath])
    }
}
