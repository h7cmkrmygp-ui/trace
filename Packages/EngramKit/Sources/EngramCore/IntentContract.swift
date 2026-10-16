import Foundation

/// F03 — ce que la personne veut dire, séparé de l'effet et du dossier : la même pensée peut être une obligation, un
/// achat, un souhait de recevoir, une idée de cadeau, un fait, une préférence, un objectif, un récit, une question, une
/// hypothèse, une citation ou une correction. Seules certaines intentions autorisent une opération de liste.
public enum IntentType: String, Codable, Sendable, CaseIterable {
    /// Une chose à faire (« je dois », « il faut », « rappelle-moi »).
    case obligation
    /// Un rendez-vous ou un événement à un moment donné.
    case appointment
    /// Une chose à acheter ou à se procurer.
    case purchase
    /// Une chose que le propriétaire souhaite recevoir.
    case wish
    /// Une idée de cadeau pour quelqu'un.
    case giftIdea = "gift_idea"
    /// Ajouter à une liste nommée (films à voir, idées de business…).
    case listAdd = "list_add"
    /// Cocher dans une liste (acheté, fait).
    case listCheck = "list_check"
    /// Retirer d'une liste.
    case listRemove = "list_remove"
    case fact
    case preference
    case goal
    case idea
    case decision
    /// Ce qui s'est passé (« j'ai fait », « on est allés »).
    case narrative
    case question
    /// Une supposition ou une condition (« si… », « je pourrais »).
    case hypothesis
    /// Les paroles de quelqu'un d'autre.
    case quote
    /// Une correction d'une chose dite avant (« finalement »).
    case correction

    /// Les intentions qui peuvent écrire dans une liste.
    public var writesToList: Bool {
        switch self {
        case .purchase, .wish, .giftIdea, .listAdd, .listCheck, .listRemove: true
        default: false
        }
    }
}

/// F03 — l'affirmation ou la négation de l'intention (« n'ajoute pas », « je ne dois pas »).
public enum Polarity: String, Codable, Sendable, CaseIterable {
    case affirmative, negative
}

/// F16 — le rôle d'une date dite : quand une chose a lieu, l'échéance, le rappel, un début, une fin, une récurrence.
public enum TemporalRole: String, Codable, Sendable, CaseIterable {
    case event, deadline, reminder, start, end, recurrence, other
}

/// F16 — une date dite, avec son rôle (l'expression exacte de la note, sa résolution vient au stockage).
public struct TemporalMention: Sendable, Hashable, Codable {
    public var role: TemporalRole
    public var phrase: String

    public init(role: TemporalRole, phrase: String) {
        self.role = role
        self.phrase = phrase
    }
}

/// F04 — ce que la phrase elle-même dit de sa forme : une commande niée, une condition, une question, une citation.
public struct LinguisticSignals: Sendable, Equatable {
    public var negated: Bool
    public var conditional: Bool
    public var question: Bool
    public var quoted: Bool

    public init(negated: Bool = false, conditional: Bool = false, question: Bool = false, quoted: Bool = false) {
        self.negated = negated
        self.conditional = conditional
        self.question = question
        self.quoted = quoted
    }

    /// Aucune de ces formes : la phrase peut demander une action effective.
    public var isPlainRequest: Bool { !negated && !conditional && !question && !quoted }
}


