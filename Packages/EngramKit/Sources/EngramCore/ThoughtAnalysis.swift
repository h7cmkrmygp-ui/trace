import Foundation

/// Une pensée telle que l'IA la propose (non vérifiée).
public struct AnalyzedThought: Sendable, Hashable {
    public var title: String
    public var summary: String?
    /// Citation censée être mot pour mot dans le texte d'origine.
    public var excerpt: String
    public var kind: MemoryKind
    public var tags: [String]
    public var mentionedDates: [String]
    /// Domaine large, en français (« Automobile »).
    public var category: String
    /// Sous-catégorie facultative (« Corolla »).
    public var subcategory: String?

    public init(title: String, summary: String?, excerpt: String, kind: MemoryKind, tags: [String],
                mentionedDates: [String], category: String, subcategory: String?) {
        self.title = title
        self.summary = summary
        self.excerpt = excerpt
        self.kind = kind
        self.tags = tags
        self.mentionedDates = mentionedDates
        self.category = category
        self.subcategory = subcategory
    }
}

/// Résultat brut d'une analyse.
public struct ThoughtAnalysis: Sendable, Hashable {
    public var thoughts: [AnalyzedThought]
    public init(thoughts: [AnalyzedThought]) { self.thoughts = thoughts }
}

public enum AnalyzerError: Error, Equatable, Sendable {
    /// Le modèle ne peut pas répondre pour l'instant (raison lisible) : on réessaiera plus tard.
    case unavailable(String)
    /// Le modèle refuse (garde-fous) : repli.
    case refused
    /// Sortie inutilisable : un nouvel essai, puis repli.
    case invalidOutput
    /// Modèle occupé : un nouvel essai.
    case busy
}

/// Ce qui analyse un texte : le modèle d'Apple dans l'app, un faux analyseur dans les tests.
public protocol MemoryAnalyzer: Sendable {
    /// `existingCategories` : chemins actifs, « Parent › Enfant ».
    func analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis
}

/// Une pensée vérifiée, prête à être classée.
public struct ValidThought: Sendable, Hashable {
    public var title: String
    public var summary: String?
    public var excerpt: String
    public var spanStart: Int?
    public var spanEnd: Int?
    public var kind: MemoryKind
    public var tags: [String]
    /// 0, 1 ou 2 niveaux : [] = « À classer ».
    public var categoryPath: [String]
    public var mentionedDates: [String]

    public init(title: String, summary: String?, excerpt: String, spanStart: Int?, spanEnd: Int?, kind: MemoryKind,
                tags: [String], categoryPath: [String], mentionedDates: [String]) {
        self.title = title
        self.summary = summary
        self.excerpt = excerpt
        self.spanStart = spanStart
        self.spanEnd = spanEnd
        self.kind = kind
        self.tags = tags
        self.categoryPath = categoryPath
        self.mentionedDates = mentionedDates
    }
}
