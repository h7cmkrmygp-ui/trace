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
    /// Le moment fixe des évaluations (les échéances sont reproductibles).
    static let evaluationDate = Date(timeIntervalSince1970: 1_800_000_000)

    struct Clock: DateProvider {
        let date: Date
        func now() -> Date { date }
    }

    /// Une lecture donnée d'avance (aucun modèle).
    struct GivenReading: MemoryAnalyzer {
        let analysis: ThoughtAnalysis
        func analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis { analysis }
    }

    /// - Parameter makeAnalyzer: le modèle à évaluer (par défaut, la lecture donnée, sans modèle) ; il reçoit la base de
    ///   l'évaluation (pour y écrire ses reçus d'envoi).
    public static func evaluate(_ item: ProductionCase, reading: ThoughtAnalysis? = nil,
                                makeAnalyzer: (@Sendable (MemoryStore) -> any MemoryAnalyzer)? = nil) async -> CaseResult {
        do {
            let database = try AppDatabase.inMemory()
            let dates = Clock(date: evaluationDate)
            let memories = MemoryStore(database: database, dates: dates)
            let analyzer: any MemoryAnalyzer = makeAnalyzer?(memories) ?? GivenReading(analysis: reading ?? item.oracle)
            let processor = ThoughtProcessor(memories: memories, categories: CategoryStore(database: database, dates: dates),
                                             filer: ThoughtFiler(database: database, dates: dates), analyzer: analyzer)
            guard case .saved(let interim) = try memories.saveTextNoteWithoutAnalysis(item.text, keepLocal: item.keepLocal)
            else {
                return CaseResult(id: item.id, passed: false, mismatches: ["dictée non enregistrée"], blocking: [])
            }
            _ = await processor.process(sourceID: interim.sourceID)
            return score(item, try memories.effects(of: interim.sourceID))
        } catch {
            return CaseResult(id: item.id, passed: false, mismatches: ["erreur : \(error)"], blocking: [])
        }
    }

    /// Chaque effet comparé à l'attendu ; les effets bloquants à part.
    static func score(_ item: ProductionCase, _ effects: SourceEffects) -> CaseResult {
        let expected = item.expected
        var mismatches: [String] = []
        if effects.listAdds != expected.listAdds {
            mismatches.append("ajouts \(effects.listAdds.sorted()) au lieu de \(expected.listAdds.sorted())")
        }
        if effects.noteKinds != expected.noteKinds {
            mismatches.append("notes \(effects.noteKinds.map(\.rawValue)) au lieu de \(expected.noteKinds.map(\.rawValue))")
        }
        if let due = expected.dueCount, due != effects.dueCount {
            mismatches.append("échéances \(effects.dueCount) au lieu de \(due)")
        }
        if effects.measurements != expected.measurements {
            mismatches.append("mesures \(effects.measurements) au lieu de \(expected.measurements)")
        }
        var blocking: Set<BlockingViolation> = []
        if expected.forbidsListOperation, !effects.listAdds.isEmpty { blocking.insert(.forbiddenOperation) }
        if !expected.forbidsListOperation, !effects.listAdds.subtracting(expected.listAdds).isEmpty {
            blocking.insert(.unrequestedOperation)
        }
        if effects.anyNote == 0, effects.listAdds.isEmpty { blocking.insert(.lostCapture) }
        if !effects.duplicatedItems.isEmpty { blocking.insert(.duplicateEffect) }
        if item.keepLocal, effects.transmissions > 0 { blocking.insert(.localLeak) }
        return CaseResult(id: item.id, passed: mismatches.isEmpty && blocking.isEmpty, mismatches: mismatches,
                          blocking: blocking)
    }

    /// Le rapport d'une évaluation : réussite par jeu et par famille, et chaque effet bloquant (sans le texte des
    /// dictées : seulement leurs identifiants).
    public static func report(_ results: [CaseResult], cases: [ProductionCase]) -> String {
        let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        var lines: [String] = []
        for split in [ProductionCase.Split.dev, .heldout] {
            let selected = results.filter { byID[$0.id]?.split == split }
            lines.append("\(split.rawValue) : \(selected.filter(\.passed).count)/\(selected.count) réussis")
        }
        let families = Set(cases.map(\.family)).sorted()
        for family in families {
            let selected = results.filter { byID[$0.id]?.family == family }
            lines.append("  \(family) : \(selected.filter(\.passed).count)/\(selected.count)")
        }
        for violation in BlockingViolation.allCases {
            let ids = results.filter { $0.blocking.contains(violation) }.map(\.id)
            lines.append("BLOQUANT \(violation.rawValue) : \(ids.count)\(ids.isEmpty ? "" : " — \(ids.prefix(20).joined(separator: ", "))")")
        }
        return lines.joined(separator: "\n")
    }
}