/// F04 — lecture déterministe de la forme d'une phrase (complète la compréhension du modèle, ne la remplace pas).
/// Elle repose sur des familles de formes grammaticales (négation, condition, question, discours rapporté), jamais sur un
/// sujet ou un mot de la vie du propriétaire.
public enum LinguisticGuards {
    /// Formules qui ne nient pas la demande : « n'oublie pas de… » rappelle, « pas mal » nuance.
    static let affirmativeIdioms = [
        " n oublie pas ", " oublie pas ", " n oubliez pas ", " oubliez pas ", " ne pas oublier ", " pas oublier ",
        " n oublies pas ", " pas mal ",
    ]
    /// « On n'a plus de lait », « il n'y a pas de café », « je n'en ai plus » : un manque, pas une demande niée.
    static let shortage = [
        #" (?:n )?(?:y )?(?:a|ai|as|avons|avez|ont|reste|restait|restera) (?:plus|pu|pas) (?:de|d|du|des) "#,
        #" (?:n )?(?:y )?en (?:a|ai|as|avons|avez|ont|reste|restait) (?:plus|pu)\s*$"#,
    ]
    static let negators: Set<String> = ["pas", "jamais", "aucun", "aucune", "rien"]
    static let englishNegations = [" don t ", " do not ", " doesn t ", " does not ", " not ", " never ", " no need "]
    static let conditions = [
        #" si (?:je|j|tu|t|on|il|ils|elle|elles|nous|vous|jamais|c|ca|cela|le|la|les|ma|mon|mes|ta|ton|tes|sa|son|ses|un|une|quelqu)\b"#,
        #"^ si "#, #" s ils? (?!te plai|vous plai)"#, " au cas ou ", " a condition ", " pourvu que ", " supposons ",
        " imaginons ", " mettons que ", " if ", " in case ", " suppose ",
    ]
    /// « Peux-tu ajouter… ? » : une demande polie, pas une question sur l'action.
    static let politeRequests = [
        "peux tu ", "pourrais tu ", "tu peux ", "tu pourrais ", "veux tu ", "voudrais tu ", "pouvez vous ", "pourriez vous ",
        "can you ", "could you ", "would you ", "please ",
    ]
    static let reportedSpeech: Set<String> = ["dit", "disait", "disent", "dira", "dixit", "said", "says", "told"]

    public static func inspect(_ excerpt: String) -> LinguisticSignals {
        let tokens = TextNormalizer.words(of: excerpt.replacingOccurrences(of: "’", with: "'"))
        var phrase = " " + tokens.joined(separator: " ") + " "
        for idiom in affirmativeIdioms { phrase = phrase.replacingOccurrences(of: idiom, with: " ") }
        for pattern in shortage { phrase = replacing(pattern, in: phrase) }
        let words = phrase.split(separator: " ").map(String.init)

        let negated = words.contains(where: negators.contains)
            || ((words.contains("ne") || words.contains("n")) && (words.contains("plus") || words.contains("pu")))
            || englishNegations.contains { phrase.contains($0) }

        let spaced = " " + tokens.joined(separator: " ") + " "
        let conditional = conditions.contains { matches($0, spaced) }

        let start = tokens.joined(separator: " ") + " "
        let polite = politeRequests.contains { start.hasPrefix($0) }
        let inverted = invertedQuestion(excerpt)
        let question = !polite && (excerpt.contains("?") || start.hasPrefix("est ce qu") || spaced.contains(" est ce qu")
            || inverted)

        let quoted = tokens.contains(where: reportedSpeech.contains) || spaced.contains(" m a demande ")
            || spaced.contains(" a demande de ") || spaced.contains(" a demande d ")
        return LinguisticSignals(negated: negated, conditional: conditional, question: question, quoted: quoted)
    }

