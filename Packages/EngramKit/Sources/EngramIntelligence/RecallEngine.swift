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
    /// F27 — vecteurs gardés au plus.
    public static let maxCachedVectors = 2_000
    /// Ordre d'entrée des vecteurs, pour retirer les plus anciens.
    private var order: [UUID] = []
    var cachedVectorCount: Int { lock.withLock { vectors.count } }

    public init(embedder: any SentenceEmbedder, neighbors: (any WordNeighbors)?) {
        self.embedder = embedder
        self.neighbors = neighbors
    }

    /// - Parameter previous: la question d'avant dans la conversation (« Et la semaine passée ? » reprend son sujet).
    public func search(_ question: String, in documents: [RecallDocument], now: Date, calendar: Calendar,
                       after previous: RecallQuery? = nil) -> RecallResult {
        let own = RecallQuery.parse(question, now: now, calendar: calendar)
        let query = RecallQuery.parse(question, now: now, calendar: calendar, after: previous)
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
        // Une question de suite (« Et la semaine passée ? ») n'a pas de sens à elle : on compare le sujet repris.
        let meaning = own.keywords.isEmpty ? query.spokenKeywords.joined(separator: " ") : question
        let scores = similarities(of: meaning, to: documents)
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
        lock.withLock {
            if vectors[document.id] == nil { order.append(document.id) }
            vectors[document.id] = (text, vector)
            // F27 — au-delà de la limite, les vecteurs les plus anciens partent (ils seront recalculés au besoin).
            if order.count > Self.maxCachedVectors {
                let excess = order.count - Self.maxCachedVectors
                for id in order.prefix(excess) { vectors[id] = nil }
                order.removeFirst(excess)
            }
        }
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
            if hit.outsidePeriod { line += " ; hors de la période demandée" }
            if let folder = document.categories.first { line += " ; dossier : \(folder)" }
            // F22 — le passage qui répond à la question, même après les 300 premiers caractères.
            let text = relevantText(document.text, question: question)
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


    /// F22 — le texte d'une note pour le modèle : en entier s'il est court, sinon la phrase qui répond à la question
    /// (et ce qui la suit), plutôt que le seul début.
    static func relevantText(_ text: String, question: String) -> String {
        guard text.count > maxTextLength else { return text }
        guard let sentence = SearchSnippet.make(text, query: question), let range = text.range(of: sentence) else {
            return String(text.prefix(maxTextLength))
        }
        return "… " + String(text[range.lowerBound...].prefix(maxTextLength))
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
