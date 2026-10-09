import Foundation

/// Les notes trouvées, mises en texte pour un assistant (ChatGPT, Claude) quand le propriétaire le demande lui-même
/// dans un raccourci. Une note gardée sur l'iPhone ou jugée secrète n'y figure jamais.
public enum AssistantExport {
    public static func text(question: String, hits: [RecallHit], limit: Int = 5, calendar: Calendar, now: Date) -> String {
        ""
    }
}
