import EngramTesting
import Foundation
import Testing
@testable import EngramCapture

struct AudioFilesTests {
    @Test func newRecordingIsARelativeCAFPathInsideTheAudioFolder() throws {
        let base = try TemporaryDirectory()
        let recording = try AudioFiles.newRecording(in: base.url)
        #expect(recording.relativePath.hasPrefix("audio/"))
        #expect(recording.relativePath.hasSuffix(".caf"))
        #expect(recording.url == base.url.appendingPathComponent(recording.relativePath))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: base.url.appendingPathComponent("audio").path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func twoRecordingsNeverShareAPath() throws {
        let base = try TemporaryDirectory()
        #expect(try AudioFiles.newRecording(in: base.url).relativePath != AudioFiles.newRecording(in: base.url).relativePath)
    }
}
