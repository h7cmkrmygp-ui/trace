import Foundation

/// P43 — « C'était quoi les affaires que je voulais pour mon anniversaire ? », « Qu'est-ce qu'il y a sur ma liste
/// d'épicerie ? » : Retrouver répond avec ce qui reste dans la liste, tiré de la liste elle-même.
public enum ListQuestion {
    /// La question demande ce que contient quelque chose (pas un montant, une date ni un numéro : Retrouver y répond).
    static let asksContent = #"\b(liste|quoi|qu est ce|quels?|quelles?|affaires|choses|reste|voulais|veux|voudrais|souhaitais|aimerais|wanted)\b"#
    static let asksAFact = #"\b(combien|quand|ou|numero|prix|heure|date)\b"#
    /// Vouloir recevoir : les listes de souhaits.
    static let wishCue = #"\b(voulais|veux|voudrais|voulait|souhaite|souhaitais|aimerais|envies?|recevoir|wishlist|wanted)\b"#
    static let wishWords: Set<String> = ["souhait", "wishlist", "envie"]
    /// Acheter : l'épicerie et ses autres noms.
    static let buyCue = #"\b(acheter|achats?|epicerie|courses|commissions)\b"#
    static let groceryWords: Set<String> = Set(ListCommandParser.groceries.map(TextNormalizer.normalizedName))

    /// La liste dont parle la question ; nil si elle porte sur autre chose ou si plusieurs listes conviennent autant.
    public static func list(in question: String, among lists: [ListsSnapshot.Source]) -> ListsSnapshot.Source? {
        let form = " " + TextNormalizer.matchingForm(question) + " "
        guard RecallText.contains(asksContent, in: form), !RecallText.contains(asksAFact, in: form) else { return nil }
        var words = Set(TextNormalizer.normalizedName(question).split(separator: " ").map(String.init))
        if RecallText.contains(wishCue, in: form) { words.formUnion(wishWords) }
        if RecallText.contains(buyCue, in: form) || !words.isDisjoint(with: groceryWords) { words.formUnion(groceryWords) }
        // Tous les mots du nom de la liste sont dans la question ; la plus précise gagne, à égalité rien n'est deviné.
        let scored = lists.compactMap { list -> (list: ListsSnapshot.Source, score: Int)? in
            let listWords = ListResolver.significantWords(list.name)
            guard !listWords.isEmpty, listWords.isSubset(of: words) else { return nil }
            return (list, listWords.count)
        }
        guard let best = scored.map(\.score).max() else { return nil }
        return scored.filter { $0.score == best }.map(\.list).onlyOne
    }

    /// « Dans ta liste de souhaits d'anniversaire : Gourde et Livre (1 déjà cochée). »
    public static func answer(_ list: ListsSnapshot.Source) -> String {
        let name = phrase(for: list.title)
        let capitalized = name.prefix(1).uppercased() + name.dropFirst()
        if list.isPrivate { return "\(capitalized) est privée : ouvre-la dans Engram pour la voir." }
        var open: [String] = []
        var done = 0
        for block in NoteBody.blocks(from: list.body) {
            guard case .check(let isDone) = block.kind else { continue }
            if isDone { done += 1 } else { open.append(block.text) }
        }
        if open.isEmpty { return done > 0 ? "Tout est coché dans \(name)." : "\(capitalized) est vide." }
        let checked = done == 0 ? "" : " (\(done) déjà cochée\(done > 1 ? "s" : ""))"
        return "Dans \(name) : \(SecondBrainText.naturalList(open))\(checked)."
    }

    /// « Liste de souhaits » → « ta liste de souhaits » ; un titre changé par le propriétaire → « ta liste « Mes envies » ».
    static func phrase(for title: String) -> String {
        title.lowercased().hasPrefix("liste") ? "ta l" + title.dropFirst() : "ta liste « \(title) »"
    }
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

/// P43 — ce que les notes disent d'une personne : ses goûts et ses idées de cadeaux (sa page, Retrouver, sa fête).
public struct PersonProfile: Sendable, Equatable {
    public var tastes: Tastes
    public var giftIdeas: [String]

    public init(tastes: Tastes = Tastes(), giftIdeas: [String] = []) {
        self.tastes = tastes
        self.giftIdeas = giftIdeas
    }

