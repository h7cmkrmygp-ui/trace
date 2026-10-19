import EngramCore
import Foundation

/// F20 — le corpus d'évaluation : des centaines de dictées **inventées** (aucune donnée réelle, prénoms fictifs), en
/// familles de paires minimales — agir sur une chose ou l'acheter, acheter ou recevoir ou offrir, devoir, pouvoir ou
/// avoir fait, négation, condition, question, citation, deux intentions, mesure de soi ou d'un tiers — réparties entre
/// un jeu de développement et un jeu de contrôle mis de côté (un cas sur quatre de chaque famille).
///
/// Chaque cas porte la bonne lecture (oracle) et, quand c'est utile, une lecture fausse plausible (adversaire) : le moteur
/// doit donner les effets attendus avec la première et ne produire aucun effet bloquant avec la seconde.
public enum EvaluationCorpus {
    static let chores: [(verb: String, object: String, past: String)] = [
        ("nettoyer", "ma douche", "nettoyé"), ("laver", "l'auto", "lavé"), ("réparer", "la clôture", "réparé"),
        ("ranger", "le garage", "rangé"), ("vider", "le lave-vaisselle", "vidé"), ("tondre", "le gazon", "tondu"),
        ("peinturer", "la galerie", "peinturé"), ("changer", "les piles du détecteur", "changé"),
        ("sortir", "les poubelles", "sorti"), ("arroser", "les plantes", "arrosé"), ("appeler", "le garagiste", "appelé"),
        ("payer", "la facture d'électricité", "payé"),
    ]
    static let days = ["Lundi", "Mardi", "Jeudi", "Samedi", "Dimanche", "Demain"]
    static let products: [(phrase: String, item: String)] = [
        ("du lait", "Lait"), ("des œufs", "Œufs"), ("du pain", "Pain"), ("du café", "Café"),
        ("du savon à vaisselle", "Savon à vaisselle"), ("des piles", "Piles"), ("du papier de toilette", "Papier de toilette"),
        ("des bananes", "Bananes"), ("du beurre", "Beurre"), ("de la farine", "Farine"), ("du riz", "Riz"),
        ("des pâtes", "Pâtes"), ("du yogourt", "Yogourt"), ("des carottes", "Carottes"),
    ]
    static let wishes: [(phrase: String, item: String)] = [
        ("une gourde", "Gourde"), ("un livre de recettes", "Livre de recettes"), ("des écouteurs", "Écouteurs"),
        ("un sac à dos", "Sac à dos"), ("une plante", "Plante"), ("un jeu de société", "Jeu de société"),
        ("une tasse", "Tasse"), ("un parapluie", "Parapluie"),
    ]
    static let gifts: [(phrase: String, item: String)] = [
        ("Une gourde", "Gourde"), ("Un livre de recettes", "Livre de recettes"), ("Un sac à dos", "Sac à dos"),
        ("Une plante", "Plante"), ("Un jeu de société", "Jeu de société"), ("Une tasse", "Tasse"),
        ("Un parapluie", "Parapluie"), ("Un foulard", "Foulard"),
    ]
    /// Prénoms inventés pour le corpus.
    public static let names = ["Inès", "Léo", "Maëlle", "Noé"]
    static let tastes = ["le thé vert", "les tulipes", "le jazz", "les mots croisés"]

    static func thought(_ excerpt: String, kind: MemoryKind, intent: IntentType, polarity: Polarity = .affirmative,
                        category: String, list: String? = nil, items: [String] = [], dates: [String] = [],
                        people: [String] = []) -> AnalyzedThought {
        AnalyzedThought(title: excerpt, summary: nil, excerpt: excerpt, kind: kind, tags: [], mentionedDates: dates,
                        category: category, subcategory: nil, people: people, listName: list, listItems: items,
                        intent: intent, polarity: polarity)
    }

