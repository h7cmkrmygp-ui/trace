import Foundation

/// Règle anti-invention : seule une pensée dont l'extrait figure dans le texte est gardée, et tout est nettoyé.
public enum AnalysisValidator {
    public static let maxTags = 3
    public static let maxTagLength = 30
    public static let maxCategoryLength = 40
    /// Longueur maximale de la raison du choix de catégorie (P32).
    public static let maxReasonLength = 200
    /// Personnes, et lieux, gardés au plus par pensée.
    public static let maxNames = 4
    /// P41 — choses gardées au plus par liste, et leur longueur.
    public static let maxListItems = 20
    public static let maxListItemLength = 60

    /// P33 — le dossier des fêtes quand le propriétaire n'en a pas encore (le classement reprend le sien s'il existe).
    public static let birthdayFolder = "Anniversaires"
    public static let birthdayFolderDescription = "Les fêtes des personnes de ta vie, rappelées chaque année."

    /// Pensées valides, dans l'ordre. Lève `invalidOutput` s'il n'en reste aucune.
    /// - Parameter recent: P42 — la dictée précédente, pour comprendre « elle », « cette liste », « ce projet ».
    public static func validate(_ analysis: ThoughtAnalysis, against text: String,
                                recent: RecentContext? = nil) throws -> [ValidThought] {
        let alone = analysis.thoughts.count == 1
        var valid: [ValidThought] = []
        // Dans une même dictée, « elle » ou « la même liste » renvoient d'abord à la phrase d'avant (P42).
        var context = recent
        for thought in analysis.thoughts {
            guard let checked = validate(thought, against: text, alone: alone, recent: context) else { continue }
            valid.append(checked)
            var next = context ?? RecentContext()
            if !checked.people.isEmpty { next.people = checked.people }
            if let list = checked.listName { next.lists = [list] }
            context = next
        }
        guard !valid.isEmpty else { throw AnalyzerError.invalidOutput }
        return valid
    }

    /// - Parameters:
    ///   - alone: seule pensée de la note (un extrait incomplet se relit alors avec la note entière).
    ///   - recent: P42 — ce qui vient d'être dit : « elle », « cette liste », « ce projet » n'y renvoient que sans ambiguïté.
    static func validate(_ thought: AnalyzedThought, against text: String, alone: Bool = false,
                         recent: RecentContext? = nil) -> ValidThought? {
        var excerpt = thought.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !TextNormalizer.containsPhrase(excerpt, in: text) {
            // L'IA a pu écrire « puis » pour « pis » ou corriger une faute : on reprend les vrais mots du passage.
            guard let passage = closestPassage(to: excerpt, in: text) else { return nil }
            excerpt = passage
        }

        let proposedTitle = thought.title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let title = TitleMaker.fallbackTitle(from: proposedTitle.isEmpty ? excerpt : proposedTitle)

        let summary = thought.summary?.trimmingCharacters(in: .whitespacesAndNewlines)

        var path = categoryPath(category: thought.category, subcategory: thought.subcategory)
        // Un suivi (« Santé › Poids ») ne reçoit que sa mesure : sinon la note reste « À classer » plutôt que mal rangée (P31).
        if !MeasurementFolders.accepts(path, text: excerpt) { path = [] }
        var kind = thought.kind
        var reason = path.isEmpty ? nil : cleanReason(thought.categoryReason)
        // « Pour ce projet, il faut aussi… » : le seul projet de la dictée précédente (P42).
        if ContextReferences.refersToAProject(excerpt), let recent, let folder = projectFolder(in: recent) {
            path = categoryPath(category: folder, subcategory: nil)
            reason = "« Ce projet » : celui de ta note d'il y a \(recent.minutesAgo) min, rangée dans « \(folder) »."
        }
        // Une note qui dit seulement une fête (P33) : une chose à retenir, dans le dossier des fêtes, sans échéance
        // (la page de la personne la rappelle chaque année). Une tâche autour d'une fête reste une tâche.
        let birthdayText = BirthdayParser.isOnlyABirthday(excerpt) ? excerpt
            : alone && BirthdayParser.isOnlyABirthday(text) ? text : nil
        let birthday = birthdayText.flatMap(BirthdayParser.parse)
        if let birthday {
            kind = .info
            path = [birthdayFolder]
            reason = birthdayReason(birthday)
        }

        var seen = Set<String>()
        var tags: [String] = []
        for raw in thought.tags {
            guard let tag = cleanName(raw, maxLength: maxTagLength),
                  seen.insert(TextNormalizer.normalizedName(tag)).inserted else { continue }
            tags.append(tag)
            if tags.count == maxTags { break }
        }

        // P41 — une liste n'est gardée qu'avec au moins une chose vraiment dite.
        var items = listItems(thought.listItems, in: text)
        var listName = items.isEmpty ? nil : thought.listName.flatMap(cleanListName)
        // « Ajoute un livre à cette liste » : la seule liste dont on vient de parler (P42).
        if ContextReferences.refersToAList(excerpt), let list = recent?.lists.onlyOne {
            if items.isEmpty { items = ContextReferences.listItems(in: excerpt) ?? [] }
            if !items.isEmpty { listName = list }
        }

        // Une personne ou un lieu n'est gardé que s'il est nommé dans le texte (4 de chaque au plus). « Elle », « lui »,
        // « sa fête » sans nom : la seule personne dont on vient de parler (P42) ; plusieurs, aucun lien n'est inventé.
        var people = EntityName.clean(thought.people, in: text, limit: maxNames)
        if people.isEmpty, ContextReferences.refersToSomeone(excerpt), let person = recent?.people.onlyOne {
            people = [person]
        }

        // Une date n'est gardée que si l'expression figure dans le texte : l'IA relève, elle n'invente pas.
        let dates = thought.mentionedDates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && TextNormalizer.containsPhrase($0, in: text) }
        // « Je dois acheter du lait demain » : une tâche ou un rendez-vous daté garde son échéance et son rappel (P41).
        if kind == .task || kind == .appointment, !dates.isEmpty { listName = nil }

