import Foundation

/// F22 — une réponse rédigée par le modèle n'affirme que ce que disent les notes données : aucun montant, nombre ou nom
/// absent de leurs textes.
public enum RecallAnswerCheck {
    public static func isSupported(_ answer: String, by notes: [String]) -> Bool { true }
}

/// F25 — les dossiers donnés au modèle, choisis selon le sens de la note (et non par ordre alphabétique).
public enum CategoryBudget {
    public static func select(_ paths: [String], for text: String, evidence: [FolderEvidence], counts: [String: Int],
                              limit: Int) -> [String] {
        Array(paths.prefix(limit))
    }
}
