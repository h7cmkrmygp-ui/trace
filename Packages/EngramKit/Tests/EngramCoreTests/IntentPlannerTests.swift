import Foundation
import Testing
@testable import EngramCore

/// F03, F04 — une proposition du modèle n'autorise pas n'importe quelle écriture : l'intention, sa polarité, sa forme (
/// question, condition, citation) et ce que la phrase dit vraiment décident de l'opération ; le dossier est séparé de
/// l'action. Aucune règle propre à un mot (« douche », « nettoyer ») : des familles d'opérations.
struct IntentPlannerTests {
    func thought(_ excerpt: String, intent: IntentType?, kind: MemoryKind = .task, polarity: Polarity = .affirmative,
                 list: String? = nil, items: [String] = [], path: [String] = [], dates: [String] = []) -> ValidThought {
        ValidThought(title: excerpt, summary: nil, excerpt: excerpt, spanStart: nil, spanEnd: nil, kind: kind, tags: [],
                     categoryPath: path, mentionedDates: dates, listName: list, listItems: items, intent: intent,
                     polarity: polarity)
    }

    func listOperations(_ plan: ActionPlan) -> [ActionPlan.Operation] {
        plan.operations.filter { if case .note = $0 { false } else { true } }
    }

    /// Le cas qui a révélé le défaut : une obligation de nettoyage proposée par erreur comme un achat, dans « Achats ».
    @Test func cleaningIsNeverTurnedIntoAPurchase() {
        let plan = ActionPlanner.plan(thought("Lundi, je dois nettoyer ma douche", intent: .purchase, list: "achats",
                                              items: ["Nettoyer ma douche"], path: ["Achats"]))
        #expect(listOperations(plan).isEmpty)
        #expect(plan.operations == [.note(.task)])
        #expect(!plan.keepsFolder)
        #expect(plan.review != nil)
        // Bien comprise, la même phrase est une tâche, et « Achats » ne lui convient pas non plus.
        let understood = ActionPlanner.plan(thought("Lundi, je dois nettoyer ma douche", intent: .obligation, path: ["Achats"]))
        #expect(understood.operations == [.note(.task)])
        #expect(!understood.keepsFolder)
        #expect(ActionPlanner.plan(thought("Lundi, je dois nettoyer ma douche", intent: .obligation, path: ["Maison"])).keepsFolder)
    }

