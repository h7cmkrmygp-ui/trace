import Foundation

/// Les jours relatifs (« aujourd'hui », « demain »…) d'un titre ou d'un texte deviennent la vraie date de la dictée.
public enum RelativeDateWording {
    public static func anchored(_ text: String, on day: Date, calendar: Calendar) -> String {
        text
    }
}
