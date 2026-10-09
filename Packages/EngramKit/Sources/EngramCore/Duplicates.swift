import Foundation

/// P23 — la même pensée dite deux fois.
public enum DuplicateFinder {
    public struct Note: Sendable, Equatable {
        public let id: UUID
        public let text: String
        public let kind: MemoryKind?
        public let capturedAt: Date

        public init(id: UUID, text: String, kind: MemoryKind?, capturedAt: Date) {
            self.id = id
            self.text = text
            self.kind = kind
            self.capturedAt = capturedAt
        }
    }

    /// Deux notes qui se ressemblent : la plus ancienne est gardée.
    public struct Pair: Sendable, Equatable {
        public let keep: UUID
        public let duplicate: UUID
        public let score: Double
    }

    /// Ressemblance minimale (mots en commun sur tous les mots).
    public static let threshold = 0.75
    /// Deux notes plus éloignées que ça sont deux pensées distinctes.
    public static let maximumGap: TimeInterval = 30 * 86_400
    /// Mots qui ne disent rien de l'idée (« il faut appeler » = « appeler »).
    static let fillers: Set<String> = ["faut", "falloir", "euh", "ben", "bon", "faque", "dois", "doit", "devrais", "aller",
                                       "vais", "va", "rappelle", "rappeler", "penser", "pense", "oublier", "oublie"]

    /// Les mots qui portent l'idée : sans accents, au singulier, sans les petits mots.
    static func words(_ text: String) -> Set<String> {
        Set(TextNormalizer.normalizedName(text).split(separator: " ").map(String.init))
            .subtracting(RecallText.stopwords)
            .subtracting(fillers)
            .filter { $0.count >= 2 }
    }

    /// Les paires de notes du même genre, à moins de 30 jours, qui disent presque les mêmes mots. Une note n'est
    /// proposée que dans une paire à la fois ; une paire écartée (« ce n'est pas un doublon ») ne revient pas.
    public static func pairs(_ notes: [Note], dismissed: Set<String> = []) -> [Pair] {
        let sorted = notes.sorted { ($0.capturedAt, $0.id.uuidString) < ($1.capturedAt, $1.id.uuidString) }
        let words = sorted.map { Self.words($0.text) }
        var used: Set<UUID> = []
        var found: [Pair] = []
        for first in sorted.indices where !used.contains(sorted[first].id) && words[first].count >= 2 {
            for second in sorted.indices where second > first && !used.contains(sorted[second].id) {
                let older = sorted[first]
                let newer = sorted[second]
                guard newer.kind == older.kind, words[second].count >= 2,
                      newer.capturedAt.timeIntervalSince(older.capturedAt) <= maximumGap,
                      !dismissed.contains(key(older.id, newer.id)) else { continue }
                let shared = words[first].intersection(words[second]).count
                let all = words[first].union(words[second]).count
                let score = all == 0 ? 0 : Double(shared) / Double(all)
                guard score >= threshold else { continue }
                found.append(Pair(keep: older.id, duplicate: newer.id, score: score))
                used.insert(older.id)
                used.insert(newer.id)
                break
            }
        }
        return found
    }

    /// La clé d'une paire, dans n'importe quel ordre.
    public static func key(_ first: UUID, _ second: UUID) -> String {
        [first.uuidString, second.uuidString].sorted().joined(separator: "|")
    }

    /// Le texte de la note gardée, complété par celui du doublon s'il dit quelque chose de plus.
    public static func mergedBody(keep: String, duplicate: String) -> String {
        let kept = keep.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = duplicate.trimmingCharacters(in: .whitespacesAndNewlines)
        if extra.isEmpty { return kept }
        if kept.isEmpty { return extra }
        if TextNormalizer.matchingForm(kept).contains(TextNormalizer.matchingForm(extra)) { return kept }
        return kept + "\n" + extra
    }
}