        let range = (text as NSString).range(of: excerpt)
        let found = range.location != NSNotFound
        return ValidThought(
            title: title,
            summary: (summary?.isEmpty ?? true) ? nil : summary,
            excerpt: excerpt,
            spanStart: found ? range.location : nil,
            spanEnd: found ? range.location + range.length : nil,
            kind: kind,
            tags: tags,
            categoryPath: path,
            mentionedDates: dates,
            // Le dossier des fêtes a sa propre description (celle de l'IA parlait d'un autre dossier).
            categoryDescription: birthday != nil ? birthdayFolderDescription : thought.categoryDescription
                .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)) }
                .flatMap { $0.isEmpty ? nil : $0 },
            people: people,
            places: EntityName.clean(thought.places, in: text, limit: maxNames),
            // La raison du choix suit le chemin : un chemin refusé n'a plus de raison (P32).
            categoryReason: reason,
            birthdayOf: birthday?.person,
            listName: listName,
            listItems: listName == nil ? [] : items)
    }

    /// P42 — le dossier dont parle « ce projet » : le seul dossier de la dictée précédente, ou le seul qui est un projet.
    static func projectFolder(in recent: RecentContext) -> String? {
        if let only = recent.folders.onlyOne { return only }
        return recent.folders.filter {
            let form = TextNormalizer.normalizedName($0)
            return form.contains("projet") || form.contains("project")
        }.onlyOne
    }

    /// « Liste de Souhaits » → « souhaits » (la carte ajoute « Liste de ») ; nil si vide.
    static func cleanListName(_ raw: String) -> String? {
        guard let name = cleanName(ListResolver.clean(raw), maxLength: maxCategoryLength) else { return nil }
        // Une majuscule de début de phrase tombe ; un sigle ou un nom propre en début de nom reste (« NHL »).
        let startsASentence = name.dropFirst().first.map { $0.isLowercase } ?? true
        return startsASentence ? name.prefix(1).lowercased() + name.dropFirst() : name
    }

    /// Les choses d'une liste, nettoyées (une majuscule, sans doublon, 20 au plus) ; une chose n'est gardée que si la moitié
    /// au moins de ses mots porteurs de sens sont dans le texte : l'IA range ce qui est dit, elle n'ajoute rien.
    static func listItems(_ raw: [String], in text: String) -> [String] {
        let said = Set(meaningfulWords(text).map(TextNormalizer.singularize))
        var seen = Set<String>()
        var items: [String] = []
        for proposed in raw {
            let collapsed = proposed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?-–•☐☑ "))
            guard !collapsed.isEmpty, collapsed.count <= maxListItemLength,
                  seen.insert(TextNormalizer.normalizedName(collapsed)).inserted else { continue }
            let words = Set(meaningfulWords(collapsed).map(TextNormalizer.singularize))
            let grounded = words.isEmpty ? TextNormalizer.containsPhrase(collapsed, in: text)
                : words.filter(said.contains).count * 2 >= words.count
            guard grounded else { continue }
            items.append(collapsed.prefix(1).uppercased() + collapsed.dropFirst())
            if items.count == maxListItems { break }
        }
        return items
    }

    /// « La fête d'Inès, le 13 octobre : une date à retenir, rangée avec les anniversaires ; Engram te la rappelle chaque
    /// année. » (P33, affichée dans « Pourquoi ce dossier »).
    public static func birthdayReason(_ birthday: ParsedBirthday) -> String {
        let day = birthday.day == 1 ? "1er" : "\(birthday.day)"
        let feast = BirthdayPlanner.feast(birthday.person)
        return "\(feast.prefix(1).uppercased() + feast.dropFirst()), le \(day) \(WeeklyReviewText.months[birthday.month - 1]) :"
            + " une date à retenir, rangée avec les anniversaires ; Engram te la rappelle chaque année."
    }

    /// Une phrase sur une ligne, espaces réduits, coupée à `maxReasonLength` ; nil si vide.
    static func cleanReason(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : String(collapsed.prefix(maxReasonLength))
    }

    /// Chemin de 0 à 2 niveaux. Un modèle peut renvoyer « Automobile › Corolla » dans un seul champ :
    /// on découpe sur « › », « > » et « / », et on retire un parent répété dans la sous-catégorie.
    static func categoryPath(category: String, subcategory: String?) -> [String] {
        func parts(_ raw: String?) -> [String] {
            guard let raw else { return [] }
            return raw.components(separatedBy: CharacterSet(charactersIn: "›>/"))
                .compactMap { cleanName($0, maxLength: maxCategoryLength) }
        }
        let categoryParts = parts(category)
        guard !categoryParts.isEmpty else { return [] }
        var path: [String] = []
        for part in categoryParts + parts(subcategory) {
            let key = TextNormalizer.normalizedName(part)
            if path.contains(where: { TextNormalizer.normalizedName($0) == key }) { continue }
            path.append(part)
        }
        return Array(path.prefix(2))
    }

    /// Mots-outils ignorés pour comparer un extrait à un passage.
    static let functionWords: Set<String> = [
        "les", "des", "une", "pour", "que", "qui", "dans", "sur", "avec", "pas", "mon", "mes", "ton", "tes", "son", "ses",
        "nos", "vos", "leur", "est", "the", "and", "for", "with",
    ]

    static func contentWords(_ text: String) -> Set<String> {
        Set(TextNormalizer.matchingForm(text).split(separator: " ").map(String.init)
            .filter { $0.count >= 3 && !functionWords.contains($0) })
    }

    /// Le passage du texte (une proposition, deux qui se suivent, ou toute la note) qui contient au moins les trois quarts des mots
    /// porteurs de sens de l'extrait, sans être beaucoup plus long. nil si aucun ne correspond : l'extrait est inventé.
    static func closestPassage(to excerpt: String, in text: String) -> String? {
        let wanted = contentWords(excerpt)
        guard wanted.count >= 2 else { return nil }
        let source = text as NSString
        var pieces: [NSRange] = []
        var start = 0
        let separators = CharacterSet(charactersIn: ".!?;,\n")
        for index in 0...source.length {
            let atEnd = index == source.length
            if atEnd || separators.contains(UnicodeScalar(source.character(at: index)) ?? " ") {
                let raw = source.substring(with: NSRange(location: start, length: index - start))
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let offset = (raw as NSString).range(of: trimmed).location
                    pieces.append(NSRange(location: start + offset, length: (trimmed as NSString).length))
                }
                start = index + 1
            }
        }
        var candidates = pieces
        if pieces.count > 1 {
            for index in 0..<(pieces.count - 1) {
                candidates.append(NSRange(location: pieces[index].location,
                                          length: NSMaxRange(pieces[index + 1]) - pieces[index].location))
            }
        }
        // Toute la note (un seul sujet en plusieurs morceaux).
        if pieces.count > 2, let first = pieces.first, let last = pieces.last {
            candidates.append(NSRange(location: first.location, length: NSMaxRange(last) - first.location))
        }
        var best: (passage: String, score: Double)?
        for range in candidates {
            let passage = source.substring(with: range)
            let words = contentWords(passage)
            guard !words.isEmpty else { continue }
            let shared = Double(wanted.intersection(words).count)
            let recall = shared / Double(wanted.count)
            let precision = shared / Double(words.count)
            guard recall >= 0.75, precision >= 0.5 else { continue }
            if recall + precision > best?.score ?? 0 { best = (passage, recall + precision) }
        }
        return best?.passage
    }

    /// P35, F05 — la partie de la dictée qu'aucun extrait ne reprend, mesurée par passages (voir `uncoveredPassages`) ;
    /// nil s'il ne reste rien qui dise quelque chose.
    public static func leftover(of text: String, excerpts: [String]) -> String? {
        let thoughts = excerpts.map { excerpt in
            ValidThought(title: excerpt, summary: nil, excerpt: excerpt, spanStart: nil, spanEnd: nil, kind: .other, tags: [],
                         categoryPath: [], mentionedDates: [])
        }
        let passages = uncoveredPassages(of: text, thoughts: thoughts)
        return passages.isEmpty ? nil : passages.map(\.text).joined(separator: ". ")
    }

    /// Mots qui n'apportent rien au sujet : hésitations, liaisons, petites formules de dictée.
    static let fillerWords: Set<String> = [
        "euh", "hum", "okay", "genre", "ben", "bon", "tse", "mettons", "style", "comme", "alors", "donc", "aussi", "pis",
        "faut", "faudrait", "rappelle", "voila", "bref", "enfin", "ouin", "ouais", "oui", "non",
    ]

    /// Les mots porteurs de sens d'un texte, dans l'ordre (pour mesurer ce que les extraits reprennent).
    static func meaningfulWords(_ text: String) -> [String] {
        TextNormalizer.matchingForm(text).split(separator: " ").map(String.init)
            .filter { $0.count >= 3 && !functionWords.contains($0) && !fillerWords.contains($0) }
    }

    /// Les propositions d'un texte (coupé sur . ! ? ; , et les retours à la ligne), sans espaces autour.
    static func clauses(of text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?;,\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// P35 — l'IA a reformulé au lieu de recopier (aucun extrait ne se retrouve) : la dictée entière devient une seule note,
    /// avec le titre, le type et le dossier choisis par l'IA.
    public static func salvage(_ analysis: ThoughtAnalysis, against text: String) -> ValidThought? {
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !whole.isEmpty,
              let first = analysis.thoughts.first(where: { !$0.category.trimmingCharacters(in: .whitespaces).isEmpty })
                ?? analysis.thoughts.first else { return nil }
        // Les dates, étiquettes, personnes et lieux de toutes les pensées (chacun est revérifié dans le texte).
        var thought = first
        thought.excerpt = whole
        // Rien d'inventé n'est gardé : pas de texte rédigé, et le titre de l'IA seulement s'il parle de la note.
        thought.summary = nil
        if Set(meaningfulWords(first.title)).isDisjoint(with: meaningfulWords(whole)) { thought.title = "" }
        thought.mentionedDates = analysis.thoughts.flatMap(\.mentionedDates)
        thought.tags = analysis.thoughts.flatMap(\.tags)
        thought.people = analysis.thoughts.flatMap(\.people)
        thought.places = analysis.thoughts.flatMap(\.places)
        return validate(thought, against: whole, alone: true)
    }

    /// Part des mots du texte (0 à 1) que l'on retrouve dans les extraits.
    public static func coverage(of excerpts: [String], in text: String) -> Double {
        let words = TextNormalizer.matchingForm(text).split(separator: " ")
        guard !words.isEmpty else { return 1 }
        let covered = Set(excerpts.flatMap { TextNormalizer.matchingForm($0).split(separator: " ") })
        return Double(words.filter { covered.contains($0) }.count) / Double(words.count)
    }

    /// Espaces réduits ; `nil` si le nom ne contient ni lettre ni chiffre ; coupé à `maxLength`.
    static func cleanName(_ raw: String, maxLength: Int) -> String? {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !TextNormalizer.normalizedName(collapsed).isEmpty else { return nil }
        return String(collapsed.prefix(maxLength))
    }
}

