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
            merged[index] = kept
        }
        return ThoughtAnalysis(thoughts: merged, route: analysis.route)
    }

    static func key(_ excerpt: String) -> String {
        WordErrorRate.words(excerpt.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_CA")))
            .joined(separator: " ")
    }
}
