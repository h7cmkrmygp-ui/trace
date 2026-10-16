import Foundation

/// F26 — quand une dictée doit passer par « Vérifie ta note » avant d'être classée.
public enum TranscriptReview {
    public static func needsReview(text: String, averageLogProbability: Double?, ownerWantsReview: Bool) -> Bool {
        ownerWantsReview
    }
}
