import EngramTesting
import Foundation
import Testing
@testable import EngramCapture

struct WhisperModelStoreTests {
    /// Le chemin du modèle est gardé relatif : sur iOS, « /var/… » et « /private/var/… » désignent le même dossier,
    /// et le dossier de l'app peut changer de chemin absolu après une réinstallation.
    @Test func relativePathIgnoresSymlinkedPrefixes() throws {
        let temp = try TemporaryDirectory()
        let base = temp.url.appendingPathComponent("whisper", isDirectory: true)
        let folder = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/x", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(WhisperModelStore.relativePath(of: folder, in: base) == "models/argmaxinc/whisperkit-coreml/x")
        if folder.path.hasPrefix("/var/") {
            let viaPrivate = URL(fileURLWithPath: "/private" + folder.path, isDirectory: true)
            #expect(WhisperModelStore.relativePath(of: viaPrivate, in: base) == "models/argmaxinc/whisperkit-coreml/x")
        }
    }

    @Test func aModelIsDownloadedOnlyWhenItsFolderIsRecordedAndPresent() throws {
        let temp = try TemporaryDirectory()
        let store = WhisperModelStore(directory: temp.url)
        #expect(!store.isDownloaded(.largeV3Turbo))
        let folder = temp.url.appendingPathComponent("models/m", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "models/m".write(to: temp.url.appendingPathComponent("\(WhisperModel.largeV3Turbo.rawValue).folder"),
                             atomically: true, encoding: .utf8)
        #expect(store.isDownloaded(.largeV3Turbo))
        #expect(!store.isDownloaded(.largeV3))
        try store.delete(.largeV3Turbo)
        #expect(!store.isDownloaded(.largeV3Turbo))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
