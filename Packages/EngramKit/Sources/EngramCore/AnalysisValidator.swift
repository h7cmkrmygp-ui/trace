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
        var excerpt = thought.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !TextNormalizer.containsPhrase(excerpt, in: text) {
            // L'IA a pu écrire « puis » pour « pis » ou corriger une faute : on reprend les vrais mots du passage.
            guard let passage = closestPassage(to: excerpt, in: text) else { return nil }
            excerpt = passage
        }

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
                .filter { !$0.isEmpty && TextNormalizer.containsPhrase($0, in: text) },
            categoryDescription: thought.categoryDescription
                .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)) }
                .flatMap { $0.isEmpty ? nil : $0 })
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

    /// Mots-outils ignorés pour comparer un extrait à un passage.
    static let functionWords: Set<String> = [
        "les", "des", "une", "pour", "que", "qui", "dans", "sur", "avec", "pas", "mon", "mes", "ton", "tes", "son", "ses",
        "nos", "vos", "leur", "est", "the", "and", "for", "with",
    ]

    static func contentWords(_ text: String) -> Set<String> {
        Set(TextNormalizer.matchingForm(text).split(separator: " ").map(String.init)
            .filter { $0.count >= 3 && !functionWords.contains($0) })
    }

    /// Le passage du texte (une proposition, ou deux qui se suivent) qui contient au moins les trois quarts des mots
    /// porteurs de sens de l'extrait, sans être beaucoup plus long. nil si aucun ne correspond : l'extrait est inventé.
    static func closestPassage(to excerpt: String, in text: String) -> String? {
        let wanted = contentWords(excerpt)
        guard wanted.count >= 2 else { return nil }
        let source = text as NSString
        var pieces: [NSRange] = []
        var start = 0
        let separators = CharacterSet(charactersIn: ".!?;,\n")
        for index in 0...source.length {
            let atEnd = index == source.length
            if atEnd || separators.contains(UnicodeScalar(source.character(at: index)) ?? " ") {
                let raw = source.substring(with: NSRange(location: start, length: index - start))
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let offset = (raw as NSString).range(of: trimmed).location
                    pieces.append(NSRange(location: start + offset, length: (trimmed as NSString).length))
                }
                start = index + 1
            }
        }
        var candidates = pieces
        if pieces.count > 1 {
            for index in 0..<(pieces.count - 1) {
                candidates.append(NSRange(location: pieces[index].location,
                                          length: NSMaxRange(pieces[index + 1]) - pieces[index].location))
            }
        }
        var best: (passage: String, score: Double)?
        for range in candidates {
            let passage = source.substring(with: range)
            let words = contentWords(passage)
            guard !words.isEmpty else { continue }
            let shared = Double(wanted.intersection(words).count)
            let recall = shared / Double(wanted.count)
            let precision = shared / Double(words.count)
            guard recall >= 0.75, precision >= 0.5 else { continue }
            if recall + precision > best?.score ?? 0 { best = (passage, recall + precision) }
        }
        return best?.passage
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
