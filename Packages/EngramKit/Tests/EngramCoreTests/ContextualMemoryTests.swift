import Foundation
import Testing
@testable import EngramCore

/// P42 — la mémoire du contexte : « elle », « lui », « cette liste », « ce projet » renvoient à ce qui vient d'être dit,
/// seulement quand c'est clair ; en cas de doute, aucun lien n'est inventé.
struct ContextualMemoryTests {
    static let recent = RecentContext(people: ["Julie"], lists: ["souhaits d'anniversaire"],
                                      folders: ["Famille", "Projets › Chalet"], minutesAgo: 5)

    @Test func aNoteThatTalksAboutSomeoneWithoutNamingThem() {
        #expect(ContextReferences.refersToSomeone("Elle adore aussi le chocolat"))
        #expect(ContextReferences.refersToSomeone("Je dois lui acheter un cadeau"))
        #expect(ContextReferences.refersToSomeone("C'est bientôt sa fête"))
        #expect(ContextReferences.refersToSomeone("Il aimerait un nouveau vélo"))
        #expect(!ContextReferences.refersToSomeone("Il faut acheter du lait"))
        #expect(!ContextReferences.refersToSomeone("La voiture fait un bruit, elle doit aller au garage"))
        #expect(ContextReferences.refersToAList("Ajoute un livre à cette liste"))
        #expect(ContextReferences.refersToAList("Mets aussi du café sur la même liste"))
        #expect(!ContextReferences.refersToAList("Ajoute du café à ma liste d'épicerie"))
        #expect(ContextReferences.refersToAProject("Pour ce projet, il faut aussi acheter du bois"))
        #expect(!ContextReferences.refersToAProject("J'ai un nouveau projet de cuisine"))
        #expect(ContextReferences.listItems(in: "Ajoute un livre et des chandelles à cette liste") == ["Livre", "Chandelles"])
        #expect(ContextReferences.listItems(in: "Ajoute un livre à ma liste d'épicerie") == nil)
    }

    func valid(_ text: String, people: [String] = [], category: String = "Famille", list: String? = nil,
               items: [String] = [], recent: RecentContext?) throws -> ValidThought {
        let thought = AnalyzedThought(title: text, summary: nil, excerpt: text, kind: .preference, tags: [], mentionedDates: [],
                                      category: category, subcategory: nil, people: people, listName: list, listItems: items)
        return try #require(try AnalysisValidator.validate(ThoughtAnalysis(thoughts: [thought]), against: text, recent: recent).first)
    }

    @Test func elleIsThePersonJustMentioned() throws {
        #expect(try valid("Elle adore aussi le chocolat", recent: Self.recent).people == ["Julie"])
        // L'IA l'a compris aussi : la personne de la dictée précédente est gardée même si elle n'est pas nommée ici.
        #expect(try valid("Elle adore aussi le chocolat", people: ["Julie"], recent: Self.recent).people == ["Julie"])
        // Deux personnes juste avant : ambigu, aucun lien inventé.
        #expect(try valid("Elle adore aussi le chocolat",
                          recent: RecentContext(people: ["Julie", "Marc"])).people.isEmpty)
        // Rien juste avant, ou une phrase qui ne parle de personne : aucun lien.
        #expect(try valid("Elle adore aussi le chocolat", recent: nil).people.isEmpty)
        #expect(try valid("Il faut acheter du lait", recent: Self.recent).people.isEmpty)
        // Une personne que ni la note ni la dictée précédente ne nomment n'est jamais gardée.
        #expect(try valid("Il adore le thé", people: ["Marc"], recent: RecentContext(people: ["Julie", "Léa"])).people.isEmpty)
    }

    @Test func withinOneDictationElleIsThePersonJustNamed() throws {
        let text = "Julie aime les parfums. Elle adore aussi le chocolat."
        let analysis = ThoughtAnalysis(thoughts: [
            AnalyzedThought(title: "Parfums", summary: nil, excerpt: "Julie aime les parfums", kind: .preference, tags: [],
                            mentionedDates: [], category: "Famille", subcategory: nil, people: ["Julie"]),
            AnalyzedThought(title: "Chocolat", summary: nil, excerpt: "Elle adore aussi le chocolat", kind: .preference,
                            tags: [], mentionedDates: [], category: "Famille", subcategory: nil),
        ])
        #expect(try AnalysisValidator.validate(analysis, against: text).map(\.people) == [["Julie"], ["Julie"]])
    }

    @Test func thisListIsTheListJustUsed() throws {
        let thought = try valid("Ajoute un livre à cette liste", category: "Listes", recent: Self.recent)
        #expect(thought.listName == "souhaits d'anniversaire")
        #expect(thought.listItems == ["Livre"])
        // Deux listes juste avant : ambigu, rien n'est deviné.
        #expect(try valid("Ajoute un livre à cette liste", category: "Listes",
                          recent: RecentContext(lists: ["épicerie", "souhaits"])).listName == nil)
    }

    @Test func thisProjectIsTheProjectJustTalkedAbout() throws {
        let thought = try valid("Pour ce projet, il faut aussi acheter du bois", category: "Maison", recent: Self.recent)
        #expect(thought.categoryPath == ["Projets", "Chalet"])
        #expect(thought.categoryReason?.contains("Projets › Chalet") == true)
        // Deux projets possibles : le choix de l'IA reste.
        #expect(try valid("Pour ce projet, il faut aussi acheter du bois", category: "Maison",
                          recent: RecentContext(folders: ["Projets › Chalet", "Projets › Cuisine"])).categoryPath == ["Maison"])
    }
}
