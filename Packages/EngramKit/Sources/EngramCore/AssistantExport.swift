import Foundation

/// Les notes trouvées, mises en texte pour un assistant (ChatGPT, Claude) quand le propriétaire le demande lui-même
/// dans un raccourci. Une note gardée sur l'iPhone ou jugée secrète n'y figure jamais.
public enum AssistantExport {
    public static func text(question: String, hits: [RecallHit], limit: Int = 5, calendar: Calendar, now: Date) -> String {
        let shared = hits.filter { !$0.document.isPrivate }
        let hidden = hits.count - shared.count
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        if shared.isEmpty {
            lines.append("Aucune note partageable ne correspond à « \(asked) » dans Engram.")
        } else {
            lines.append("Notes d'Engram pour : « \(asked) »")
            lines.append("")
            for (index, hit) in shared.prefix(limit).enumerated() {
                let document = hit.document
                let kind = document.kind.map(word(for:)) ?? "note"
                lines.append("\(index + 1). \(document.title) (\(kind), notée le \(day(document.capturedAt, calendar: calendar)))")
                let body = document.text.split(whereSeparator: \.isNewline).joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                if !body.isEmpty, body != document.title {
                    lines.append("   " + (body.count > 280 ? String(body.prefix(279)) + "…" : body))
                }
            }
        }
        if hidden > 0 {
            lines.append("")
            lines.append(hidden == 1 ? "1 note gardée sur l'iPhone n'est pas incluse."
                                     : "\(hidden) notes gardées sur l'iPhone ne sont pas incluses.")
        }
        return lines.joined(separator: "\n")
    }

    static func word(for kind: MemoryKind) -> String {
        switch kind {
        case .task: "tâche"
        case .appointment: "rendez-vous"
        case .idea: "idée"
        case .decision: "décision"
        case .preference: "préférence"
        case .info: "info"
        case .other: "note"
        }
    }

    /// « 9 janvier 2027 », « 1er janvier 2027 ».
    static func day(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM yyyy"
        let number = calendar.component(.day, from: date)
        return (number == 1 ? "1er" : String(number)) + " " + formatter.string(from: date)
    }
}
