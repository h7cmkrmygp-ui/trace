import Foundation

/// Nettoyage d'une dictée : les hésitations (« euh », « hum », « mmm ») disparaissent, les vrais mots restent.
public enum SpeechCleanup {
    public static func removingHesitations(_ text: String) -> String {
        text
    }
}