    /// « Dois-je… », « Que feras-tu », « Va-t-il… » ; « rendez-vous » et « rappelle-moi » n'en sont pas.
    static func invertedQuestion(_ text: String) -> Bool {
        let lowered = text.lowercased().replacingOccurrences(of: "’", with: "'")
        guard let regex = try? NSRegularExpression(
            pattern: #"([\p{L}]+)-(?:t-)?(je|tu|il|elle|on|ils|elles)\b"#) else { return false }
        let range = NSRange(lowered.startIndex..., in: lowered)
        for match in regex.matches(in: lowered, range: range) {
            guard let verb = Range(match.range(at: 1), in: lowered) else { continue }
            let word = String(lowered[verb])
            if ["rendez", "peux", "pourrais", "veux", "voudrais", "pouvez", "pourriez"].contains(word) { continue }
            return true
        }
        return false
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text.contains(pattern) }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func replacing(_ pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    }
}

/// F03 — la phrase exprime-t-elle vraiment l'opération que propose l'intention (acheter, recevoir, offrir, ajouter,
/// cocher, retirer) ? Une proximité de mots ou un nom de dossier ne suffit pas : il faut une forme de l'opération
/// elle-même (des familles de verbes et de tournures, aucune liste de sujets).
public enum OperationEvidence {
    static let purchase = [
        "achet", "achat", "il me faut ", "il nous faut ", "me faut ", "nous faut ", "faut du ", "faut de ", "faut des ",
        "faut d ", "besoin d", "plus de ", "pu de ", "plus d ", "manque", "aller chercher ", "passer chercher ",
        "prendre du ", "prendre de ", "prendre des ", "prendre d ", "commander ", "epicerie ", "courses ", "commissions ",
        "buy ", "need ", "pick up ", "grocer", "out of ",
    ]
    /// « J'ai acheté », « I bought » : c'est fait, pas à acheter.
    static let alreadyBought = ["ai achete", "a achete", "avons achete", "ont achete", "bought "]
    static let wish = [
        "recevoir", "qu on m achete", "qu on m offre", "m offrir", "m offre", "me donner", "me donne ", "aimerais avoir",
        "aimerais un ", "aimerais une ", "aimerais des ", "aimerais recevoir", "voudrais un ", "voudrais une ",
        "voudrais des ", "voudrais avoir", "veux un ", "veux une ", "souhait", "tenterait", "pour ma fete",
        "pour mon anniversaire", "pour noel", "wish", "d like ", "i want ",
    ]
    static let gift = ["cadeau", "offrir", "offre ", "donner a ", "donner au ", "ferait plaisir", "gift"]
    static let addVerbs: Set<String> = ["ajoute", "ajouter", "ajoutes", "rajoute", "rajouter", "mets", "mettre", "met",
                                        "inscris", "inscrire", "add", "put"]
    static let check = ["coche", "cocher", "check off", "cross off", "c est fait", "ai pris", "ai achete", "a achete",
                        "avons achete", "bought ", "got "]
    static let remove = ["enleve", "enlever", "retire", "retirer", "efface", "effacer", "supprime", "supprimer", "remove",
                         "delete"]
    static let continuationStarts: Set<String> = ["des", "du", "de", "un", "une", "et", "pis", "puis", "aussi", "plus",
                                                  "also", "and", "some"]
    static let continuationMarks: Set<String> = ["aussi", "encore", "avec", "also", "too"]

    public static func supports(_ intent: IntentType, excerpt: String, listName: String?) -> Bool {
        let tokens = TextNormalizer.words(of: excerpt.replacingOccurrences(of: "’", with: "'"))
        let phrase = " " + tokens.joined(separator: " ") + " "
        func says(_ cues: [String]) -> Bool { cues.contains { phrase.contains(" " + $0) } }
        let command = ListCommandParser.parse(excerpt) != nil
        let mentionsList = tokens.contains("liste") || tokens.contains("listes") || tokens.contains("list")
        // « Des écouteurs aussi », « pis du pain avec ça » : une suite courte, sans verbe d'action, de la liste nommée.
        let continuation = listName != nil && tokens.count <= 6
            && continuationStarts.contains(tokens.first ?? "") && tokens.contains(where: continuationMarks.contains)
        switch intent {
        case .purchase:
            return command || continuation || (says(purchase) && !says(alreadyBought))
        case .wish:
            return says(wish) || continuation
                || (command && listName.map { TextNormalizer.matchingForm($0).contains("souhait") } == true)
        case .giftIdea:
            return says(gift) || continuation
        case .listAdd:
            return command || continuation || (tokens.contains(where: addVerbs.contains) && (mentionsList || listName != nil))
        case .listCheck:
            return ListActionParser.parse(excerpt)?.kind == .check || says(check)
        case .listRemove:
            return ListActionParser.parse(excerpt)?.kind == .remove || (says(remove) && (mentionsList || listName != nil))
        default:
            return false
        }
    }
}

/// F03 — le rôle d'un dossier dont le nom dit une action (achats, à faire, listes, souhaits) plutôt qu'un sujet.
public enum FolderRole: Sendable, Equatable {
    case purchases, tasks, lists, wishes