extension AnalysisValidator {
    /// Négations et refus : jamais négligeables dans un passage oublié (« pas Marc »).
    static let negations: Set<String> = ["pas", "ne", "n", "non", "jamais", "plus", "rien", "aucun", "aucune", "sans", "ni"]
    /// Mots qui, seuls, ne disent rien : hésitations, liaisons, pronoms, articles.
    static let coverageIgnored: Set<String> = fillerWords.union(functionWords).union([
        "ok", "ah", "oh", "eh", "hein", "le", "la", "les", "l", "un", "une", "de", "d", "du", "des", "et", "ou", "a", "au",
        "aux", "en", "y", "je", "j", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles", "me", "m", "te", "t", "se",
        "s", "ce", "c", "ca", "qu", "que", "qui", "est", "suis", "ai", "mais", "puis", "ensuite", "apres",
        // Le cadre d'une intention déjà reprise (« Rappeler d'acheter… », « Rappelle-moi de… », « Pense à… ») n'est pas
        // une autre intention.
        "rappeler", "rappelle", "rappelles", "rappel", "moi", "toi", "penser", "pense", "oublie", "oublier", "oublies",
        "dois", "doit", "devrais", "faudra", "falloir", "remind", "need", "must", "should", "to",
    ]).subtracting(negations)

