import Foundation

/// P43 — « C'était quoi les affaires que je voulais pour mon anniversaire ? », « Qu'est-ce qu'il y a sur ma liste
/// d'épicerie ? » : Retrouver répond avec ce qui reste dans la liste, tiré de la liste elle-même.
public enum ListQuestion {
    /// La liste dont parle la question ; nil si elle porte sur autre chose ou si plusieurs listes conviennent autant.
    public static func list(in question: String, among lists: [ListsSnapshot.Source]) -> ListsSnapshot.Source? { nil }

    /// « Dans ta liste de souhaits d'anniversaire : Gourde et Livre (1 déjà cochée). »
    public static func answer(_ list: ListsSnapshot.Source) -> String { "" }
}

/// Ce qu'une personne aime et n'aime pas, d'après des phrases de notes.
public struct Tastes: Sendable, Equatable {
    public var likes: [String]
    public var dislikes: [String]

    public init(likes: [String] = [], dislikes: [String] = []) {
        self.likes = likes
        self.dislikes = dislikes
    }
}

/// P43 — « Qu'est-ce que Julie aime ? », « Une idée de cadeau pour Marc ? » : ses goûts, ses idées de cadeaux et sa fête,
/// tirés des notes ; rien d'inventé.
public enum PersonQuestion {
    /// La personne connue dont on demande les goûts ou une idée de cadeau ; nil sinon.
    public static func person(in question: String, among people: [String]) -> String? { nil }

    /// « Julie aime les parfums » → « les parfums » ; « Julie n'aime pas le café » → « le café » (n'aime pas).
    public static func tastes(in texts: [String]) -> Tastes { Tastes() }

    /// La réponse, ou nil si les notes ne disent rien de ses goûts ni de cadeaux.
    public static func answer(person: String, tastes: Tastes, giftIdeas: [String], birthday: String?) -> String? { nil }
}
