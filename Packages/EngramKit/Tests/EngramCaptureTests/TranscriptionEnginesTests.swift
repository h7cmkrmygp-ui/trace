import Foundation
import Testing
@testable import EngramCapture

struct TranscriptionEnginesTests {
    @Test func enginesHaveStableIdentifiersAndWhisperIsTheDefault() {
        #expect(TranscriptionEngine.default == .whisper)
        #expect(TranscriptionEngine(rawValue: "whisper") == .whisper)
        #expect(TranscriptionEngine(rawValue: "openai") == .openAI)
        #expect(TranscriptionEngine(rawValue: "apple") == .apple)
        #expect(TranscriptionEngine.allCases.allSatisfy { !$0.label.isEmpty })
    }

    @Test func multipartBodyContainsFieldsAndFile() throws {
        var form = MultipartFormData(boundary: "LIMITE")
        form.addField(name: "model", value: "gpt-4o-transcribe")
        form.addFile(name: "file", fileName: "note.wav", mimeType: "audio/wav", data: Data("RIFF".utf8))
        let body = try #require(String(data: form.body, encoding: .utf8))
        #expect(form.contentType == "multipart/form-data; boundary=LIMITE")
        #expect(body.contains("--LIMITE\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\ngpt-4o-transcribe\r\n"))
        #expect(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"note.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF\r\n"))
        #expect(body.hasSuffix("--LIMITE--\r\n"))
    }

    @Test func parsesASuccessfulOpenAIResponse() throws {
        let data = Data(#"{"text": "  Appeler le garage   demain  "}"#.utf8)
        let transcript = try OpenAITranscriber.parse(data: data, status: 200)
        #expect(transcript.text == "Appeler le garage demain")
    }

    @Test func reportsAnInvalidKeyAndServiceErrors() {
        let unauthorized = Data(#"{"error": {"message": "Incorrect API key provided"}}"#.utf8)
        #expect(throws: TranscriptionError.invalidAPIKey) { try OpenAITranscriber.parse(data: unauthorized, status: 401) }
        let overloaded = Data(#"{"error": {"message": "Server overloaded"}}"#.utf8)
        #expect(throws: TranscriptionError.service("Server overloaded")) { try OpenAITranscriber.parse(data: overloaded, status: 503) }
    }
}
