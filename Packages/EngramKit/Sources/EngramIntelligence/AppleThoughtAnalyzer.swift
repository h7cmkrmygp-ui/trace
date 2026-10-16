#if canImport(FoundationModels)
import EngramCore
import Foundation
import FoundationModels

// MARK: - Sortie guidée du modèle

@Generable
struct GeneratedThoughts {
    @Guide(description: "One item per distinct subject of the note, in the order they appear. A sentence about a single subject is ONE item.")
    var thoughts: [GeneratedThought]
}

@Generable
struct GeneratedThought {
    @Guide(description: "The exact words of the note that express this item, copied verbatim, never rephrased or translated.")
    var excerpt: String
    @Guide(description: "What the owner means, decided BEFORE the kind, the list and the category. An action on something the owner already has (wash, repair, call, tidy) is an obligation, never a purchase; buying is not receiving.")
    var intent: GeneratedIntent
    @Guide(description: "negative only when the owner says the thing must not happen or did not happen (« n'ajoute pas », « je ne dois pas »); « n'oublie pas de » and « on n'a plus de lait » are affirmative.")
    var polarity: GeneratedPolarity
    @Guide(description: "Who does or wants it: « moi » for the owner, or a name from the note.")
    var subject: String
    @Guide(description: "The action as a French verb (« laver », « appeler »). Empty if none.")
    var action: String
    @Guide(description: "The object of the action, copied from the note (« l'auto »). Empty if none.")
    var object: String
    @Guide(description: "For whom, copied from the note, when it is not the owner. Empty otherwise.")
    var beneficiary: String
    @Guide(description: "Clear, natural French title with only the essential, the action first (« Appeler l'assurance »), English and slang words translated (call → appeler, shift → quart de travail), at most 8 words, never « aujourd'hui » or « demain ». Only what this item's words say.")
    var title: String
    @Guide(description: "The note itself, written in clear French as in Apple Notes, every fact kept, no hesitation, the real date instead of « aujourd'hui » or « demain ». Several steps: one per line starting with « ☐ ». Empty if the title says it all. Never a fact, amount or name the note does not say.")
    var summary: String
    var kind: GeneratedKind
    @Guide(description: "Only for the intents purchase (without a date), wish, giftIdea, listAdd, listCheck and listRemove: the list name in lowercase French without « liste de » (« épicerie », « souhaits », « souhaits d'anniversaire », « cadeaux pour Julie »), an existing list written exactly as given when it is the same list. Empty for anything else.")
    var list: String
    @Guide(description: "The things for that list, one per entry, copied from this item's own words, never an added adjective, quantity or brand. Empty when list is empty.", .maximumCount(20))
    var listItems: [String]
    @Guide(description: "Up to 3 short tags in French.", .maximumCount(3))
    var tags: [String]
    @Guide(description: "Date or time expressions of this item copied from the note, each with its role.")
    var dates: [GeneratedDate]
    @Guide(description: "Written BEFORE choosing the category, one short French sentence for the owner: what this item is really about, then which existing category it truly belongs to and why, judged by what that category contains, or why none fits and a new one is needed.")
    var categoryReason: String
    @Guide(description: "The domain of the owner's life this item belongs to, in French, 1 to 3 words, decided from its meaning. Reuse an existing category name exactly only when the item truly belongs to it; otherwise create a new one. A person's birthday alone goes in the owner's birthdays category, or « Anniversaires ».")
    var category: String
    @Guide(description: "If the category is new: one short French sentence describing what it will contain. Otherwise empty.")
    var categoryDescription: String
    @Guide(description: "Optional precise, lasting topic inside the category, in French, 1 to 3 words, that several notes will share. Reuse an existing subcategory exactly only when the item truly belongs to it. Empty otherwise.")
    var subcategory: String
    @Guide(description: "People this item involves, copied from the note: first names or names (« Julie »), or words for a specific person in the owner's life (« maman », « mon manager »). Never « je », « moi » or « quelqu'un ». Empty if nobody is named.", .maximumCount(4))
    var people: [String]
    @Guide(description: "Specific places this item involves, copied from the note (« Costco », « le gym », « le bureau »). Never a vague place. Empty if none.", .maximumCount(4))
    var places: [String]
}