    static let names: [(FolderRole, Set<String>)] = [
        (.purchases, ["achat", "course", "epicerie", "magasinage", "shopping", "emplette", "commission", "liste d epicerie",
                      "liste de course", "liste d achat"]),
        (.tasks, ["a faire", "tache", "todo", "to do", "chose a faire"]),
        (.wishes, ["souhait", "cadeau", "cadeaux", "liste de souhait", "wishlist", "idee cadeau", "idee de cadeau"]),
        (.lists, ["liste", "list"]),
    ]

    /// Le rôle du dossier le plus précis du chemin qui en a un ; nil pour un dossier de sujet (« Maison »).
    public static func role(of path: [String]) -> FolderRole? {
        for component in path.reversed() {
            let key = TextNormalizer.normalizedName(component)
            if let role = names.first(where: { $0.1.contains(key) })?.0 { return role }
        }
        return nil
    }

    /// L'intention convient-elle à un dossier de ce rôle ? Une intention inconnue ne convient à aucun.
    public func accepts(_ intent: IntentType?) -> Bool {
        guard let intent else { return false }
        switch self {
        case .purchases: return [.purchase, .listAdd, .listCheck, .listRemove].contains(intent)
        case .tasks: return [.obligation, .appointment, .purchase].contains(intent)
        case .lists: return intent.writesToList
        case .wishes: return [.wish, .giftIdea].contains(intent)
        }
    }

    var purpose: String {
        switch self {
        case .purchases: "des achats"
        case .tasks: "des choses à faire"
        case .lists: "des listes"
        case .wishes: "des souhaits et des cadeaux"
        }
    }
}

/// F03 — ce que le magasin a le droit de faire d'une pensée validée : des opérations typées, exclusives, et la raison de ce
/// qui a été refusé.
public struct ActionPlan: Sendable, Equatable {
    public enum Operation: Sendable, Equatable {
        /// Une note (de ce type).
        case note(MemoryKind)
        case appendToList(name: String, items: [String])
        case checkInList(name: String?, items: [String])
        case removeFromList(name: String?, items: [String])
    }

    public var operations: [Operation]
    /// Le dossier proposé par l'IA peut être gardé (son rôle convient à l'intention).
    public var keepsFolder: Bool
    /// Les dates dites peuvent devenir une échéance ou un rappel (pas pour une négation, une hypothèse, une question, une
    /// citation ou un récit).
    public var schedules: Bool
    /// Ce qui a été refusé et pourquoi (montré dans « Pourquoi ce dossier »).
    public var review: String?

