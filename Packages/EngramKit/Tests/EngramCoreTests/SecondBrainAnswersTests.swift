import Foundation
import Testing
@testable import EngramCore

/// P43 — Retrouver répond aux questions d'un deuxième cerveau : le contenu d'une liste, les goûts d'une personne, ses idées
/// de cadeaux ; tout vient des notes, rien n'est inventé.
struct SecondBrainAnswersTests {
    static let wishes = ListsSnapshot.Source(memoryID: UUID(), name: "Souhaits d'anniversaire",
                                             title: "Liste de souhaits d'anniversaire",
                                             body: "☐ Gourde\n☑ Écouteurs\n☐ Livre", isPrivate: false)
    static let groceries = ListsSnapshot.Source(memoryID: UUID(), name: "Épicerie", title: "Liste d'épicerie", body: "☐ Lait",
                                                isPrivate: false)

    @Test func aQuestionAboutAListFindsThatList() {
        let lists = [Self.wishes, Self.groceries]
        #expect(ListQuestion.list(in: "C'était quoi les affaires que je voulais pour mon anniversaire?", among: lists) == Self.wishes)
        #expect(ListQuestion.list(in: "Qu'est-ce qu'il y a sur ma liste d'épicerie?", among: lists) == Self.groceries)
        #expect(ListQuestion.list(in: "C'est quoi le numéro du garage?", among: lists) == nil)
        #expect(ListQuestion.answer(Self.wishes) == "Dans ta liste de souhaits d'anniversaire : Gourde et Livre (1 déjà cochée).")
        #expect(ListQuestion.answer(Self.groceries) == "Dans ta liste d'épicerie : Lait.")
    }

    @Test func whatSomeoneLikesComesFromTheNotes() {
        #expect(PersonQuestion.person(in: "Qu'est-ce que Julie aime?", among: ["Julie", "Marc"]) == "Julie")
        #expect(PersonQuestion.person(in: "Une idée de cadeau pour marc?", among: ["Julie", "Marc"]) == "Marc")
        #expect(PersonQuestion.person(in: "C'est quand la fête de Julie?", among: ["Julie"]) == nil)
        #expect(PersonQuestion.person(in: "Qu'est-ce que Léa aime?", among: ["Julie"]) == nil)
        let tastes = PersonQuestion.tastes(in: ["Julie aime les parfums", "Elle adore aussi le chocolat.",
                                                "Julie n'aime pas le café", "J'aime le cadeau de Julie"])
        #expect(tastes == Tastes(likes: ["les parfums", "le chocolat"], dislikes: ["le café"]))
        #expect(PersonQuestion.answer(person: "Julie", tastes: tastes, giftIdeas: ["Foulard"], birthday: nil)
            == "D'après tes notes, Julie aime les parfums et le chocolat. Julie n'aime pas le café. Idées de cadeaux pour Julie : Foulard.")
        // Rien de noté : pas de réponse inventée (la recherche dans les notes répond).
        #expect(PersonQuestion.answer(person: "Julie", tastes: Tastes(), giftIdeas: [], birthday: nil) == nil)
    }
}
