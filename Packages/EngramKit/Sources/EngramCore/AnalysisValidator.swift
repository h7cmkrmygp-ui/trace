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

        let path = categoryPath(category: thought.category, subcategory: thought.subcategory)

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
            // Une date n'est gardée que si l'expression figure dans le texte : l'IA relève, elle n'invente pas.
            mentionedDates: thought.mentionedDates
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && TextNormalizer.containsPhrase($0, in: text) })
    }

    /// Chemin de 0 à 2 niveaux. Un modèle peut renvoyer « Automobile › Corolla » dans un seul champ :
    /// on découpe sur « › », « > » et « / », et on retire un parent répété dans la sous-catégorie.
    static func categoryPath(category: String, subcategory: String?) -> [String] {
        func parts(_ raw: String?) -> [String] {
            guard let raw else { return [] }
            return raw.components(separatedBy: CharacterSet(charactersIn: "›>/"))
                .compactMap { cleanName($0, maxLength: maxCategoryLength) }
        }
        let categoryParts = parts(category)
        guard !categoryParts.isEmpty else { return [] }
        var path: [String] = []
        for part in categoryParts + parts(subcategory) {
            let key = TextNormalizer.normalizedName(part)
            if path.contains(where: { TextNormalizer.normalizedName($0) == key }) { continue }
            path.append(part)
        }
        return Array(path.prefix(2))
    }

    /// Part des mots du texte (0 à 1) que l'on retrouve dans les extraits.
    public static func coverage(of excerpts: [String], in text: String) -> Double {
        let words = TextNormalizer.matchingForm(text).split(separator: " ")
        guard !words.isEmpty else { return 1 }
        let covered = Set(excerpts.flatMap { TextNormalizer.matchingForm($0).split(separator: " ") })
        return Double(words.filter { covered.contains($0) }.count) / Double(words.count)
    }

    /// Espaces réduits ; `nil` si le nom ne contient ni lettre ni chiffre ; coupé à `maxLength`.
    static func cleanName(_ raw: String, maxLength: Int) -> String? {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !TextNormalizer.normalizedName(collapsed).isEmpty else { return nil }
        return String(collapsed.prefix(maxLength))
    }
}