    /// F05 — les passages exacts de la dictée qu'aucune pensée validée ne couvre (positions UTF-16 dans `text`), y compris
    /// une négation ou une commande courte ; les hésitations seules, et les dates, personnes et lieux déjà repris par la
    /// pensée de la même proposition, ne comptent pas. Une pensée sans position est cherchée par son extrait.
    public static func uncoveredPassages(of text: String, thoughts: [ValidThought]) -> [EvidenceSpan] {
        let source = text as NSString
        let covered: [(range: NSRange, details: Set<String>)] = thoughts.compactMap { thought in
            var range: NSRange?
            if let start = thought.spanStart, let end = thought.spanEnd, start >= 0, end <= source.length, start < end {
                range = NSRange(location: start, length: end - start)
            } else {
                let found = source.range(of: thought.excerpt, options: [.caseInsensitive])
                if found.location != NSNotFound, found.length > 0 { range = found }
            }
            guard let range else { return nil }
            let details = Set((thought.mentionedDates + thought.people + thought.places)
                .flatMap { TextNormalizer.matchingForm($0).split(separator: " ").map(String.init) })
            return (range, details)
        }
        var passages: [EvidenceSpan] = []
        for clause in clauseRanges(in: source) {
            let overlapping = covered.filter { NSIntersectionRange($0.range, clause).length > 0 }
            let details = overlapping.reduce(into: Set<String>()) { $0.formUnion($1.details) }
            for piece in subtract(overlapping.map(\.range), from: clause) {
                guard let kept = trimmed(piece, in: source) else { continue }
                let words = TextNormalizer.matchingForm(source.substring(with: kept)).split(separator: " ").map(String.init)
                let meaningful = words.filter { word in
                    !coverageIgnored.contains(word) && !details.contains(word) && (word.count >= 2 || negations.contains(word))
                }
                guard !meaningful.isEmpty else { continue }
                passages.append(EvidenceSpan(start: kept.location, end: NSMaxRange(kept), text: source.substring(with: kept)))
            }
        }
        return passages
    }