    @Test func buyingReceivingAndGivingAreDifferentOperations() {
        #expect(ActionPlanner.plan(thought("Il me faut du nettoyant pour la douche", intent: .purchase, list: "épicerie",
                                           items: ["Nettoyant pour la douche"])).operations
            == [.appendToList(name: "épicerie", items: ["Nettoyant pour la douche"])])
        #expect(ActionPlanner.plan(thought("J'aimerais qu'on m'achète une gourde", intent: .wish, kind: .other,
                                           list: "souhaits", items: ["Gourde"])).operations
            == [.appendToList(name: "souhaits", items: ["Gourde"])])
        #expect(ActionPlanner.plan(thought("Un foulard ferait un beau cadeau pour Julie", intent: .giftIdea, kind: .idea,
                                           list: "cadeaux pour Julie", items: ["Foulard"])).operations
            == [.appendToList(name: "cadeaux pour Julie", items: ["Foulard"])])
        // Recevoir n'est pas acheter : un souhait sans aucune formule de souhait n'écrit rien.
        #expect(listOperations(ActionPlanner.plan(thought("Je dois appeler Marc", intent: .wish, list: "souhaits",
                                                          items: ["Marc"]))).isEmpty)
    }

    @Test func aNegationAQuestionAConditionOrAQuoteWritesNothing() {
        let requests = [
            ("N'ajoute pas du lait à ma liste d'épicerie", Polarity.affirmative),
            ("Ajoute pas de lait à ma liste d'épicerie", .affirmative),
            ("Ajoute du lait à ma liste d'épicerie", .negative),
            ("Si je dis « ajoute du lait », que feras-tu ?", .affirmative),
            ("Est-ce que j'ajoute du lait à ma liste d'épicerie ?", .affirmative),
            ("Paul m'a dit : ajoute du lait à ta liste", .affirmative),
            ("Si jamais il manque du lait, ajoute-le à ma liste", .affirmative),
        ]
        for (text, polarity) in requests {
            let plan = ActionPlanner.plan(thought(text, intent: .listAdd, polarity: polarity, list: "épicerie", items: ["Lait"]))
            #expect(listOperations(plan).isEmpty, "\(text)")
        }
        // La vraie demande, elle, s'applique.
        #expect(listOperations(ActionPlanner.plan(thought("Ajoute du lait à ma liste d'épicerie", intent: .listAdd,
                                                          list: "épicerie", items: ["Lait"]))).count == 1)
    }

    @Test func theListParserOnlyProvidesArgumentsToAnIntentThatAllowsIt() {
        // L'IA a compris une préférence ou une hypothèse : la forme « ajoute … à ma liste » ne suffit pas.
        #expect(listOperations(ActionPlanner.plan(thought("Ajoute du lait à ma liste d'épicerie", intent: .preference,
                                                          kind: .preference))).isEmpty)
        #expect(listOperations(ActionPlanner.plan(thought("Ajoute du lait à ma liste d'épicerie", intent: nil))).isEmpty)
        // Avec la bonne intention, l'analyseur de la phrase fournit la liste et les choses si l'IA ne les a pas données.
        #expect(ActionPlanner.plan(thought("Ajoute du lait et des œufs à ma liste d'épicerie", intent: .listAdd)).operations
            == [.appendToList(name: "épicerie", items: ["Lait", "Œufs"])])
        #expect(ActionPlanner.plan(thought("J'ai acheté le pain", intent: .listCheck, kind: .info)).operations
            == [.checkInList(name: nil, items: ["Pain"])])
        #expect(listOperations(ActionPlanner.plan(thought("J'ai acheté le pain", intent: .narrative, kind: .info))).isEmpty)
    }

    @Test func modalitiesKeepTheirMeaning() {
        #expect(ActionPlanner.plan(thought("J'aimerais faire du yoga", intent: .idea, kind: .task)).operations == [.note(.idea)])
        #expect(ActionPlanner.plan(thought("Je pourrais appeler Marc", intent: .hypothesis, kind: .task)).operations
            == [.note(.idea)])
        #expect(ActionPlanner.plan(thought("J'ai appelé Marc", intent: .narrative, kind: .task)).operations == [.note(.info)])
        #expect(ActionPlanner.plan(thought("J'ai décidé de garder la voiture", intent: .decision, kind: .info)).operations
            == [.note(.decision)])
        #expect(ActionPlanner.plan(thought("Mon objectif est de courir 5 km", intent: .goal, kind: .task)).operations
            == [.note(.info)])
    }

    @Test func aDatedPurchaseStaysATaskWithItsDate() {
        let plan = ActionPlanner.plan(thought("Je dois acheter du lait lundi", intent: .purchase, list: "épicerie",
                                              items: ["Lait"], dates: ["lundi"]))
        #expect(plan.operations.first == .note(.task))
    }

    @Test func eachFolderRoleAcceptsOnlyItsIntentions() {
        #expect(FolderRole.role(of: ["Achats"]) == .purchases)
        #expect(FolderRole.role(of: ["Épicerie"]) == .purchases)
        #expect(FolderRole.role(of: ["À faire"]) == .tasks)
        #expect(FolderRole.role(of: ["Maison"]) == nil)
        #expect(FolderRole.purchases.accepts(.purchase))
        #expect(!FolderRole.purchases.accepts(.obligation))
        #expect(FolderRole.tasks.accepts(.obligation))
        #expect(!FolderRole.tasks.accepts(.preference))
    }
}

/// F04 — la forme de la phrase, lue sans IA.
struct LinguisticGuardsTests {
    @Test func negationsConditionsQuestionsAndQuotesAreRecognized() {
        #expect(LinguisticGuards.inspect("N'ajoute pas du lait à ma liste").negated)
        #expect(LinguisticGuards.inspect("Ne mets plus de beurre sur la liste").negated)
        #expect(LinguisticGuards.inspect("Ajoute pas de lait").negated)
        #expect(LinguisticGuards.inspect("Pas besoin d'acheter du pain").negated)
        #expect(LinguisticGuards.inspect("Si je dis ajoute du lait").conditional)
        #expect(LinguisticGuards.inspect("Au cas où il manquerait du lait").conditional)
        #expect(LinguisticGuards.inspect("Que feras-tu ?").question)
        #expect(LinguisticGuards.inspect("Est-ce que je dois acheter du lait").question)
        #expect(LinguisticGuards.inspect("Paul m'a dit d'ajouter du lait").quoted)
        #expect(LinguisticGuards.inspect("Elle a dit « ajoute du lait »").quoted)
        // Un titre entre guillemets n'est pas une citation ; « aime pas mal » n'est pas une négation de commande.
        #expect(LinguisticGuards.inspect("Ajoute « Dune » à ma liste de films").isPlainRequest)
        #expect(LinguisticGuards.inspect("Ajoute du lait à ma liste d'épicerie").isPlainRequest)
    }
}
