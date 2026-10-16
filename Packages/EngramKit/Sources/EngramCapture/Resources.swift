import Foundation

/// F27 — une ressource lourde (un modèle) chargée une seule fois, même demandée deux fois en même temps.
public actor SingleFlight<Value: Sendable> {
    public init() {}

    public func value(_ load: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await load()
    }

    public func reset() {}
}

/// F27 — une seule transcription à la fois, pour toutes les dictées et le banc d'essai.
public actor SerialGate {
    public init() {}

    public func run<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await work()
    }
}