@Generable
struct GeneratedDate {
    @Guide(description: "The date or time expression, copied verbatim from the note (« demain », « 24 novembre », « tous les lundis »).")
    var phrase: String
    var role: GeneratedDateRole
}

@Generable
enum GeneratedDateRole {
    case reminder, deadline, event, start, end, recurrence, other
}

@Generable
enum GeneratedIntent {
    case obligation, appointment, purchase, wish, giftIdea, listAdd, listCheck, listRemove, fact, preference, goal, idea,
         decision, narrative, question, hypothesis, quote, correction
}

@Generable
enum GeneratedPolarity {
    case affirmative, negative
}

@Generable
enum GeneratedKind {
    case idea, task, appointment, decision, preference, info, other
}

// MARK: - Consignes versionnées

enum AnalysisPrompt {
    static let version = "p50-v1"

    static let instructions = """
        You are the filing engine of a personal memory app running on the owner's iPhone.
        The owner dictates or types notes in Québec French, often mixed with English words. Ignore hesitations (« euh », « hum »).
        Understand the whole meaning of the note before filing it; never file by keywords alone.
        Create one item per distinct subject or action. One sentence can hold two: « faut que je call mon manager demain \
        pour changer mon shift, pis après je vais au gym » is two tasks, « Appeler mon gestionnaire pour changer mon \
        quart de travail » and « Aller au gym », both for « demain ».
        But never split a request about one subject: a reminder about the same thing stays in the same item. In \
        "rappelle-moi de réserver la salle le 24 novembre, rappelle-moi ça demain" there is ONE item, a task, and \
        « demain » is its reminder date.
        Two unrelated subjects, such as "appeler le garage pour les pneus, pis acheter du lait", are two items.
        Understand the owner's intention, not only the words; one dictation often holds several intentions:
        - something to buy (« je dois acheter », « il me faut »): list « épicerie » for food and household, else « achats »;
        - something the owner wishes to receive (« j'aimerais qu'on m'achète », « j'aimerais recevoir »): list « souhaits », \
        or « souhaits d'anniversaire » for the owner's birthday;
        - a gift idea for someone: list « cadeaux pour Julie », that person in people;
        - what someone likes or dislikes (« Julie aime les parfums »): kind preference, that person in people, never a list;
        - « je dois », « il faut que »: a task; « j'aimerais faire », « peut-être »: an idea; « j'ai décidé »: a decision.
        For each item:
        - excerpt: the exact words of the note, copied verbatim, never rephrased or translated.
        - intent: what the owner means, decided BEFORE the kind, the list and the category: obligation, appointment, \
        purchase (the owner must buy or get something), wish (to receive), giftIdea (to give), listAdd, listCheck, \
        listRemove, fact, preference, goal, idea, decision, narrative (something that happened), question, hypothesis \
        (« si… », « je pourrais »), quote (someone else's words), correction. « je dois laver l'auto » is an \
        obligation: an action on something the owner already has is never a purchase.
        - polarity: negative only when the owner says the thing must not happen or did not happen; « n'oublie pas de » \
        is affirmative.
        - subject, action, object, beneficiary: who, the French verb, its object and for whom, copied from the note.
        - title and summary: clear, natural French without hesitation, English and slang words translated, and the \
        real date instead of « aujourd'hui » or « demain ».
        - kind: task (something to do), appointment (something at a given time or place), idea, decision, preference, \
        info (a fact to remember, such as a measurement), other.
        - list and listItems: only for the intents purchase (without a date), wish, giftIdea, listAdd, listCheck and \
        listRemove: the list name and the things this item's own words say, one per entry; reuse an existing list, \
        written exactly as given, when it is the same list said differently. Empty for every other intent, a negative \
        polarity, a question, a condition or someone else's words. Never a thing the note does not say.
        - categoryReason: written before choosing the category, one short French sentence: what the item is really \
        about, and why it truly belongs to the existing category you reuse (judged by what it contains), or why none \
        fits and a new one is needed. The category must agree with it.
        - category: the domain of the owner's life this item belongs to, in French, decided from its meaning. Reuse an \
        existing category, written exactly as given, only when the subject truly belongs to it; a word in common is not \
        enough. When none truly fits, create a new category: a broad domain in French that later notes will join.
        The owner wants few broad categories: prefer an existing broad category (its number of notes is given) to a new one.
        When the prompt says where the most similar notes are filed, file the item there if the subject truly matches; \
        the owner's own filings show how he likes to organize.
        A note that only gives a person's birthday or feast day is info, a date to remember, not a task: file it in the \
        owner's existing category for birthdays, or create « Anniversaires »; never with family, health or money. \
        Something to do around a birthday (buying a gift) stays a task.
        A folder that tracks a measurement (weight, sleep, blood pressure, pulse, steps, blood sugar) only receives that \
        measurement. A weight in pounds (« livres ») is not money.
        When the prompt says what Engram already recognized in the note, trust it.
        - categoryDescription: only when the category is new, one short French sentence describing it.
        - subcategory: optional, a precise and lasting topic inside the category; reuse an existing one when the item \
        truly belongs to it; create one only for a subject that will gather at least 3 notes; otherwise leave it empty.
        - dates: the date expressions of this item with their role; an item that follows another one in time (« pis \
        après ») also gets that item's date expression.
        - people and places: the named people and the specific places of the item, copied from the note; never « je » or « moi ».
        - Previous note: what the owner said a few minutes before. Use it only for a word that clearly points back to it \
        (« elle », « lui », « sa fête »: that person; « cette liste »: that list; « ce projet »: that folder); when \
        several could be meant, ignore it.
        Never invent facts, dates or names that are not in the note.
        When the prompt lists « Corrections requested », your previous answer was refused for those reasons: fix them.
        """