    public init(operations: [Operation], keepsFolder: Bool = true, schedules: Bool = true, review: String? = nil) {
        self.operations = operations
        self.keepsFolder = keepsFolder
        self.schedules = schedules
        self.review = review
    }
}

/// F03, F04 — de la pensée validée au plan d'actions. Les analyseurs de listes ne font que fournir les choses et le nom
/// d'une liste quand l'intention l'autorise déjà ; une intention de liste que la phrase ne porte pas est refusée.
public enum ActionPlanner {
    public static func plan(_ thought: ValidThought) -> ActionPlan {
        var intent = thought.intent
        var operations: [ActionPlan.Operation] = []
        var review: String?
        if let proposed = intent, proposed.writesToList {
            let signals = LinguisticGuards.inspect(thought.excerpt)
            if thought.polarity == .negative || signals.negated {
                review = "La phrase dit de ne pas le faire : aucune liste n'est changée."
            } else if signals.conditional {
                review = "La phrase pose une condition : aucune liste n'est changée."
            } else if signals.question {
                review = "La phrase est une question : aucune liste n'est changée."
            } else if signals.quoted {
                review = "La phrase rapporte les paroles de quelqu'un : aucune liste n'est changée."
            } else if !OperationEvidence.supports(proposed, excerpt: thought.excerpt, listName: thought.listName) {
                review = "La phrase ne dit pas \(describe(proposed)) : elle reste une note."
                intent = nil
            } else if let operation = listOperation(proposed, thought) {
                // « Je dois acheter du lait lundi » : une tâche datée garde son échéance (la liste liée vient avec F09).
                if !(proposed == .purchase && !thought.mentionedDates.isEmpty) { operations = [operation] }
            }
        }
        if operations.isEmpty { operations = [.note(kind(for: intent, thought))] }
        var keepsFolder = true
        if let role = FolderRole.role(of: thought.categoryPath), !role.accepts(intent) {
            keepsFolder = false
            let folder = thought.categoryPath.joined(separator: " › ")
            review = review ?? "« \(folder) » est un dossier pour \(role.purpose) : cette pensée n'en est pas une."
        }
        let schedules = thought.polarity != .negative
            && !([.hypothesis, .question, .quote, .narrative] as [IntentType]).contains { $0 == intent }
        return ActionPlan(operations: operations, keepsFolder: keepsFolder, schedules: schedules, review: review)
    }

    /// Les arguments de l'opération : ceux du modèle (déjà ancrés dans le passage), sinon ceux que la phrase donne.
    static func listOperation(_ intent: IntentType, _ thought: ValidThought) -> ActionPlan.Operation? {
        switch intent {
        case .purchase, .wish, .giftIdea, .listAdd:
            if let name = thought.listName, !thought.listItems.isEmpty {
                return .appendToList(name: name, items: thought.listItems)
            }
            if let command = ListCommandParser.parse(thought.excerpt) {
                return .appendToList(name: command.listName, items: command.items)
            }
            return nil
        case .listCheck, .listRemove:
            let kind: ListAction.Kind = intent == .listCheck ? .check : .remove
            var name = thought.listName
            var items = thought.listItems
            if items.isEmpty, let action = ListActionParser.parse(thought.excerpt), action.kind == kind {
                name = action.listName
                items = action.items
            }
            guard !items.isEmpty else { return nil }
            return kind == .check ? .checkInList(name: name, items: items) : .removeFromList(name: name, items: items)
        default:
            return nil
        }
    }

    /// Le type de la note, tiré de l'intention ; une négation n'en fait jamais une tâche ou un rendez-vous.
    static func kind(for intent: IntentType?, _ thought: ValidThought) -> MemoryKind {
        if thought.birthdayOf != nil { return .info }
        guard let intent else { return thought.kind }
        let kind: MemoryKind = switch intent {
        case .obligation, .purchase: .task
        case .appointment: .appointment
        case .giftIdea, .idea, .hypothesis: .idea
        case .fact, .narrative, .quote, .correction, .goal: .info
        case .preference: .preference
        case .decision: .decision
        case .question: .other
        case .wish, .listAdd, .listCheck, .listRemove: thought.kind
        }
        if thought.polarity == .negative, kind == .task || kind == .appointment { return .info }
        return kind
    }

    static func describe(_ intent: IntentType) -> String {
        switch intent {
        case .purchase: "un achat"
        case .wish: "un souhait de recevoir"
        case .giftIdea: "une idée de cadeau"
        case .listAdd: "un ajout à une liste"
        case .listCheck: "une chose faite ou achetée"
        case .listRemove: "une chose à retirer d'une liste"
        default: "cette opération"
        }
    }
}