    public var isEmpty: Bool { tastes.likes.isEmpty && tastes.dislikes.isEmpty && giftIdeas.isEmpty }
}

/// P43 — « Qu'est-ce que Julie aime ? », « Une idée de cadeau pour Marc ? » : ses goûts, ses idées de cadeaux et sa fête,
/// tirés des notes ; rien d'inventé.
public enum PersonQuestion {
    static let asksTastes = #"\b(aime|aiment|aimait|adore|adorait|prefere|gouts?|cadeaux?|offrir|idees?|deteste|plairait|plait|fan)\b"#
    /// Ce que dit le propriétaire lui-même (« j'aime », « on adore ») ne parle pas de la personne.
    static let notTheOwner = #"(?<![jJ]')(?<![jJ]e )(?<![oO]n )(?<![nN]ous )"#
    /// « n'aime pas », « aime pas » (au Québec), « déteste » ; « aime pas mal » veut dire qu'elle aime.
    static let dislike = notTheOwner + #"\b(?:(?:n')?aime (?:vraiment )?pas(?! mal)(?: trop| vraiment| beaucoup| tellement)?|(?:n')?aime plus|d[ée]teste|(?:ne )?supporte pas)\s+(?<what>.+)$"#
    static let like = notTheOwner + #"(?<![nN]')\b(?:aime(?! pas(?! mal))(?! plus)|adore|pr[ée]f[èe]re|aimerait|voudrait|appr[ée]cie)\s+(?:(?:bien|beaucoup|vraiment|aussi|trop|énormément|encore|pas mal)\s+)*(?<what>.+)$"#
    static let maxLength = 80

    /// La personne connue dont on demande les goûts ou une idée de cadeau ; nil sinon (ou si plusieurs sont nommées).
    public static func person(in question: String, among people: [String]) -> String? {
        let form = " " + TextNormalizer.matchingForm(question) + " "
        guard RecallText.contains(asksTastes, in: form) else { return nil }
        let named = people.filter { name in
            let key = TextNormalizer.matchingForm(name)
            return !key.isEmpty && form.contains(" " + key + " ")
        }
        // « Marc Tremblay » plutôt que « Marc » ; deux personnes différentes : rien n'est deviné.
        let longest = named.filter { name in
            !named.contains { other in other != name && TextNormalizer.matchingForm(other).contains(TextNormalizer.matchingForm(name)) }
        }
        return longest.onlyOne
    }

    /// « Julie aime les parfums » → « les parfums » ; « Julie n'aime pas le café » → « le café » (n'aime pas).
    public static func tastes(in texts: [String]) -> Tastes {
        var tastes = Tastes()
        var seen = Set<String>()
        for text in texts {
            let clauses = text.replacingOccurrences(of: "’", with: "'")
                .components(separatedBy: CharacterSet(charactersIn: ".!?;\n"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
            for clause in clauses where !clause.isEmpty {
                if let what = capture(dislike, in: clause) {
                    if seen.insert("-" + TextNormalizer.matchingForm(what)).inserted { tastes.dislikes.append(what) }
                } else if let what = capture(like, in: clause) {
                    if seen.insert("+" + TextNormalizer.matchingForm(what)).inserted { tastes.likes.append(what) }
                }
            }
        }
        return tastes
    }

    /// La réponse, ou nil si les notes ne disent rien de ses goûts ni de cadeaux (sa fête seule ne répond pas à la question).
    public static func answer(person: String, tastes: Tastes, giftIdeas: [String], birthday: String?) -> String? {
        var sentences: [String] = []
        if !tastes.likes.isEmpty { sentences.append("\(person) aime \(SecondBrainText.naturalList(tastes.likes)).") }
        if !tastes.dislikes.isEmpty { sentences.append("\(person) n'aime pas \(SecondBrainText.naturalList(tastes.dislikes)).") }
        if !sentences.isEmpty { sentences[0] = "D'après tes notes, " + sentences[0] }
        if !giftIdeas.isEmpty { sentences.append("Idées de cadeaux pour \(person) : \(SecondBrainText.naturalList(giftIdeas)).") }
        guard !sentences.isEmpty else { return nil }
        if let birthday { sentences.append(birthday) }
        return sentences.joined(separator: " ")
    }

    static func capture(_ pattern: String, in clause: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: clause, range: NSRange(clause.startIndex..., in: clause)),
              let range = Range(match.range(withName: "what"), in: clause) else { return nil }
        let what = clause[range].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",:-")))
        guard !what.isEmpty, what.count <= maxLength else { return nil }
        return what
    }
}

enum SecondBrainText {
    /// « a », « a et b », « a, b et c ».
    static func naturalList(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " et " + items[items.count - 1]
    }
}
