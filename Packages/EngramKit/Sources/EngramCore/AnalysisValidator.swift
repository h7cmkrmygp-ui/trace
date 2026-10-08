import Foundation

/// Règle anti-invention : seule une pensée dont l'extrait figure dans le texte est gardée, et tout est nettoyé.
public enum AnalysisValidator {
    public static let maxTags = 3
    public static let maxTagLength = 30
    public static let maxCategoryLength = 40

    /// Pensées valides, dans l'ordre. Lève `invalidOutput` s'il n'en reste aucune.
    public static func validate(_ analysis: ThoughtAnalysis, against text: String) throws -> [ValidThought] {
        let valid = analysis.thoughts.compactMap { validate($0, against: text) }
        guard !valid.isEmpty else { throw AnalyzerError.invalidOutput }
        return valid
    }

    static func validate(_ thought: AnalyzedThought, against text: String) -> ValidThought? {
        let excerpt = thought.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TextNormalizer.containsPhrase(excerpt, in: text) else { return nil }

        let proposedTitle = thought.title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let title = TitleMaker.fallbackTitle(from: proposedTitle.isEmpty ? excerpt : proposedTitle)

        let summary = thought.summary?.trimmingCharacters(in: .whitespacesAndNewlines)

        var path: [String] = []
        if let category = cleanName(thought.category, maxLength: maxCategoryLength) {
            path.append(category)
            if let sub = thought.subcategory.flatMap({ cleanName($0, maxLength: maxCategoryLength) }),
               TextNormalizer.normalizedName(sub) != TextNormalizer.normalizedName(category) {
                path.append(sub)
            }
        }

        var seen = Set<String>()
        var tags: [String] = []
        for raw in thought.tags {
            guard let tag = cleanName(raw, maxLength: maxTagLength),
                  seen.insert(TextNormalizer.normalizedName(tag)).inserted else { continue }
            tags.append(tag)
            if tags.count == maxTags { break }
        }

        let range = (text as NSString).range(of: excerpt)
        let found = range.location != NSNotFound
        return ValidThought(
            title: title,
            summary: (summary?.isEmpty ?? true) ? nil : summary,
            excerpt: excerpt,
            spanStart: found ? range.location : nil,
            spanEnd: found ? range.location + range.length : nil,
            kind: thought.kind,
            tags: tags,
            categoryPath: path,
            mentionedDates: thought.mentionedDates
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })
    }

    /// Espaces réduits ; `nil` si le nom ne contient ni lettre ni chiffre ; coupé à `maxLength`.
    static func cleanName(_ raw: String, maxLength: Int) -> String? {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !TextNormalizer.normalizedName(collapsed).isEmpty else { return nil }
        return String(collapsed.prefix(maxLength))
    }
}