    static func key(_ list: String, _ item: String) -> String {
        ListCommandParser.key(list) + "|" + ListCommandParser.key(item)
    }

    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    public static let cases: [ProductionCase] = {
        var cases: [ProductionCase] = []
        var counters: [String: Int] = [:]
        func add(_ family: String, _ text: String, keepLocal: Bool = false, expected: ExpectedEffects,
                 oracle: [AnalyzedThought], adversary: [AnalyzedThought]? = nil) {
            let index = counters[family, default: 0]
            counters[family] = index + 1
            cases.append(ProductionCase(id: "\(family)-\(index + 1)", split: index % 4 == 3 ? .heldout : .dev,
                                        family: family, text: text, keepLocal: keepLocal, expected: expected,
                                        oracle: ThoughtAnalysis(thoughts: oracle),
                                        adversary: adversary.map { ThoughtAnalysis(thoughts: $0) }))
        }

        // Agir sur une chose qu'on a : une tâche datée, jamais un achat (même proposée comme achat dans « Achats »).
        for chore in chores {
            for day in days {
                let text = "\(day), je dois \(chore.verb) \(chore.object)"
                add("obligation", text, keepLocal: day == "Dimanche",
                    expected: ExpectedEffects(noteKinds: [.task], dueCount: 1),
                    oracle: [thought(text, kind: .task, intent: .obligation, category: "Maison", dates: [day])],
                    adversary: [thought(text, kind: .task, intent: .purchase, category: "Achats", list: "achats",
                                        items: [capitalized("\(chore.verb) \(chore.object)")], dates: [day])])
            }
            let plain = "Je dois \(chore.verb) \(chore.object)"
            add("obligation-sans-date", plain, expected: ExpectedEffects(noteKinds: [.task], dueCount: 0),
                oracle: [thought(plain, kind: .task, intent: .obligation, category: "Maison")],
                adversary: [thought(plain, kind: .task, intent: .purchase, category: "Achats", list: "achats",
                                    items: [capitalized("\(chore.verb) \(chore.object)")])])
        }
        // Acheter, sous trois formes : la chose va dans la liste d'épicerie, sans note à part.
        for product in products {
            let expected = ExpectedEffects(listAdds: [key("épicerie", product.item)])
            for (text, intent) in [("Il me faut \(product.phrase)", IntentType.purchase),
                                   ("Je dois acheter \(product.phrase)", .purchase),
                                   ("Ajoute \(product.phrase) à ma liste d'épicerie", .listAdd)] {
                add("achat", text, expected: expected,
                    oracle: [thought(text, kind: .other, intent: intent, category: "Épicerie", list: "épicerie",
                                     items: [product.item])])
            }
            // Un achat daté reste une tâche avec son échéance.
            for day in ["lundi", "samedi"] {
                let text = "Je dois acheter \(product.phrase) \(day)"
                add("achat-date", text, expected: ExpectedEffects(noteKinds: [.task], dueCount: 1),
                    oracle: [thought(text, kind: .task, intent: .purchase, category: "Épicerie", list: "épicerie",
                                     items: [product.item], dates: [day])])
            }
            // La forme d'une commande ne suffit pas : négation, condition, question et citation n'écrivent rien.
            let negation = "N'ajoute pas \(product.phrase) à ma liste d'épicerie"
            add("negation", negation, expected: ExpectedEffects(noteKinds: [.other], forbidsListOperation: true),
                oracle: [thought(negation, kind: .other, intent: .listAdd, polarity: .negative, category: "Divers")],
                adversary: [thought(negation, kind: .other, intent: .listAdd, category: "Divers", list: "épicerie",
                                    items: [product.item])])
            let condition = "Si jamais il manque \(product.phrase), ajoute-le à ma liste"
            add("condition", condition, expected: ExpectedEffects(noteKinds: [.idea], forbidsListOperation: true),
                oracle: [thought(condition, kind: .idea, intent: .hypothesis, category: "Divers")],
                adversary: [thought(condition, kind: .other, intent: .listAdd, category: "Divers", list: "épicerie",
                                    items: [product.item])])
            let question = "Est-ce que j'ajoute \(product.phrase) à ma liste d'épicerie ?"
            add("question", question, expected: ExpectedEffects(noteKinds: [.other], forbidsListOperation: true),
                oracle: [thought(question, kind: .other, intent: .question, category: "Divers")],
                adversary: [thought(question, kind: .other, intent: .listAdd, category: "Divers", list: "épicerie",
                                    items: [product.item])])
            let name = names[(counters["citation"] ?? 0) % names.count]
            let quote = "\(name) m'a dit : ajoute \(product.phrase) à ta liste"
            add("citation", quote, expected: ExpectedEffects(noteKinds: [.info], forbidsListOperation: true),
                oracle: [thought(quote, kind: .info, intent: .quote, category: "Divers", people: [name])],
                adversary: [thought(quote, kind: .other, intent: .listAdd, category: "Divers", list: "épicerie",
                                    items: [product.item], people: [name])])
        }
        // Recevoir n'est pas acheter : la liste de souhaits.
        for wish in wishes {
            for text in ["J'aimerais qu'on m'offre \(wish.phrase)", "J'aimerais recevoir \(wish.phrase) pour ma fête"] {
                add("souhait", text, expected: ExpectedEffects(listAdds: [key("souhaits", wish.item)]),
                    oracle: [thought(text, kind: .other, intent: .wish, category: "Listes", list: "souhaits",
                                     items: [wish.item])])
            }
        }
        // Offrir : la liste de cadeaux de la personne.
        for gift in gifts {
            for name in names {
                let text = "\(gift.phrase) ferait un beau cadeau pour \(name)"
                add("cadeau", text, expected: ExpectedEffects(listAdds: [key("cadeaux pour \(name)", gift.item)]),
                    oracle: [thought(text, kind: .idea, intent: .giftIdea, category: "Listes",
                                     list: "cadeaux pour \(name)", items: [gift.item], people: [name])])
            }
        }
        // Avoir fait n'est pas devoir faire ; pouvoir faire est une idée.
        for chore in chores {
            let narrative = "Hier, j'ai \(chore.past) \(chore.object)"
            add("recit", narrative, expected: ExpectedEffects(noteKinds: [.info], dueCount: 0),
                oracle: [thought(narrative, kind: .info, intent: .narrative, category: "Maison", dates: ["Hier"])])
            let maybe = "Je pourrais \(chore.verb) \(chore.object)"
            add("hypothese", maybe, expected: ExpectedEffects(noteKinds: [.idea], dueCount: 0),
                oracle: [thought(maybe, kind: .idea, intent: .hypothesis, category: "Maison")],
                adversary: [thought(maybe, kind: .task, intent: .purchase, category: "Achats", list: "achats",
                                    items: [capitalized("\(chore.verb) \(chore.object)")])])
        }
        // Les goûts d'une personne : jamais une liste.
        for name in names {
            for taste in tastes {
                let text = "\(name) aime \(taste)"
                add("preference", text, expected: ExpectedEffects(noteKinds: [.preference]),
                    oracle: [thought(text, kind: .preference, intent: .preference, category: "Famille", people: [name])])
            }
        }
        // Une mesure de soi entre dans le suivi ; celle d'un tiers, non.
        for index in 0..<8 {
            let mine = "Je pèse \(150 + 2 * index) livres"
            add("mesure", mine, expected: ExpectedEffects(noteKinds: [.info], measurements: 1),
                oracle: [thought(mine, kind: .info, intent: .fact, category: "Santé")])
            let other = "Mon frère pèse \(170 + 2 * index) livres"
            add("mesure-tiers", other, expected: ExpectedEffects(noteKinds: [.info], measurements: 0),
                oracle: [thought(other, kind: .info, intent: .fact, category: "Santé")])
        }
        // Deux intentions dans une même dictée : chacune son effet.
        for (index, chore) in chores.enumerated() {
            let product = products[index % products.count]
            let day = days[index % days.count]
            let first = "\(day), je dois \(chore.verb) \(chore.object)"
            let second = "Il me faut aussi \(product.phrase)"
            add("deux-intentions", "\(first). \(second).",
                expected: ExpectedEffects(listAdds: [key("épicerie", product.item)], noteKinds: [.task], dueCount: 1),
                oracle: [thought(first, kind: .task, intent: .obligation, category: "Maison", dates: [day]),
                         thought(second, kind: .other, intent: .purchase, category: "Épicerie", list: "épicerie",
                                 items: [product.item])])
        }
        return cases
    }()
}
