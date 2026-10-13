import Foundation

/// P39 — Retrouver répond direct : pour une question de fait (un numéro, un montant, une date, un endroit), la réponse
/// exacte tirée de la meilleure note, avec la note d'où elle vient. Sans valeur dans la note, pas de réponse : la réponse
/// habituelle prend le relais. Rien n'est inventé.
public enum DirectAnswer {
    public static func make(question: String, hits: [RecallHit], now: Date, calendar: Calendar) -> String? {
        nil
    }
}
