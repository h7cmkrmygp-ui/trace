import EngramCore
import Foundation
import NaturalLanguage

/// Mots proches d'un mot (le modèle de langue d'Apple dans l'app, un faux dans les tests).
public protocol WordNeighbors: Sendable {
    func neighbors(of word: String) -> [String]
}

/// Mots proches selon les plongements de mots d'Apple, calculés **sur l'iPhone**.
public final class AppleWordNeighbors: WordNeighbors, @unchecked Sendable {
    private let lock = NSLock()
    private var isLoaded = false
    private var embedding: NLEmbedding?

    public init() {}

    public func neighbors(of word: String) -> [String] {
        lock.withLock {
            if !isLoaded {
                embedding = NLEmbedding.wordEmbedding(for: .french)
                isLoaded = true
            }
            // Seulement les voisins très proches : un mot vaguement lié ne doit pas faire remonter une note.
            return embedding?.neighbors(for: word, maximumCount: 4).filter { $0.1 < 0.8 }.map { $0.0 } ?? []
        }
    }
}

public struct RecallResult: Sendable, Equatable {
    public let query: RecallQuery
    public let hits: [RecallHit]

    public init(query: RecallQuery, hits: [RecallHit]) {
        self.query = query
        self.hits = hits
    }
}

/// « Retrouver » : question comprise, notes triées par mots, mots proches et sens. Entièrement sur l'iPhone :
/// ni la question ni les notes ne sont envoyées à un service en ligne.
public final class RecallEngine: @unchecked Sendable {
    let embedder: any SentenceEmbedder
    let neighbors: (any WordNeighbors)?
    private let lock = NSLock()
    /// Vecteurs de sens déjà calculés (recalculés si le texte de la note change).
    private var vectors: [UUID: (text: String, vector: [Double]?)] = [:]

    public init(embedder: any SentenceEmbedder, neighbors: (any WordNeighbors)?) {
        self.embedder = embedder
        self.neighbors = neighbors
    }

    public func search(_ question: String, in documents: [RecallDocument], now: Date, calendar: Calendar) -> RecallResult {
        let query = RecallQuery.parse(question, now: now, calendar: calendar)
        guard !query.keywords.isEmpty else {
            return RecallResult(query: query, hits: RecallRanker.rank(documents, for: query, now: now))
        }
        var expansions: [String: [String]] = [:]
        if let neighbors {
            for (keyword, spoken) in zip(query.keywords, query.spokenKeywords) {
                let found = neighbors.neighbors(of: spoken)
                if !found.isEmpty { expansions[keyword] = found }
            }
        }
        let scores = similarities(of: question, to: documents)
        return RecallResult(query: query, hits: RecallRanker.rank(documents, for: query, now: now, semanticScores: scores,
                                                                  expansions: expansions))
    }

    /// Notes liées à une note : même sujet par les mots ou par le sens.
    public func related(to document: RecallDocument, in documents: [RecallDocument], now: Date) -> [RecallHit] {
        let others = documents.filter { $0.id != document.id }
        return RecallRanker.related(to: document, in: documents, now: now,
                                    semanticScores: similarities(of: document.meaningText, to: others))
    }

    func similarities(of text: String, to documents: [RecallDocument]) -> [UUID: Double] {
        guard let target = embedder.vector(for: text) else { return [:] }
        var scores: [UUID: Double] = [:]
        for document in documents {
            guard let vector = vector(for: document) else { continue }
            scores[document.id] = CategoryHints.cosine(target, vector)
        }
        return scores
    }

    private func vector(for document: RecallDocument) -> [Double]? {
        let text = document.meaningText
        if let cached = lock.withLock({ vectors[document.id] }), cached.text == text { return cached.vector }
        let vector = embedder.vector(for: text)
        lock.withLock { vectors[document.id] = (text, vector) }
        return vector
    }
}

/// Consigne donnée à l'IA d'Apple pour rédiger la réponse, à partir des seules notes trouvées.
public enum RecallAnswerPrompt {
    public static let maxNotes = 8
    static let maxTextLength = 300

    public static let instructions = """
        You answer the owner's question about their own notes, in French as spoken in Québec, addressing them as « tu ».
        Use only the notes listed in the prompt. Never invent a note, a detail, a name, a place, a date or an amount.
        Answer in one to three short sentences. Mention the date or the deadline when it helps.
        For a list or a summary, group the notes briefly instead of repeating them word for word.
        If none of the notes answers the question, answer exactly: « Je ne trouve rien là-dessus dans ta mémoire. »
        """

    public static func prompt(question: String, hits: [RecallHit], now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d MMMM yyyy"
        let notes = hits.prefix(maxNotes).enumerated().map { index, hit in
            let document = hit.document
            var line = "\(index + 1). [\(label(document.kind))] « \(document.title) » — notée le \(formatter.string(from: document.capturedAt))"
            if let due = document.dueAt { line += " ; échéance : \(formatter.string(from: due))" }
            if document.status == .archived { line += " ; marquée comme faite" }
            if let folder = document.categories.first { line += " ; dossier : \(folder)" }
            let text = String(document.text.prefix(maxTextLength))
            if text != document.title { line += "\n   Texte : \(text)" }
            return line
        }
        return """
            Aujourd'hui : \(formatter.string(from: now)).
            Question : \(question)
            Notes trouvées :
            \(notes.joined(separator: "\n"))
            """
    }

    static func label(_ kind: MemoryKind?) -> String {
        switch kind {
        case .task: "tâche"
        case .appointment: "rendez-vous"
        case .idea: "idée"
        case .decision: "décision"
        case .preference: "préférence"
        case .info: "info"
        case .other, nil: "note"
        }
    }
}