    /// « Previous note (5 min ago): people: Julie; folders: Projets › Chalet » ; nil si vide.
    static func describe(_ recent: RecentContext) -> String? {
        let parts = [("people", recent.people), ("lists", recent.lists), ("folders", recent.folders)]
            .filter { !$0.1.isEmpty }
            .map { "\($0.0): \($0.1.joined(separator: ", "))" }
        return parts.isEmpty ? nil : "Previous note (\(recent.minutesAgo) min ago): \(parts.joined(separator: "; "))"
    }

    static func prompt(text: String, categories: [String], likely: [String], today: String? = nil,
                       facts: [String] = [], descriptions: [String: String] = [:], evidence: [FolderEvidence] = [],
                       counts: [String: Int] = [:], lists: [String] = [], recent: RecentContext? = nil,
                       repairNotes: [String] = []) -> String {
        // Une catégorie par ligne, avec son nombre de notes (P34) et ce qu'elle contient (P32) quand Engram le sait.
        let existing = categories.isEmpty ? "(none yet)"
            : categories.map { name in
                let size = counts[name].map { " (\($0))" } ?? ""
                return descriptions[name].map { "- \(name)\(size) : \($0)" } ?? "- \(name)\(size)"
            }.joined(separator: "\n")
        let hint = likely.isEmpty ? ""
            : "\nExisting categories closest in meaning (a hint, not an obligation): \(likely.joined(separator: ", "))\n"
        let known = facts.isEmpty ? "" : "\nEngram already recognized in this note: \(facts.joined(separator: "; "))\n"
        let similar = evidence.isEmpty ? "" : "\nThe most similar notes are filed in: \(SimilarFolders.describe(evidence))\n"
        let date = today.map { "Today: \($0)\n" } ?? ""
        // P41 — les listes du propriétaire, pour y ajouter plutôt que d'en créer d'autres.
        let existingLists = lists.isEmpty ? "" : "\nExisting lists: \(lists.joined(separator: "; "))\n"
        // P42 — ce qui vient d'être dit, pour comprendre « elle », « cette liste », « ce projet ».
        let previous = recent.flatMap(describe).map { "\n\($0)\n" } ?? ""
        // F07 — les raisons précises du refus de la réponse précédente (un seul nouvel essai).
        let repairs = repairNotes.isEmpty ? ""
            : "\nCorrections requested (your previous answer was refused):\n"
                + repairNotes.map { "- \($0)" }.joined(separator: "\n") + "\n"
        return """
            \(date)Existing categories ("Parent › Child" means a subcategory; in parentheses, its number of notes; \
            after « : », what it contains):
            \(existing)
            \(hint)\(existingLists)\(known)\(similar)\(previous)\(repairs)
            Note to file:
            \(text)
            """
    }
}

