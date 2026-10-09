import Foundation

/// P31 — « C'est quand déjà la fête à Amina ? » : Retrouver et Siri répondent avec la fête gardée sur la page de la personne.
public enum BirthdayQuestion {
    /// La personne dont on demande la date de fête ; nil si la question porte sur autre chose.
    public static func person(in question: String) -> String? {
        nil
    }

    /// La fête de cette personne : même nom, ou un nom entendu à une lettre près s'il n'y en a qu'un.
    public static func find(_ name: String, in birthdays: [Birthday]) -> Birthday? {
        nil
    }

    /// « La fête d'Amina, c'est le 13 octobre, dans 4 jours. »
    public static func answer(_ birthday: Birthday, now: Date, calendar: Calendar) -> String {
        ""
    }
}
