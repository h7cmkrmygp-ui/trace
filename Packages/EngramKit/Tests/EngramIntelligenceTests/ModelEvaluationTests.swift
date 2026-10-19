import EngramCore
import EngramPipeline
import EngramStore
import Foundation
import Testing
@testable import EngramIntelligence

/// F20 — l'évaluation des **vrais** modèles sur le jeu de contrôle du corpus (dictées inventées), par le vrai chemin de
/// production (validation, plan d'actions, rangement, stockage). Seuils de publication : aucun effet bloquant, et au
/// moins 80 % des cas réussis.
///
/// Rien ne tourne par défaut :
/// - modèle d'Apple (gratuit, sur l'appareil) : `ENGRAM_RUN_MODEL_EVAL=1`, sur un iPhone ou un simulateur où le modèle est
///   disponible (workflow « Apple evaluation ») ;
/// - Gemini et Groq : en plus `ENGRAM_ALLOW_CLOUD_EVAL=1` et les clés `ENGRAM_GEMINI_KEY`, `ENGRAM_GROQ_KEY`, seulement avec
///   l'accord explicite du propriétaire (les dictées sont fictives, mais elles partent en ligne). Les clés ne sont jamais
///   affichées.
struct ModelEvaluationTests {
    static let environment = ProcessInfo.processInfo.environment
    static let enabled = environment["ENGRAM_RUN_MODEL_EVAL"] == "1"
    static let cloudAllowed = enabled && environment["ENGRAM_ALLOW_CLOUD_EVAL"] == "1"
    static let threshold = 0.8

    static var heldout: [ProductionCase] { EvaluationCorpus.cases.filter { $0.split == .heldout } }

    static func run(_ name: String, _ makeAnalyzer: @escaping @Sendable (MemoryStore) -> any MemoryAnalyzer) async
        -> [CaseResult] {
        var results: [CaseResult] = []
        for item in heldout { results.append(await ProductionEvaluator.evaluate(item, makeAnalyzer: makeAnalyzer)) }
        print("ÉVALUATION DE PRODUCTION — \(name) (jeu de contrôle)\n" + ProductionEvaluator.report(results, cases: heldout))
        return results
    }

    static func check(_ results: [CaseResult]) {
        #expect(results.allSatisfy { $0.blocking.isEmpty })
        #expect(Double(results.filter(\.passed).count) >= threshold * Double(max(results.count, 1)))
    }

    #if canImport(FoundationModels)
    @Test(.enabled(if: enabled)) func appleModel() async {
        guard AppleThoughtAnalyzer.availabilityDescription().isAvailable else {
            print("MODÈLE D'APPLE INDISPONIBLE : évaluation non exécutée")
            return
        }
        Self.check(await Self.run("Apple") { _ in AppleThoughtAnalyzer() })
    }
    #endif

    @Test(.enabled(if: cloudAllowed)) func gemini() async {
        guard let key = Self.environment["ENGRAM_GEMINI_KEY"], !key.isEmpty else {
            print("GEMINI : aucune clé, évaluation non exécutée")
            return
        }
        Self.check(await Self.run("Gemini") { _ in
            GeminiThoughtAnalyzer(client: GeminiClient(apiKey: key), models: ["gemini-2.5-flash"])
        })
    }

    @Test(.enabled(if: cloudAllowed)) func groq() async {
        guard let key = Self.environment["ENGRAM_GROQ_KEY"], !key.isEmpty else {
            print("GROQ : aucune clé, évaluation non exécutée")
            return
        }
        Self.check(await Self.run("Groq") { _ in GroqThoughtAnalyzer(client: GroqClient(apiKey: key)) })
    }
}
