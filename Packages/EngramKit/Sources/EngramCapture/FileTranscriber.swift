import AVFAudio
import Foundation
import Speech

public struct Transcript: Sendable, Equatable {
    public let text: String
    public let localeIdentifier: String
}

public enum TranscriptionError: Error, Equatable, Sendable {
    /// Aucune des langues souhaitées n'est prise en charge sur cet appareil.
    case unsupportedLanguage
}

/// Transcrit un fichier audio **sur l'appareil** avec SpeechAnalyzer et SpeechTranscriber.
/// Les ressources de la langue sont téléchargées par iOS au premier usage.
public struct FileTranscriber: Sendable {
    public static let engineName = "apple-speech"

    /// Par ordre de préférence : français canadien, français de France, langue de l'appareil.
    public let preferredLocales: [Locale]

    public init(preferredLocales: [Locale] = [Locale(identifier: "fr-CA"), Locale(identifier: "fr-FR"), Locale.current]) {
        self.preferredLocales = preferredLocales
    }

    public func transcribe(url: URL) async throws -> Transcript {
        guard let locale = await resolveLocale() else { throw TranscriptionError.unsupportedLanguage }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        let collector = Task { () throws -> String in
            var pieces: [String] = []
            for try await result in transcriber.results where result.isFinal {
                pieces.append(String(result.text.characters))
            }
            return pieces.joined(separator: " ")
        }
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        let raw = try await collector.value
        let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return Transcript(text: text, localeIdentifier: locale.identifier)
    }

    func resolveLocale() async -> Locale? {
        for candidate in preferredLocales {
            if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) { return supported }
        }
        return nil
    }
}
