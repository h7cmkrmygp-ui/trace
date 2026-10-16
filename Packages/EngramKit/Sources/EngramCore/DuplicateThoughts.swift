import Foundation

/// Filet de sécurité après l'IA : deux pensées au même extrait (casse, accents et espaces ignorés) n'en font qu'une.
/// La première est gardée ; elle reçoit les dates et les étiquettes de l'autre.
public enum DuplicateThoughts {
    public static let maxTags = 3

    public static func merge(_ analysis: ThoughtAnalysis) -> ThoughtAnalysis {
        var merged: [AnalyzedThought] = []
        var indexByKey: [String: Int] = [:]
        for thought in analysis.thoughts {
            let key = Self.key(thought.excerpt)
            guard !key.isEmpty, let index = indexByKey[key] else {
                if !key.isEmpty { indexByKey[key] = merged.count }
                merged.append(thought)
                continue
            }
            var kept = merged[index]
            for date in thought.mentionedDates where !kept.mentionedDates.contains(date) { kept.mentionedDates.append(date) }
            for tag in thought.tags where !kept.tags.contains(tag) && kept.tags.count < maxTags { kept.tags.append(tag) }
            if kept.summary == nil { kept.summary = thought.summary }
            if kept.categoryDescription == nil { kept.categoryDescription = thought.categoryDescription }
            for mention in thought.temporal where !kept.temporal.contains(mention) { kept.temporal.append(mention) }
            // F03 — l'intention reste celle de la première ; sans intention, elle prend celle de l'autre (et sa polarité).
            if kept.intent == nil {
                kept.intent = thought.intent
                kept.polarity = thought.polarity
            }
            // Les choses de l'autre pour la même liste la rejoignent (P41).
            if kept.listName == nil {
                kept.listName = thought.listName
                kept.listItems = thought.listItems
            } else if kept.listName == thought.listName {
                for item in thought.listItems where !kept.listItems.contains(item) { kept.listItems.append(item) }
            }
            merged[index] = kept
        }
        return ThoughtAnalysis(thoughts: merged, route: analysis.route)
    }

    static func key(_ excerpt: String) -> String {
        WordErrorRate.words(excerpt.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_CA")))
            .joined(separator: " ")
    }
}
