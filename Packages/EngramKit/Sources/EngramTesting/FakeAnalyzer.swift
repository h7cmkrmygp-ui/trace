import EngramCore
import Synchronization

/// Faux analyseur pour les tests : renvoie les réponses prévues dans l'ordre (la dernière se répète).
/// Ne jamais utiliser dans l'app.
public final class FakeAnalyzer: MemoryAnalyzer {
    struct State: Sendable {
        var responses: [Result<ThoughtAnalysis, AnalyzerError>]
        var calls: [[String]] = []
    }

    private let state: Mutex<State>

    public init(_ responses: [Result<ThoughtAnalysis, AnalyzerError>]) {
        state = Mutex(State(responses: responses))
    }

    public func analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis {
        let response: Result<ThoughtAnalysis, AnalyzerError>? = state.withLock { state in
            state.calls.append(existingCategories)
            guard !state.responses.isEmpty else { return nil }
            return state.responses.count > 1 ? state.responses.removeFirst() : state.responses[0]
        }
        guard let response else { throw AnalyzerError.unavailable("aucune réponse prévue") }
        return try response.get()
    }

    public var callCount: Int { state.withLock { $0.calls.count } }
    /// Listes de catégories reçues, un élément par appel.
    public var receivedCategories: [[String]] { state.withLock { $0.calls } }
}
