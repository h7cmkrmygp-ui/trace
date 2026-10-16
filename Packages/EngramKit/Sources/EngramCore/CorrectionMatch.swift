import Foundation

/// F21 — deux notes parlent-elles de la même chose, une fois retirés les mots d'une correction, les dates et les nombres
/// (ce qui change justement) ?
public enum CorrectionMatch {
    static let threshold = 0.5
    static let ignored: Set<String> = [
        "finalement", "correction", "corrige", "corriger", "plutot", "fait", "change", "changement", "deplace", "deplacer",
        "reporte", "reporter", "remplace", "maintenant", "nouveau", "nouvelle", "actually", "instead", "lundi", "mardi",
        "mercredi", "jeudi", "vendredi", "samedi", "dimanche", "janvier", "fevrier", "mars", "avril", "mai", "juin",
        "juillet", "aout", "septembre", "octobre", "novembre", "decembre", "demain", "aujourd", "hier", "matin", "soir",
        "semaine", "prochain", "prochaine", "heure", "heures", "minute", "minutes",
    ]

    public static func words(_ text: String) -> Set<String> {
        Set(AnalysisValidator.meaningfulWords(text).map(TextNormalizer.singularize)
            .filter { !ignored.contains($0) && !$0.allSatisfy(\.isNumber) })
    }

    public static func same(_ new: Set<String>, _ old: Set<String>) -> Bool {
        guard !new.isEmpty, !old.isEmpty else { return false }
        return Double(new.intersection(old).count) / Double(new.union(old).count) >= threshold
    }
}