    /// Les propositions (coupées sur . ! ? ; et les retours à la ligne), en positions UTF-16.
    static func clauseRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var start = 0
        let separators = CharacterSet(charactersIn: ".!?;\n")
        for index in 0...source.length {
            let atEnd = index == source.length
            if atEnd || (UnicodeScalar(source.character(at: index)).map { separators.contains($0) } ?? false) {
                if index > start { ranges.append(NSRange(location: start, length: index - start)) }
                start = index + 1
            }
        }
        return ranges
    }

    /// Les morceaux d'une proposition qu'aucun des intervalles ne touche.
    static func subtract(_ cuts: [NSRange], from clause: NSRange) -> [NSRange] {
        var pieces = [clause]
        for cut in cuts {
            pieces = pieces.flatMap { piece -> [NSRange] in
                let overlap = NSIntersectionRange(piece, cut)
                guard overlap.length > 0 else { return [piece] }
                var result: [NSRange] = []
                if overlap.location > piece.location {
                    result.append(NSRange(location: piece.location, length: overlap.location - piece.location))
                }
                if NSMaxRange(overlap) < NSMaxRange(piece) {
                    result.append(NSRange(location: NSMaxRange(overlap), length: NSMaxRange(piece) - NSMaxRange(overlap)))
                }
                return result
            }
        }
        return pieces
    }

    /// Sans espaces ni ponctuation aux deux bouts ; nil s'il ne reste rien.
    static func trimmed(_ range: NSRange, in source: NSString) -> NSRange? {
        let skipped = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        func isSkipped(_ index: Int) -> Bool {
            UnicodeScalar(source.character(at: index)).map { skipped.contains($0) } ?? false
        }
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, isSkipped(start) { start += 1 }
        while end > start, isSkipped(end - 1) { end -= 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }
}
