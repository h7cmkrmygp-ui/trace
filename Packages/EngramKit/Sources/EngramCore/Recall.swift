import Foundation

// « Retrouver » : on pose une question floue, Engram retrouve les vraies notes. Tout se calcule sur l'iPhone.
// Rien n'est inventé : une note n'est proposée que si ses mots, son sens, son dossier ou sa date répondent.

/// Une question posée à « Retrouver », comprise sans IA (déterministe, français et anglais).
public struct RecallQuery: Sendable, Equatable {
    public enum Intent: String, Sendable, Equatable {
        /// Retrouver quelque chose de précis (« le nom du restaurant »).
        case find
        /// Lister selon une période ou un type (« mes tâches de cette semaine »).
        case list
        /// Résumer (« résume mes idées de la semaine »).
        case summarize
    }

    /// Mots utiles de la question, sans accents ni majuscules.
    public var keywords: [String] = []
    /// Les mêmes mots tels qu'ils ont été dits, accents compris (pour chercher des mots proches).
    public var spokenKeywords: [String] = []
    /// Types de notes demandés (vide = tous).
    public var kinds: Set<MemoryKind> = []
    /// Période demandée (nil = n'importe quand).
    public var period: DateInterval?
    /// La période porte sur l'échéance (« prévu aujourd'hui », « demain ») plutôt que sur le jour de la note.
    public var periodMeansDue = false
    public var intent: Intent = .find

    public init() {}

