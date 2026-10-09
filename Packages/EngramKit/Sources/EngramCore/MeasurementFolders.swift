import Foundation

/// P31 — un dossier de suivi (« Poids », « Sommeil »…) ne reçoit que sa mesure, ou une note qui en parle (« prendre
/// rendez-vous pour mon poids »). « L'anniversaire d'Amina » n'y va jamais.
public enum MeasurementFolders {
    /// Noms de dossiers qui suivent une mesure (sans accents ni majuscules).
    static let folders: [Metric: Set<String>] = [
        .weight: ["poids", "pesee", "pesees", "weight", "perte de poids", "prise de poids"],
        .sleep: ["sommeil", "sleep"],
        .bloodPressure: ["tension", "tension arterielle", "pression arterielle", "blood pressure"],
        .heartRate: ["pouls", "frequence cardiaque", "rythme cardiaque", "heart rate"],
        .steps: ["pas", "nombre de pas", "steps", "podometre"],
        .glucose: ["glycemie", "glucose", "taux de sucre", "blood sugar"],
    ]
    /// Débuts de mots qui montrent qu'une note parle bien de cette mesure, même sans chiffre.
    static let words: [Metric: [String]] = [
        .weight: ["poids", "pese", "peser", "pesee", "kg", "kilo", "livre", "lb", "maigri", "grossi", "balance", "weigh"],
        .sleep: ["sommeil", "dormi", "dormir", "dors", "nuit", "sieste", "insomnie", "sleep", "slept"],
        .bloodPressure: ["tension", "pression", "arteriel", "blood"],
        .heartRate: ["pouls", "cardiaque", "battement", "bpm", "heart"],
        .steps: ["pas", "marche", "steps", "podometre"],
        .glucose: ["glycemie", "glucose", "sucre", "diabete", "insuline"],
    ]

    /// La mesure que suit un dossier ; nil pour un dossier ordinaire.
    public static func metric(forFolder name: String) -> Metric? {
        var key = MeasurementParser.normalized(name).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for prefix in ["suivi du ", "suivi de la ", "suivi des ", "suivi de ", "suivi d'", "mon ", "ma ", "mes "]
        where key.hasPrefix(prefix) {
            key.removeFirst(prefix.count)
            break
        }
        return Metric.allCases.first { folders[$0]?.contains(key) == true }
    }

    /// Vrai si la note peut aller dans ce dossier : un dossier ordinaire accepte tout.
    public static func belongs(_ text: String, in folder: String) -> Bool {
        guard let metric = metric(forFolder: folder) else { return true }
        if MeasurementParser.parse(text).contains(where: { $0.metric == metric }) { return true }
        let tokens = MeasurementParser.normalized(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return (words[metric] ?? []).contains { word in tokens.contains { $0.hasPrefix(word) } }
    }

    /// Vrai si aucun dossier du chemin ne la refuse.
    public static func accepts(_ path: [String], text: String) -> Bool {
        path.allSatisfy { belongs(text, in: $0) }
    }
}