// MARK: - Analyseur

/// Analyse des pensées par le modèle d'Apple, **sur l'iPhone** (aucun envoi sur Internet).
/// Il classe les notes secrètes et sert de secours quand les services en ligne ne répondent pas.
public struct AppleThoughtAnalyzer: MemoryAnalyzer {
    public static let promptVersion = AnalysisPrompt.version
    static let maxChunkLength = 2_500
    /// Nombre de catégories proches du sens de la note données en indice au modèle.
    static let hintCount = 5

    let embedder: any SentenceEmbedder

    public init(embedder: any SentenceEmbedder = AppleSentenceEmbedder()) {
        self.embedder = embedder
    }

    /// État lisible du modèle, pour les Réglages.
    public static func availabilityDescription() -> (isAvailable: Bool, text: String) {
        let availability = SystemLanguageModel.default.availability
        if case .available = availability { return (true, "Disponible sur cet iPhone") }
        return (false, describe(availability))
    }

    public func analyze(text: String, existingCategories: [String]) async throws -> ThoughtAnalysis {
        try await analyze(text: text, existingCategories: existingCategories, context: AnalysisContext())
    }

    /// Le jour de la dictée est donné au modèle : il écrit la vraie date plutôt que « aujourd'hui ».
    public func analyze(text: String, existingCategories: [String], context: AnalysisContext) async throws -> ThoughtAnalysis {
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else { throw AnalyzerError.unavailable(Self.describe(availability)) }
        // Seulement les catégories vraiment proches du sens (aucune si le sens est indisponible) : P31.
        let likely = CategoryHints.likely(text: text, categories: existingCategories, embedder: embedder,
                                          limit: Self.hintCount)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.dateFormat = "EEEE d MMMM yyyy"
        let today = formatter.string(from: context.capturedAt)
        var thoughts: [AnalyzedThought] = []
        for chunk in TextChunker.chunks(of: text, maxLength: Self.maxChunkLength) {
            thoughts += try await analyze(chunk: chunk, existingCategories: existingCategories, likely: likely, today: today,
                                          facts: context.facts, descriptions: context.categoryDescriptions,
                                          evidence: context.folderEvidence, counts: context.categoryCounts,
                                          lists: context.lists, recent: context.recent, repairNotes: context.repairNotes, depth: 0)
        }
        return ThoughtAnalysis(thoughts: thoughts)
    }

