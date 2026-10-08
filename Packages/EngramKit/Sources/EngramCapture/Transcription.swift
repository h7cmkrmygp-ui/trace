import Foundation

/// Résultat d'une transcription.
public struct Transcript: Sendable, Equatable {
    public let text: String
    /// Langue détectée ou utilisée (« fr-CA », « fr », « en », « fr+en »…).
    public let localeIdentifier: String

    public init(text: String, localeIdentifier: String) {
        self.text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        self.localeIdentifier = localeIdentifier
    }
}

public enum TranscriptionError: Error, Equatable, Sendable {
    /// Aucune des langues souhaitées n'est prise en charge sur cet appareil.
    case unsupportedLanguage
    /// Le modèle n'est pas (encore) sur l'iPhone ou ne peut pas être chargé.
    case modelUnavailable(String)
    /// Le fichier audio ne peut pas être lu.
    case unreadableAudio
}

/// Un moteur de transcription d'un fichier audio, **sur l'iPhone**.
public protocol AudioTranscriber: Sendable {
    /// Nom enregistré dans `source.transcription_engine`.
    var engineName: String { get }
    func transcribe(url: URL) async throws -> Transcript
}

/// Moteurs proposés dans les Réglages. Les deux fonctionnent sur l'iPhone, sans frais.
public enum TranscriptionEngine: String, CaseIterable, Identifiable, Sendable {
    /// Whisper (modèle libre d'OpenAI) exécuté sur l'iPhone par WhisperKit : bilingue, privé, hors ligne.
    case whisper
    /// La reconnaissance vocale d'Apple, sur l'iPhone (une seule langue à la fois).
    case apple

    public static let `default` = TranscriptionEngine.whisper

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .whisper: "Whisper (bilingue, sur l'iPhone)"
        case .apple: "Reconnaissance d'Apple"
        }
    }
}
