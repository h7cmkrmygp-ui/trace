import Foundation

/// P31 — ce qu'Engram reconnaît déjà dans une note, sur l'iPhone et sans IA (une fête, une mesure, un ajout à une liste),
/// dit à l'IA avec la note pour qu'elle la classe d'après son vrai sujet.
public enum NoteFacts {
    static let measurements: [Metric: String] = [
        .weight: "une mesure de poids", .sleep: "une durée de sommeil", .bloodPressure: "une mesure de tension artérielle",
        .heartRate: "une mesure du pouls", .steps: "un nombre de pas", .glucose: "une mesure de glycémie",
    ]

    public static func describe(_ text: String) -> [String] {
        var facts: [String] = []
        if let birthday = BirthdayParser.parse(text) {
            let day = birthday.day == 1 ? "1er" : "\(birthday.day)"
            facts.append("\(BirthdayPlanner.feast(birthday.person)), le \(day) \(WeeklyReviewText.months[birthday.month - 1])"
                + " (une date pour une personne, pas une mesure de santé)")
        }
        for measurement in MeasurementParser.parse(text) {
            if let fact = measurements[measurement.metric], !facts.contains(fact) { facts.append(fact) }
        }
        if let command = ListCommandParser.parse(text) {
            let first = MeasurementParser.normalized(String(command.listName.prefix(1)))
            let of = !first.isEmpty && "aeiouyh".contains(first) ? "d'" : "de "
            facts.append("un ajout à la liste \(of)\(command.listName)")
        }
        return facts
    }
}