    func analyze(chunk: String, existingCategories: [String], likely: [String], today: String?, facts: [String] = [],
                 descriptions: [String: String] = [:], evidence: [FolderEvidence] = [], counts: [String: Int] = [:],
                 lists: [String] = [], recent: RecentContext? = nil, repairNotes: [String] = [],
                 depth: Int) async throws -> [AnalyzedThought] {
        let session = LanguageModelSession(instructions: AnalysisPrompt.instructions)
        do {
            let response = try await session.respond(
                to: AnalysisPrompt.prompt(text: chunk, categories: existingCategories, likely: likely, today: today,
                                          facts: facts, descriptions: descriptions, evidence: evidence, counts: counts,
                                          lists: lists, recent: recent, repairNotes: repairNotes),
                generating: GeneratedThoughts.self)
            return response.content.thoughts.map(Self.convert)
        } catch let error as LanguageModelError {
            // iOS 27 : `LanguageModelError` remplace `LanguageModelSession.GenerationError`.
            switch error {
            case .contextSizeExceeded where depth < 3:
                return try await analyzeInHalves(chunk, existingCategories: existingCategories, likely: likely, today: today,
                                                 facts: facts, descriptions: descriptions, evidence: evidence, counts: counts, lists: lists, recent: recent, repairNotes: repairNotes, depth: depth)
            case .unsupportedLanguageOrLocale, .guardrailViolation, .refusal:
                // Problème propre à cette note : repli pour elle seule (ne bloque pas les suivantes).
                throw AnalyzerError.refused
            case .rateLimited, .timeout:
                throw AnalyzerError.busy
            default:
                throw AnalyzerError.invalidOutput
            }
        } catch {
            // Autres erreurs (ressources du modèle absentes, anciennes erreurs) : reconnues par leur description.
            let name = String(describing: error)
            if name.localizedCaseInsensitiveContains("assetsUnavailable") {
                throw AnalyzerError.unavailable("Le modèle d'Apple Intelligence se télécharge encore.")
            }
            if name.localizedCaseInsensitiveContains("exceededContextWindowSize"), depth < 3 {
                return try await analyzeInHalves(chunk, existingCategories: existingCategories, likely: likely, today: today,
                                                 facts: facts, descriptions: descriptions, evidence: evidence, counts: counts, lists: lists, recent: recent, repairNotes: repairNotes, depth: depth)
            }
            throw AnalyzerError.invalidOutput
        }
    }

    func analyzeInHalves(_ chunk: String, existingCategories: [String], likely: [String], today: String?,
                         facts: [String] = [], descriptions: [String: String] = [:], evidence: [FolderEvidence] = [],
                         counts: [String: Int] = [:], lists: [String] = [], recent: RecentContext? = nil, repairNotes: [String] = [],
                         depth: Int) async throws -> [AnalyzedThought] {
        let halves = TextChunker.halves(of: chunk)
        guard halves.count == 2 else { throw AnalyzerError.invalidOutput }
        let first = try await analyze(chunk: halves[0], existingCategories: existingCategories, likely: likely, today: today,
                                      facts: facts, descriptions: descriptions, evidence: evidence, counts: counts, lists: lists, recent: recent, repairNotes: repairNotes, depth: depth + 1)
        let second = try await analyze(chunk: halves[1], existingCategories: existingCategories, likely: likely, today: today,
                                       facts: facts, descriptions: descriptions, evidence: evidence, counts: counts, lists: lists, recent: recent, repairNotes: repairNotes, depth: depth + 1)
        return first + second
    }

