import EngramCore
import EngramStore
import Foundation

/// F20 — un cas d'évaluation **fictif** : une dictée, ses effets attendus, la bonne lecture (oracle) et, s'il y a lieu,
/// une lecture fausse (adversaire) que le moteur doit neutraliser.
public struct ProductionCase: Sendable {
    public enum Split: String, Sendable { case dev, heldout }

    public let id: String
    public let split: Split
    public let family: String
    public let text: String
    public let keepLocal: Bool
    public let expected: ExpectedEffects
    public let oracle: ThoughtAnalysis
    public let adversary: ThoughtAnalysis?

    public init(id: String, split: Split, family: String, text: String, keepLocal: Bool = false,
                expected: ExpectedEffects, oracle: ThoughtAnalysis, adversary: ThoughtAnalysis? = nil) {
        self.id = id
        self.split = split
        self.family = family
        self.text = text
        self.keepLocal = keepLocal
        self.expected = expected
        self.oracle = oracle
        self.adversary = adversary
    }
}

/// F20 — les effets attendus d'une dictée.
public struct ExpectedEffects: Sendable, Equatable {
    /// « clé de liste|clé de chose ».
    public var listAdds: Set<String>
    public var noteKinds: [MemoryKind]
    /// nil : non vérifié.
    public var dueCount: Int?
    public var measurements: Int
    /// Une négation, une condition, une question ou une citation : aucune opération de liste n'est permise.
    public var forbidsListOperation: Bool

    public init(listAdds: Set<String> = [], noteKinds: [MemoryKind] = [], dueCount: Int? = nil, measurements: Int = 0,
                forbidsListOperation: Bool = false) {
        self.listAdds = listAdds
        self.noteKinds = noteKinds.sorted { $0.rawValue < $1.rawValue }
        self.dueCount = dueCount
        self.measurements = measurements
        self.forbidsListOperation = forbidsListOperation
    }
}

/// F20 — ce qui bloque une publication, quelle que soit la note globale.
public enum BlockingViolation: String, Sendable, Hashable, CaseIterable {
    /// Une opération de liste issue d'une négation, d'une condition, d'une question ou d'une citation.
    case forbiddenOperation
    /// Un ajout que la dictée ne demandait pas (« un achat non demandé »).
    case unrequestedOperation
    /// La dictée n'a laissé ni note ni ajout : elle est perdue.
    case lostCapture
    /// Une chose en double dans une liste.
    case duplicateEffect
    /// Une note gardée sur l'iPhone a été envoyée en ligne.
    case localLeak
}

/// F20 — le résultat d'un cas.
public struct CaseResult: Sendable, Equatable {
    public let id: String
    public let passed: Bool
    public let mismatches: [String]
    public let blocking: Set<BlockingViolation>
}

/// F20 — l'évaluateur de production : la dictée traverse le vrai chemin (validation, plan d'actions, rangement,
/// stockage) dans une base en mémoire, puis chaque effet est comparé à l'attendu.
public enum ProductionEvaluator {
    /// - Parameter makeAnalyzer: le modèle à évaluer (par défaut, la lecture donnée, sans modèle) ; il reçoit la base de
    ///   l'évaluation (pour y écrire ses reçus d'envoi).
    public static func evaluate(_ item: ProductionCase, reading: ThoughtAnalysis? = nil,
                                makeAnalyzer: (@Sendable (MemoryStore) -> any MemoryAnalyzer)? = nil) async -> CaseResult {
        CaseResult(id: item.id, passed: false, mismatches: [], blocking: [])
    }

    public static func report(_ results: [CaseResult], cases: [ProductionCase]) -> String { "" }
}

/// F20 — le corpus d'évaluation : des centaines de dictées **inventées**, en familles de paires minimales (agir sur une
/// chose ou l'acheter, acheter ou recevoir, devoir, pouvoir ou avoir fait, négation, condition, question, citation…),
/// réparties entre un jeu de développement et un jeu de contrôle mis de côté.
public enum EvaluationCorpus {
    public static let cases: [ProductionCase] = []
}
