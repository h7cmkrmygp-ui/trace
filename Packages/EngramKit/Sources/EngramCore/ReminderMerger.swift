import Foundation

/// Filet de sécurité après l'IA : une « note » qui n'est qu'un rappel de la précédente (« rappelle-moi ça demain »,
/// « fais-moi penser à ça ce soir », « remind me about it tomorrow ») rejoint cette note précédente :
/// sa date devient la date de rappel, en premier, et l'extrait couvre les deux morceaux, mot pour mot.
public enum ReminderMerger {
    public static func merge(_ analysis: ThoughtAnalysis, in text: String) -> ThoughtAnalysis {
        var merged: [AnalyzedThought] = []
        for thought in analysis.thoughts {
            if let previous = merged.last, isBareReminder(thought) {
                merged[merged.count - 1] = combine(previous, with: thought, in: text)
            } else {
                merged.append(thought)
            }
        }
        // Une note qui demande un rappel est une chose « À faire », même non découpée (un rendez-vous reste un rendez-vous).
        for index in merged.indices where merged[index].kind != .appointment && asksForReminder(merged[index].excerpt) {
            merged[index].kind = .task
        }
        return ThoughtAnalysis(thoughts: merged, route: analysis.route)
    }

    /// Formules qui ouvrent un simple rappel.
    static let triggers: [[String]] = [["rappelle", "moi"], ["fais", "moi", "penser"], ["remind", "me"]]

    /// L'extrait contient une demande de rappel (« rappelle-moi », « fais-moi penser », « remind me »).
    static func asksForReminder(_ excerpt: String) -> Bool {
        let words = tokens(excerpt)
        return triggers.contains { trigger in words.indices.contains { words[$0...].starts(with: trigger) } }
    }

    /// Mots qui peuvent suivre la formule sans ajouter de sujet : renvois (« ça », « it ») et expressions de temps.
    static let allowed: Set<String> = [
        "ca", "cela", "ceci", "le", "la", "l", "de", "d", "a", "au", "aux", "en", "y", "moi", "me", "aussi", "encore",
        "svp", "s", "il", "te", "plait", "penser", "it", "that", "this", "about", "of", "to", "again", "please", "then",
        "demain", "apres", "aujourd", "hui", "ce", "cet", "cette", "soir", "matin", "midi", "nuit", "lundi", "mardi",
        "mercredi", "jeudi", "vendredi", "samedi", "dimanche", "semaine", "prochaine", "prochain", "fin", "dans", "jour",
        "jours", "heure", "heures", "h", "minute", "minutes", "min", "janvier", "fevrier", "mars", "avril", "mai", "juin",
        "juillet", "aout", "septembre", "octobre", "novembre", "decembre", "tomorrow", "today", "tonight", "morning",
        "evening", "afternoon", "night", "next", "week", "monday", "tuesday", "wednesday", "thursday", "friday",
        "saturday", "sunday", "in", "day", "days", "hour", "hours", "at", "on", "the",
    ]

    static func tokens(_ text: String) -> [String] {
        WordErrorRate.words(text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_CA")))
    }

    static func isBareReminder(_ thought: AnalyzedThought) -> Bool {
        let words = tokens(thought.excerpt)
        guard let trigger = triggers.first(where: { words.starts(with: $0) }) else { return false }
        let dateWords = Set(thought.mentionedDates.flatMap(tokens))
        return words.dropFirst(trigger.count).allSatisfy { word in
            allowed.contains(word) || dateWords.contains(word) || word.allSatisfy(\.isNumber)
        }
    }

    static func combine(_ previous: AnalyzedThought, with reminder: AnalyzedThought, in text: String) -> AnalyzedThought {
        var result = previous
        // Un rappel demandé en fait une chose « À faire » (un rendez-vous reste un rendez-vous).
        if previous.kind != .appointment { result.kind = .task }
        // La date du rappel donne l'échéance, sauf pour un rendez-vous : sa date à lui va dans le calendrier.
        let ordered = previous.kind == .appointment ? previous.mentionedDates + reminder.mentionedDates
                                                     : reminder.mentionedDates + previous.mentionedDates
        var dates: [String] = []
        for date in ordered where !dates.contains(date) { dates.append(date) }
        result.mentionedDates = dates
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if let first = text.range(of: previous.excerpt, options: options),
           let second = text.range(of: reminder.excerpt, options: options, range: first.upperBound..<text.endIndex) {
            result.excerpt = String(text[first.lowerBound..<second.upperBound])
        }
        return result
    }
}
