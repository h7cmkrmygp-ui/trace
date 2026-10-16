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
public enum LinguisticGuards {
    public static func inspect(_ excerpt: String) -> LinguisticSignals { LinguisticSignals() }
}

/// F03 — la phrase exprime-t-elle vraiment l'opération que propose l'intention (acheter, recevoir, offrir, ajouter,
/// cocher, retirer) ? Une proximité de mots ou un nom de dossier ne suffit pas.
public enum OperationEvidence {
    public static func supports(_ intent: IntentType, excerpt: String, listName: String?) -> Bool { true }
}

/// F03 — le rôle d'un dossier dont le nom dit une action (achats, à faire, listes, souhaits) plutôt qu'un sujet.
public enum FolderRole: Sendable, Equatable {
    case purchases, tasks, lists, wishes

    public static func role(of path: [String]) -> FolderRole? { nil }

    /// L'intention convient-elle à un dossier de ce rôle ?
    public func accepts(_ intent: IntentType?) -> Bool { true }
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
    /// Ce qui a été refusé et pourquoi (montré dans « Pourquoi ce dossier »).
    public var review: String?

    public init(operations: [Operation], keepsFolder: Bool = true, review: String? = nil) {
        self.operations = operations
        self.keepsFolder = keepsFolder
        self.review = review
    }
}

/// F03, F04 — de la pensée validée au plan d'actions. Les analyseurs de listes ne font que fournir les choses et le nom
/// d'une liste quand l'intention l'autorise déjà.
public enum ActionPlanner {
    public static func plan(_ thought: ValidThought) -> ActionPlan { ActionPlan(operations: [.note(thought.kind)]) }
}
