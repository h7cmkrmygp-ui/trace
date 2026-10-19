import Foundation

/// F22 — une réponse rédigée par le modèle n'affirme que ce que disent les notes données : aucun montant, nombre ou nom
/// absent de leurs textes (titres, dates et textes tels que donnés au modèle).
public enum RecallAnswerCheck {
    public static func isSupported(_ answer: String, by notes: [String]) -> Bool {
        AnalysisValidator.isGrounded(answer, in: notes.joined(separator: "\n"), dated: false)
    }
}

/// F25 — les dossiers donnés au modèle, choisis selon le sens de la note (et non par ordre alphabétique) : d'abord ceux
/// où sont rangées les notes semblables, puis ceux dont les mots sont dans la note, puis les plus grands, puis les autres.
public enum CategoryBudget {
    public static func select(_ paths: [String], for text: String, evidence: [FolderEvidence], counts: [String: Int],
                              limit: Int) -> [String] {
        let said = Set(AnalysisValidator.groundingWords(text))
        let evidenceRank = Dictionary(evidence.enumerated().map { ($0.element.path, $0.offset) },
                                      uniquingKeysWith: { first, _ in first })
        func shared(_ path: String) -> Int {
            Set(AnalysisValidator.groundingWords(path).filter { $0.count >= 3 }).intersection(said).count
        }
        let ranked = paths.enumerated().map { (offset: $0.offset, path: $0.element, evidence: evidenceRank[$0.element],
                                               shared: shared($0.element), count: counts[$0.element] ?? 0) }
            .sorted { first, second in
                switch (first.evidence, second.evidence) {
                case let (a?, b?): return a < b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil):
                    if first.shared != second.shared { return first.shared > second.shared }
                    if first.count != second.count { return first.count > second.count }
                    return first.offset < second.offset
                }
            }
        return ranked.prefix(limit).map(\.path)
    }
}
