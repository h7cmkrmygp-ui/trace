import Foundation

/// F11 — une pensée nouvelle exprime-t-elle la même intention qu'une note déjà là (même type, et la plupart des mots
/// porteurs de sens de leurs extraits en commun) ? Sert à ne pas recréer à côté une note que le propriétaire a gardée.
/// « Appeler Paul » et « Appeler Marc » ne sont pas la même intention.
public enum IntentionMatch {
    /// Part minimale des mots en commun (sur l'ensemble des deux).
    static let threshold = 0.5

    public static func same(_ thought: ValidThought, as memory: Memory) -> Bool {
        guard memory.kind == nil || memory.kind == thought.kind else { return false }
        let new = words(thought.excerpt)
        let old = words(memory.excerpt)
        guard !new.isEmpty, !old.isEmpty else { return false }
        let shared = Double(new.intersection(old).count)
        return shared / Double(new.union(old).count) >= threshold
    }

    static func words(_ text: String) -> Set<String> {
        Set(AnalysisValidator.meaningfulWords(text).map(TextNormalizer.singularize))
    }
}