    public static func parse(_ question: String, now: Date, calendar: Calendar) -> RecallQuery {
        var text = " " + RecallText.normalize(question) + " "
        var query = RecallQuery()

        if let found = RecallPeriods.find(in: text, now: now, calendar: calendar) {
            query.period = found.interval
            text.replaceSubrange(found.range, with: " ")
        }
        let isPlanning = RecallText.contains(#"\b(prevus?|prevues?|a faire|dois|devais|doit|devrais|faut|fallait|agenda|planned|have to|had to|need to|scheduled?)\b"#, in: text)
        if let period = query.period {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            query.periodMeansDue = isPlanning || period.start >= tomorrow
        }

        query.kinds = Self.kinds(in: text, isPlanning: isPlanning)

        var seen: Set<String> = []
        query.keywords = RecallText.tokens(text).filter { word in
            guard !RecallText.stopwords.contains(word), word.count >= 2 || word.allSatisfy(\.isNumber) else { return false }
            return seen.insert(word).inserted
        }
        query.spokenKeywords = RecallText.spoken(query.keywords, in: question)

        if RecallText.contains(#"\b(resume|resumer|resumes|recapitule|recapituler|recap|summarize|summary|summarise)\b"#, in: text) {
            query.intent = .summarize
        } else if query.keywords.isEmpty {
            query.intent = .list
        }
        return query
    }

    /// Question de suite (« Et la semaine passée ? », « de ce sujet ») : reprend le sujet et le type de la précédente.
    public static func parse(_ question: String, now: Date, calendar: Calendar, after previous: RecallQuery?) -> RecallQuery {
        var query = parse(question, now: now, calendar: calendar)
        // Seulement une vraie question de suite, sans sujet à elle : une nouvelle question n'hérite de rien.
        guard let previous, query.keywords.isEmpty, isFollowUp(question) else { return query }
        query.keywords = previous.keywords
        query.spokenKeywords = previous.spokenKeywords
        if query.kinds.isEmpty { query.kinds = previous.kinds }
        if query.period == nil {
            query.period = previous.period
            query.periodMeansDue = previous.periodMeansDue
        }
        if query.intent != .summarize { query.intent = query.keywords.isEmpty ? .list : .find }
        return query
    }

    /// « Et la semaine passée ? », « de ce sujet », « et celles du mois dernier ».
    static func isFollowUp(_ question: String) -> Bool {
        let text = " " + RecallText.normalize(question) + " "
        return RecallText.contains(#"^\s*(et|and|puis|pis|aussi)\b"#, in: text)
            || RecallText.contains(#"\b(ce sujet|meme sujet|meme chose|ca|cela|celles|ceux|celle|celui|lesquelles|lesquels|that|those|it)\b"#, in: text)
    }

    /// Recherche « sur le même sujet » qu'un texte (notes liées) : ses mots utiles, sans période ni type.
    public static func about(_ text: String) -> RecallQuery {
        var query = RecallQuery()
        var seen: Set<String> = []
        query.keywords = Array(RecallText.tokens(text).filter { word in
            !RecallText.stopwords.contains(word) && word.count >= 3 && seen.insert(word).inserted
        }.prefix(12))
        query.spokenKeywords = RecallText.spoken(query.keywords, in: text)
        return query
    }

    /// Les types nommés gagnent sur le verbe « faire » (« une idée pour faire un jardin » = une idée).
    static func kinds(in text: String, isPlanning: Bool) -> Set<MemoryKind> {
        var kinds: Set<MemoryKind> = []
        if RecallText.contains(#"\b(idees?|ideas?)\b"#, in: text) { kinds.insert(.idea) }
        if RecallText.contains(#"\b(rendez vous|rdv|appointments?|meetings?)\b"#, in: text) { kinds.insert(.appointment) }
        if RecallText.contains(#"\b(decisions?|decide|decided)\b"#, in: text) { kinds.insert(.decision) }
        if RecallText.contains(#"\b(taches?|tasks?|rappels?|reminders?|to do|todo)\b"#, in: text) {
            kinds.formUnion([.task, .appointment])
        }
        if kinds.isEmpty, isPlanning || RecallText.contains(#"\b(faire|do)\b"#, in: text) {
            kinds = [.task, .appointment]
        }
        return kinds
    }
}

/// Une note telle que « Retrouver » la lit.
public struct RecallDocument: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let title: String
    /// Contenu, résumé et extrait (le texte d'origine reste dans la note).
    public let text: String
    public let kind: MemoryKind?
    public let status: MemoryStatus
    public let capturedAt: Date
    public let dueAt: Date?
    /// Dossiers (chemins complets, du plus large au plus précis).
    public let categories: [String]
    public let tags: [String]
    /// Gardée sur l'iPhone ou jugée secrète : jamais donnée à un assistant extérieur.
    public let isPrivate: Bool

    public init(id: UUID, title: String, text: String, kind: MemoryKind?, status: MemoryStatus, capturedAt: Date,
                dueAt: Date?, categories: [String], tags: [String], isPrivate: Bool = false) {
        self.id = id
        self.title = title
        self.text = text
        self.kind = kind
        self.status = status
        self.capturedAt = capturedAt
        self.dueAt = dueAt
        self.categories = categories
        self.tags = tags
        self.isPrivate = isPrivate
    }

    /// Ce que le sens compare à la question.
    public var meaningText: String { ([title, text] + categories).joined(separator: ". ") }
}

public struct RecallHit: Sendable, Equatable {
    public let document: RecallDocument
    public let score: Double

    public init(document: RecallDocument, score: Double) {
        self.document = document
        self.score = score
    }
}

/// Trie les notes pour une question.
public enum RecallRanker {
    /// Score minimal d'une note proposée pour une recherche précise.
    static let threshold = 0.55

    /// - Parameters:
    ///   - semanticScores: ressemblance de sens (−1 à 1) entre la question et chaque note, calculée sur l'iPhone.
    ///   - expansions: mots proches d'un mot de la question (plongements de mots), en plus des synonymes connus.
    public static func rank(_ documents: [RecallDocument], for query: RecallQuery, now: Date,
                            semanticScores: [UUID: Double] = [:], expansions: [String: [String]] = [:],
                            limit: Int = 8) -> [RecallHit] {
        let candidates = documents.filter { $0.status != .trashed }
        if query.keywords.isEmpty {
            return list(candidates, for: query, now: now, limit: max(limit, 20))
        }
        return find(candidates, for: query, now: now, semanticScores: semanticScores, expansions: expansions,
                    limit: query.intent == .find ? limit : max(limit, 12))
    }

    /// Notes sur le même sujet qu'une note (jamais elle-même), seulement au-dessus d'un seuil de ressemblance.
    public static func related(to document: RecallDocument, in documents: [RecallDocument], now: Date,
                               semanticScores: [UUID: Double] = [:], limit: Int = 3) -> [RecallHit] {
        let query = RecallQuery.about(([document.title, document.text]).joined(separator: " "))
        let others = documents.filter { $0.id != document.id && $0.status != .trashed }
        return find(others, for: query, now: now, semanticScores: semanticScores, expansions: [:], limit: limit)
            .filter { $0.score >= relatedThreshold }
    }

    /// Une note liée doit ressembler davantage qu'une simple réponse possible.
    static let relatedThreshold = 0.6

    // MARK: Lister (période, type)

    static func list(_ documents: [RecallDocument], for query: RecallQuery, now: Date, limit: Int) -> [RecallHit] {
        let openOnly = query.periodMeansDue || query.kinds.contains(.task)
        let kept = documents.filter { document in
            if openOnly && document.status == .archived { return false }
            if !query.kinds.isEmpty, !query.kinds.contains(document.kind ?? .other) { return false }
            if let period = query.period, !matches(document, period: period, due: query.periodMeansDue) { return false }
            return true
        }
        let sorted: [RecallDocument]
        if query.periodMeansDue {
            sorted = kept.sorted { ($0.dueAt ?? .distantFuture, $1.capturedAt) < ($1.dueAt ?? .distantFuture, $0.capturedAt) }
        } else {
            sorted = kept.sorted { $0.capturedAt > $1.capturedAt }
        }
        return sorted.prefix(limit).map { RecallHit(document: $0, score: 1) }
    }

    /// Échéance dans la période ; sans échéance, le jour où la note a été prise.
    static func matches(_ document: RecallDocument, period: DateInterval, due: Bool) -> Bool {
        if let dueAt = document.dueAt, period.contains(dueAt), dueAt < period.end { return true }
        let captured = period.contains(document.capturedAt) && document.capturedAt < period.end
        return due ? (document.dueAt == nil && captured) : captured
    }

    // MARK: Retrouver (mots, sens)

    static func find(_ documents: [RecallDocument], for query: RecallQuery, now: Date, semanticScores: [UUID: Double],
                     expansions: [String: [String]], limit: Int) -> [RecallHit] {
        let indexed = documents.map { IndexedDocument($0) }
        let related = Dictionary(uniqueKeysWithValues: query.keywords.map { keyword in
            (keyword, RecallSynonyms.related(to: keyword) + (expansions[keyword] ?? []).map(RecallText.normalize))
        })
        var matchScores: [UUID: [String: Double]] = [:]
        var documentFrequency: [String: Int] = [:]
        for document in indexed {
            for keyword in query.keywords {
                let score = document.match(keyword, related: related[keyword] ?? [])
                guard score > 0 else { continue }
                matchScores[document.document.id, default: [:]][keyword] = score
                documentFrequency[keyword, default: 0] += 1
            }
        }
        // Un mot qu'aucune note ne contient n'aide pas à départager : il est ignoré (pas de pénalité).
        let informative = query.keywords.filter { (documentFrequency[$0] ?? 0) > 0 }
        let count = Double(max(documents.count, 1))
        let weights = Dictionary(uniqueKeysWithValues: informative.map { keyword in
            (keyword, log(1 + count / Double(1 + (documentFrequency[keyword] ?? 0))))
        })
        let totalWeight = weights.values.reduce(0, +)

        var hits: [RecallHit] = []
        for document in documents {
            var lexical = 0.0
            if totalWeight > 0, let scores = matchScores[document.id] {
                lexical = informative.reduce(0) { $0 + (weights[$1] ?? 0) * (scores[$1] ?? 0) } / totalWeight
            }
            let similarity = semanticScores[document.id] ?? 0
            let meaning = max(0, similarity - 0.6) * 2.5
            // Ni les mots ni un sens très proche ne répondent : la note n'est pas proposée, quelles que soient sa date
            // ou son type (une vague ressemblance ne suffit jamais).
            guard lexical > 0 || similarity >= 0.7 else { continue }
            var score = lexical + meaning
            if !query.kinds.isEmpty { score += query.kinds.contains(document.kind ?? .other) ? 0.25 : -0.35 }
            if let period = query.period { score += matches(document, period: period, due: query.periodMeansDue) ? 0.3 : -0.4 }
            if document.status == .archived { score -= 0.2 }
            score += 0.1 * exp(-max(0, now.timeIntervalSince(document.capturedAt)) / (30 * 86_400))
            if score >= threshold { hits.append(RecallHit(document: document, score: score)) }
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Mots d'une note, prêts à comparer.
    struct IndexedDocument {
        let document: RecallDocument
        let strong: Set<String>
        let other: Set<String>

        init(_ document: RecallDocument) {
            self.document = document
            strong = Set(RecallText.tokens(([document.title] + document.categories + document.tags).joined(separator: " ")))
            other = Set(RecallText.tokens(document.text))
        }

        /// Meilleure correspondance d'un mot de la question : exacte (titre et dossier comptent plus), forme
        /// voisine (pluriel, début commun), ou mot proche (« resto » pour « restaurant »).
        func match(_ keyword: String, related: [String]) -> Double {
            var best = 0.0
            for (words, bonus) in [(strong, 0.3), (other, 0.0)] {
                for word in words {
                    if RecallText.sameWord(word, keyword) {
                        best = max(best, 1.0 + bonus)
                    } else if RecallText.sharePrefix(word, keyword) {
                        best = max(best, 0.7)
                    } else if related.contains(where: { RecallText.sameWord(word, $0) }) {
                        best = max(best, 0.75 + bonus * 0.5)
                    }
                }
            }
            return best
        }
    }
}

/// Réponse sans modèle d'IA : elle dit seulement ce qui a été trouvé.
public enum RecallAnswer {
    public static let nothingFound = "Je ne trouve rien là-dessus dans ta mémoire."

    public static func fallback(for query: RecallQuery, hits: [RecallHit]) -> String {
        guard let first = hits.first else { return nothingFound }
        let titles = hits.prefix(3).map { "« \($0.document.title) »" }
        if query.intent == .find {
            return hits.count == 1
                ? "J'ai trouvé ceci : « \(first.document.title) »."
                : "J'ai trouvé \(hits.count) notes qui peuvent correspondre. La plus proche : « \(first.document.title) »."
        }
        if hits.count == 1 { return "Une seule note : « \(first.document.title) »." }
        let listed = titles.count > 1 ? titles.dropLast().joined(separator: ", ") + " et " + titles.last! : titles[0]
        return "\(hits.count) notes : \(listed)\(hits.count > 3 ? "…" : ".")"
    }
}

// MARK: - Texte

enum RecallText {
    /// Minuscules, sans accents, ponctuation remplacée par des espaces.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "fr_CA")).lowercased()
        let spaced = String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })
        return spaced.split(separator: " ").joined(separator: " ")
    }

    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    /// Forme dite (accents compris) de chaque mot normalisé, retrouvée dans le texte d'origine.
    static func spoken(_ keywords: [String], in original: String) -> [String] {
        var forms: [String: String] = [:]
        let lowered = String(original.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
        for word in lowered.split(separator: " ").map(String.init) {
            let key = normalize(word)
            if forms[key] == nil { forms[key] = word }
        }
        return keywords.map { forms[$0] ?? $0 }
    }

    /// Même mot, au pluriel ou au féminin près.
    static func sameWord(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || stem(lhs) == stem(rhs)
    }

    /// Début commun d'au moins 5 lettres (« appeler » et « appelé », « assurance » et « assureur »).
    static func sharePrefix(_ lhs: String, _ rhs: String) -> Bool {
        lhs.count >= 5 && rhs.count >= 5 && lhs.prefix(5) == rhs.prefix(5)
    }

    static func stem(_ word: String) -> String {
        var result = word
        if result.count > 3, let last = result.last, last == "s" || last == "x" { result.removeLast() }
        if result.count > 4, result.hasSuffix("e") { result.removeLast() }
        return result
    }

    static func contains(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? Regex(pattern) else { return false }
        return text.firstMatch(of: regex) != nil
    }

    /// Mots qui ne portent pas le sujet de la question : mots outils, verbes de mémoire (« j'avais dit »), types et
    /// moments (déjà compris à part).
    static let stopwords: Set<String> = [
        // Mots outils
        "le", "la", "les", "l", "un", "une", "des", "du", "de", "d", "au", "aux", "a", "et", "ou", "mais", "donc", "ni", "car",
        "que", "qu", "qui", "quoi", "quel", "quelle", "quels", "quelles", "quand", "comment", "pourquoi", "est", "ce", "c",
        "cet", "cette", "ces", "se", "s", "sa", "son", "ses", "mon", "ma", "mes", "ton", "ta", "tes", "notre", "nos", "votre",
        "vos", "leur", "leurs", "je", "j", "me", "m", "moi", "tu", "te", "t", "toi", "il", "ils", "elle", "elles", "on", "nous",
        "vous", "lui", "y", "en", "ne", "n", "pas", "plus", "rien", "tout", "tous", "toute", "toutes", "tres", "trop", "bien",
        "ca", "cela", "ceci", "par", "pour", "avec", "sans", "sur", "sous", "dans", "chez", "vers", "entre", "apres", "avant",
        "depuis", "pendant", "concernant", "propos", "sujet", "si", "alors", "aussi", "juste", "vraiment", "genre", "deja",
        "encore", "nom", "pis",
        // Verbes de mémoire et de demande
        "ai", "as", "avait", "avais", "avions", "aviez", "avaient", "avoir", "eu", "eue", "etait", "etais", "ete", "etre",
        "suis", "es", "sont", "sommes", "fait", "faites", "fais", "faisait", "dit", "dis", "disais", "dire", "parle", "parler",
        "parlais", "parlait", "mentionne", "mentionnee", "mentionnes", "mentionnees", "mentionner", "note", "notee", "notees",
        "noter", "enregistre", "enregistree", "enregistrees", "enregistres", "enregistrer", "pense", "pensais", "penser",
        "souviens", "souvenir", "rappelle", "rappeler", "rappelles", "semble", "sais", "savais", "savoir", "retrouve",
        "retrouver", "retrouves", "trouve", "trouver", "cherche", "chercher", "montre", "montrer", "donne", "donner", "peux",
        "pouvais", "veux", "voulais", "vouloir", "voudrais", "vais", "allais", "va", "aller", "chose", "choses", "truc",
        "trucs", "affaire", "affaires", "quelque", "quelques", "resume", "resumer", "resumes", "recapitule", "recapituler",
        "notes", "pensee", "pensees", "memoire", "memoires", "souvenirs", "celles", "ceux", "celle", "celui", "lesquelles",
        "lesquels", "meme",
        // Types et projets dans le temps (compris à part)
        "tache", "taches", "idee", "idees", "rendez", "rdv", "decision", "decisions", "rappel", "rappels", "prevu", "prevue",
        "prevus", "prevues", "faire", "dois", "devais", "doit", "devrais", "faut", "fallait", "agenda",
        // Moments (compris à part)
        "jour", "jours", "semaine", "semaines", "mois", "annee", "temps", "fois", "matin", "soir", "heure", "heures",
        "aujourd", "hui", "hier", "demain", "autre", "derniere", "dernier", "passee", "passe", "prochaine", "prochain",
        "recemment", "dernierement", "longtemps", "bout",
        // Anglais
        "the", "an", "of", "to", "in", "on", "for", "with", "about", "what", "which", "who", "when", "where", "how", "did",
        "do", "does", "i", "my", "you", "your", "it", "is", "was", "were", "be", "have", "had", "has", "that", "this", "these",
        "those", "there", "some", "something", "thing", "things", "anything", "find", "remember", "recall", "tell", "show",
        "any", "said", "say", "mentioned", "task", "tasks", "idea", "ideas", "appointment", "appointments", "meeting",
        "meetings", "reminder", "reminders", "planned", "need", "today", "tomorrow", "yesterday", "week", "month", "ago",
        "last", "next", "recently", "lately", "summarize", "summary", "please",
    ]
}

/// Mots proches connus (français du Québec et anglais), sans accents.
enum RecallSynonyms {
    static let groups: [[String]] = [
        ["voiture", "auto", "automobile", "char", "vehicule", "car", "camion", "pickup"],
        ["restaurant", "resto", "bistro", "brasserie", "souper"],
        ["application", "app", "appli", "logiciel"],
        ["travail", "job", "emploi", "boulot", "ouvrage", "bureau", "work", "shift"],
        ["argent", "finance", "banque", "paie", "salaire", "budget", "money", "facture"],
        ["medecin", "docteur", "clinique", "sante", "doctor", "hopital"],
        ["epicerie", "courses", "achats", "magasinage", "groceries"],
        ["sport", "gym", "entrainement", "workout", "exercice"],
        ["maison", "appartement", "appart", "logement", "condo", "home"],
        ["probleme", "souci", "panne", "bris", "trouble", "issue"],
        ["assurance", "assureur", "insurance"],
        ["telephone", "cell", "cellulaire", "phone"],
        ["film", "films", "serie", "movie", "netflix"],
        ["voyage", "vacances", "trip", "voyages"],
        // « C'est quand la fête à Amina ? » trouve « l'anniversaire d'Amina » (P31).
        ["fete", "anniversaire", "anniv", "birthday", "bday"],
    ]

    static func related(to keyword: String) -> [String] {
        groups.filter { group in group.contains { RecallText.sameWord($0, keyword) } }
            .flatMap { $0 }
            .filter { !RecallText.sameWord($0, keyword) }
    }
}

/// Périodes dites dans une question (« cette semaine », « il y a quelques jours »…).
enum RecallPeriods {
    struct Found {
        let interval: DateInterval?
        let range: Range<String.Index>
    }

    static let numbers: [String: Int] = [
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10,
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    ]

    static func find(in text: String, now: Date, calendar: Calendar) -> Found? {
        let day = 86_400.0
        func interval(of component: Calendar.Component, shiftedBy days: Int) -> DateInterval? {
            guard let date = calendar.date(byAdding: .day, value: days, to: now) else { return nil }
            return calendar.dateInterval(of: component, for: date)
        }
        func monthInterval(shiftedBy months: Int) -> DateInterval? {
            guard let date = calendar.date(byAdding: .month, value: months, to: now) else { return nil }
            return calendar.dateInterval(of: .month, for: date)
        }
        let last = { (days: Double) in DateInterval(start: now.addingTimeInterval(-days * day), end: now) }

        // Du plus précis au plus vague ; la première expression trouvée l'emporte.
        let rules: [(String, (Regex<AnyRegexOutput>.Match) -> DateInterval??)] = [
            (#"\b(il y a (quelque temps|longtemps|un bout)|a while ago|long ago)\b"#, { _ in .some(nil) }),
            (#"\b(il y a (quelques|plusieurs) jours|a few days ago|l autre jour|the other day|ces derniers jours)\b"#,
             { _ in last(10) }),
            (#"\b(il y a (quelques|plusieurs) semaines|a few weeks ago)\b"#, { _ in last(42) }),
            (#"\bil y a (\d+|un|une|deux|trois|quatre|cinq|six|sept|huit|neuf|dix) (jours?|semaines?|mois)\b"#, { match in
                guard let count = match.output[1].substring.flatMap({ Int($0) ?? numbers[String($0)] }),
                      let unit = match.output[2].substring else { return nil }
                let size = unit.hasPrefix("jour") ? day : unit.hasPrefix("semaine") ? 7 * day : 30 * day
                return DateInterval(start: now.addingTimeInterval(-Double(count + 1) * size),
                                    end: now.addingTimeInterval(-Double(max(0, count - 1)) * size))
            }),
            (#"\b(\d+|one|two|three|four|five) (days?|weeks?|months?) ago\b"#, { match in
                guard let count = match.output[1].substring.flatMap({ Int($0) ?? numbers[String($0)] }),
                      let unit = match.output[2].substring else { return nil }
                let size = unit.hasPrefix("day") ? day : unit.hasPrefix("week") ? 7 * day : 30 * day
                return DateInterval(start: now.addingTimeInterval(-Double(count + 1) * size),
                                    end: now.addingTimeInterval(-Double(max(0, count - 1)) * size))
            }),
            (#"\b(apres demain|day after tomorrow)\b"#, { _ in interval(of: .day, shiftedBy: 2) }),
            (#"\b(demain|tomorrow)\b"#, { _ in interval(of: .day, shiftedBy: 1) }),
            (#"\b(hier|yesterday)\b"#, { _ in interval(of: .day, shiftedBy: -1) }),
            (#"\b(aujourd hui|today|ce matin|ce soir|tonight|this morning|this evening)\b"#,
             { _ in interval(of: .day, shiftedBy: 0) }),
            (#"\b((la )?semaine (passee|derniere)|last week)\b"#, { _ in interval(of: .weekOfYear, shiftedBy: -7) }),
            (#"\b((la )?semaine prochaine|next week)\b"#, { _ in interval(of: .weekOfYear, shiftedBy: 7) }),
            (#"\b(cette semaine|this week)\b"#, { _ in interval(of: .weekOfYear, shiftedBy: 0) }),
            (#"\b((le )?mois (passe|dernier)|last month)\b"#, { _ in monthInterval(shiftedBy: -1) }),
            (#"\b((le )?mois prochain|next month)\b"#, { _ in monthInterval(shiftedBy: 1) }),
            (#"\b(ce mois ci|ce mois|this month)\b"#, { _ in monthInterval(shiftedBy: 0) }),
            (#"\b(recemment|dernierement|recents?|recentes?|derniers|dernieres|recently|lately|latest|recent)\b"#,
             { _ in last(14) }),
        ]
        for (pattern, make) in rules {
            guard let regex = try? Regex(pattern), let match = text.firstMatch(of: regex) else { continue }
            guard let result = make(match) else { continue }
            return Found(interval: result, range: match.range)
        }
        return nil
    }
}
