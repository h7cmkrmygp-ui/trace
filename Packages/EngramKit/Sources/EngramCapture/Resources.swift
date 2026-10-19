import Foundation

/// F27 — une ressource lourde (un modèle) chargée une seule fois, même demandée deux fois en même temps : le second
/// appel attend le chargement en cours au lieu d'en lancer un autre. Un échec n'est pas gardé (le prochain appel
/// réessaie) ; `reset` libère la ressource.
public actor SingleFlight<Value: Sendable> {
    private var loaded: Value?
    private var loading: Task<Value, Error>?

    public init() {}

    public func value(_ load: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let loaded { return loaded }
        if let loading { return try await loading.value }
        let task = Task { try await load() }
        loading = task
        do {
            let value = try await task.value
            loaded = value
            loading = nil
            return value
        } catch {
            loading = nil
            throw error
        }
    }

    /// La ressource chargée, s'il y en a une.
    public func current() -> Value? { loaded }

    public func reset() {
        loaded = nil
        loading = nil
    }
}

/// F27 — une seule transcription à la fois, pour toutes les dictées et le banc d'essai : les suivantes attendent leur
/// tour, dans l'ordre d'arrivée.
public actor SerialGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func run<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        while busy { await withCheckedContinuation { waiters.append($0) } }
        busy = true
        defer {
            busy = false
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        return try await work()
    }
}