    static func convert(_ generated: GeneratedThought) -> AnalyzedThought {
        func clean(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let kind = Self.kind(generated.kind)
        // F16 — chaque date garde son rôle ; pour l'échéance, le rappel d'abord (un rendez-vous : sa propre date d'abord).
        let temporal = generated.dates.compactMap { date in
            clean(date.phrase).map { TemporalMention(role: Self.role(date.role), phrase: $0) }
        }
        let order: [TemporalRole: Int] = kind == .appointment ? [.event: 0, .deadline: 1, .reminder: 2]
            : [.reminder: 0, .deadline: 1, .event: 2]
        let dates = temporal.enumerated()
            .sorted { (order[$0.element.role] ?? 3, $0.offset) < (order[$1.element.role] ?? 3, $1.offset) }
            .map(\.element.phrase)
        return AnalyzedThought(
            title: generated.title,
            summary: clean(generated.summary),
            excerpt: generated.excerpt,
            kind: kind,
            tags: generated.tags,
            mentionedDates: dates,
            category: generated.category,
            subcategory: clean(generated.subcategory),
            categoryDescription: clean(generated.categoryDescription),
            people: generated.people,
            places: generated.places,
            categoryReason: clean(generated.categoryReason),
            listName: clean(generated.list),
            listItems: generated.listItems.compactMap(clean),
            intent: Self.intent(generated.intent),
            polarity: generated.polarity == .negative ? .negative : .affirmative,
            subject: clean(generated.subject),
            action: clean(generated.action),
            object: clean(generated.object),
            beneficiary: clean(generated.beneficiary),
            temporal: temporal)
    }

    static func intent(_ generated: GeneratedIntent) -> IntentType {
        switch generated {
        case .obligation: .obligation
        case .appointment: .appointment
        case .purchase: .purchase
        case .wish: .wish
        case .giftIdea: .giftIdea
        case .listAdd: .listAdd
        case .listCheck: .listCheck
        case .listRemove: .listRemove
        case .fact: .fact
        case .preference: .preference
        case .goal: .goal
        case .idea: .idea
        case .decision: .decision
        case .narrative: .narrative
        case .question: .question
        case .hypothesis: .hypothesis
        case .quote: .quote
        case .correction: .correction
        }
    }

    static func role(_ generated: GeneratedDateRole) -> TemporalRole {
        switch generated {
        case .reminder: .reminder
        case .deadline: .deadline
        case .event: .event
        case .start: .start
        case .end: .end
        case .recurrence: .recurrence
        case .other: .other
        }
    }

    static func kind(_ generated: GeneratedKind) -> MemoryKind {
        switch generated {
        case .idea: .idea
        case .task: .task
        case .appointment: .appointment
        case .decision: .decision
        case .preference: .preference
        case .info: .info
        case .other: .other
        }
    }

    static func describe(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "Disponible sur cet iPhone"
        case .unavailable(let reason):
            // Les noms des raisons varient selon les versions du SDK : on lit leur description plutôt que de les énumérer.
            let name = String(describing: reason)
            if name.contains("deviceNotEligible") {
                return "Cet appareil ne prend pas en charge Apple Intelligence."
            } else if name.contains("NotEnabled") {
                return "Active Apple Intelligence dans Réglages › Apple Intelligence et Siri."
            } else if name.contains("NotReady") {
                return "Apple Intelligence n'est pas encore prêt (téléchargement du modèle en cours)."
            }
            return "Apple Intelligence est indisponible pour l'instant."
        @unknown default:
            return "Apple Intelligence est indisponible."
        }
    }
}

// MARK: - Jugement de confidentialité

@Generable
struct GeneratedPrivacy {
    @Guide(description: "neutral, personal, secret or unsure — see the instructions. When you hesitate, answer unsure.")
    var level: GeneratedPrivacyLevel
    @Guide(description: "One short French sentence explaining the choice, without repeating any detail of the note.")
    var reason: String
}

@Generable
enum GeneratedPrivacyLevel {
    case neutral, personal, secret, unsure
}

/// Le modèle d'Apple juge, **sur l'iPhone**, si une note contient quelque chose de personnel avant tout envoi.
/// Une erreur, un refus ou une hésitation gardent la note sur l'iPhone (le contrôleur s'en charge).
public struct ApplePrivacyJudge: PrivacyJudge {
    static let instructions = """
        You decide whether a note from a personal memory app may be sent to a free online AI service whose terms \
        forbid any personal, sensitive or confidential information. The note may mix Québec French and English.
        Answer:
        - neutral: nothing about a specific person's life. Examples: "acheter du lait", "idée d'une app de recettes", \
        "regarder un film ce soir", "réparer la poignée de la porte".
        - personal: anything about the life of the owner or of someone else: health or body, money, job or colleagues, \
        family, relationships, people's names, places where someone lives or goes, appointments with others, beliefs, \
        legal matters.
        - secret: passwords, PIN or access codes, card, bank or identity numbers, or anything clearly confidential.
        - unsure: when you hesitate between two answers.
        Never answer neutral when you have any doubt.
        """

    public init() {}

    public func judge(_ text: String) async throws -> PrivacyJudgement {
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else {
            throw AnalyzerError.unavailable(AppleThoughtAnalyzer.describe(availability))
        }
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: "Note:\n\(text)", generating: GeneratedPrivacy.self)
        return PrivacyJudgement(verdict: Self.verdict(response.content.level), reason: response.content.reason)
    }

    static func verdict(_ level: GeneratedPrivacyLevel) -> PrivacyVerdict {
        switch level {
        case .neutral: .neutral
        case .personal: .personal
        case .secret: .secret
        case .unsure: .unsure
        }
    }
}
#endif
