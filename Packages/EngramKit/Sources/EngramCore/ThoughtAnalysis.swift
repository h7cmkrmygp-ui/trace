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
    /// Courte description de la catégorie quand l'IA la crée (« Suivi de la santé, du poids… »).
    public var categoryDescription: String?
    /// Personnes et lieux nommés dans l'élément, recopiés de la note (P9).
    public var people: [String]
    public var places: [String]
    /// P32 — pourquoi l'IA choisit cette catégorie, en une phrase écrite avant de la choisir.
    public var categoryReason: String?

    public init(title: String, summary: String?, excerpt: String, kind: MemoryKind, tags: [String],
                mentionedDates: [String], category: String, subcategory: String?, categoryDescription: String? = nil,
                people: [String] = [], places: [String] = [], categoryReason: String? = nil) {
        self.categoryReason = categoryReason
        self.people = people
        self.places = places
        self.title = title
        self.summary = summary
        self.excerpt = excerpt
        self.kind = kind
        self.tags = tags
        self.mentionedDates = mentionedDates
        self.category = category
        self.subcategory = subcategory
        self.categoryDescription = categoryDescription
    }
}

/// Où et pourquoi une note a été classée (affiché au propriétaire, enregistré sur la source).
public struct AnalysisRoute: Sendable, Hashable {
    public var level: PrivacyLevel
    /// « gemini », « groq » ou « apple ».
    public var provider: String
    public var reason: String
    /// Classée sur l'iPhone faute de service disponible : à reclasser plus tard si personne n'y touche.
    public var needsCloudRetry: Bool

    public init(level: PrivacyLevel, provider: String, reason: String, needsCloudRetry: Bool) {
        self.level = level
        self.provider = provider
        self.reason = reason
        self.needsCloudRetry = needsCloudRetry
    }
}

/// Résultat brut d'une analyse.
public struct ThoughtAnalysis: Sendable, Hashable {
    public var thoughts: [AnalyzedThought]
    /// Renseigné par le routage (nil pour un analyseur seul).
    public var route: AnalysisRoute?

    public init(thoughts: [AnalyzedThought], route: AnalysisRoute? = nil) {
        self.thoughts = thoughts
        self.route = route
    }
}

/// Ce que l'analyseur sait de la note en plus de son texte : le choix du propriétaire et le moment de la dictée.
public struct AnalysisContext: Sendable, Equatable {
    /// « Garder sur l'iPhone ».
    public var keepLocal: Bool
    public var capturedAt: Date
    /// Ce qu'Engram a déjà reconnu dans la note (P31, `NoteFacts`), dit à l'IA avec elle.
    public var facts: [String]
    /// Ce que contient chaque catégorie existante (chemin → description), pour que l'IA juge par le sens (P32).
    public var categoryDescriptions: [String: String]

    public init(keepLocal: Bool = false, capturedAt: Date = Date(), facts: [String] = [],
                categoryDescriptions: [String: String] = [:]) {
        self.keepLocal = keepLocal
        self.capturedAt = capturedAt
        self.facts = facts
        self.categoryDescriptions = categoryDescriptions
    }
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
    /// Avec le contexte de la note (le routage s'en sert ; les autres analyseurs l'ignorent).
    func analyze(text: String, existingCategories: [String], context: AnalysisContext) async throws -> ThoughtAnalysis
}

extension MemoryAnalyzer {
    public func analyze(text: String, existingCategories: [String], context: AnalysisContext) async throws -> ThoughtAnalysis {
        try await analyze(text: text, existingCategories: existingCategories)
    }
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
    /// Description de la catégorie principale proposée par l'IA (posée seulement si elle n'en a pas).
    public var categoryDescription: String?
    /// Personnes et lieux vérifiés (présents dans le texte).
    public var people: [String]
    public var places: [String]
    /// P32 — la raison donnée par l'IA pour ce chemin (nil si Engram a refusé le chemin).
    public var categoryReason: String?

    public init(title: String, summary: String?, excerpt: String, spanStart: Int?, spanEnd: Int?, kind: MemoryKind,
                tags: [String], categoryPath: [String], mentionedDates: [String], categoryDescription: String? = nil,
                people: [String] = [], places: [String] = [], categoryReason: String? = nil) {
        self.categoryReason = categoryReason
        self.people = people
        self.places = places
        self.title = title
        self.summary = summary
        self.excerpt = excerpt
        self.spanStart = spanStart
        self.spanEnd = spanEnd
        self.kind = kind
        self.tags = tags
        self.categoryPath = categoryPath
        self.mentionedDates = mentionedDates
        self.categoryDescription = categoryDescription
    }
}
