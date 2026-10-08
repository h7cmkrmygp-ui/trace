import Foundation

/// Fin de la parole : après au moins un peu de parole, le niveau du micro retombe au bruit de fond pendant 4 s.
/// Le bruit de fond est mesuré en continu (pièce calme, voiture…) : seule la voix au-dessus de lui compte.
public struct SilenceDetector: Sendable {
    public init() {}

    public mutating func add(level: Float, at time: TimeInterval, interval: TimeInterval) -> Bool { false }
}
