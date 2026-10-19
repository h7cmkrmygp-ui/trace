import Foundation

/// P45 — « Qu'est-ce que j'avais prévu pour le chalet ? », « Qu'est-ce qu'il reste à faire pour ce projet ? » : Retrouver
/// répond avec ce qui reste à faire dans le dossier du projet, et ce qui y est noté.
public enum ProjectQuestion {
    /// La question demande ce qui est prévu (pas un montant, une date ni un numéro : Retrouver y répond).
    static let asksPlans = #"\b(prevu|prevue|prevus|prevues|planifie|planifiee|reste|a faire|plans?|organiser?)\b"#
    static let maxItems = 8

    /// Le dossier dont parle la question : par son nom, ou « ce projet » (le seul projet de la dernière dictée) ; nil sinon.
    public static func folder(in question: String, among folders: [String], recent: RecentContext?) -> String? {
        let form = " " + TextNormalizer.matchingForm(question) + " "
        guard RecallText.contains(asksPlans, in: form), !RecallText.contains(ListQuestion.asksAFact, in: form) else { return nil }
        // « Ce projet » : seulement celui dont on vient de parler ; jamais deviné par le mot « projet ».
        if ContextReferences.refersToAProject(question) {
            return recent.flatMap(AnalysisValidator.projectFolder)
        }
        // Par son nom : le dernier niveau du dossier (« Chalet » pour « Projets › Chalet ») est dans la question ; le plus
        // profond gagne, à égalité rien n'est deviné.
        let words = Set(TextNormalizer.normalizedName(question).split(separator: " ").map(String.init))
        let scored = folders.compactMap { folder -> (folder: String, depth: Int)? in
            let parts = folder.components(separatedBy: "›").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let last = parts.last else { return nil }
            let lastWords = ListResolver.significantWords(last)
            guard !lastWords.isEmpty, lastWords.isSubset(of: words) else { return nil }
            return (folder, parts.count)
        }
        guard let deepest = scored.map(\.depth).max() else { return nil }
        return scored.filter { $0.depth == deepest }.map(\.folder).onlyOne
    }

    /// « Pour « Projets › Chalet », à faire : Réparer le quai et Acheter du bois. Aussi noté : Budget du chalet. »
    public static func answer(folder: String, open: [String], notes: [String]) -> String {
        let todo = Array(open.prefix(maxItems))
        let noted = Array(notes.prefix(maxItems))
        var text = "Pour « \(folder) », "
        if todo.isEmpty {
            text += "rien à faire pour l'instant."
            if !noted.isEmpty { text += " Noté : \(SecondBrainText.naturalList(noted))." }
        } else {
            text += "à faire : \(SecondBrainText.naturalList(todo))."
            if !noted.isEmpty { text += " Aussi noté : \(SecondBrainText.naturalList(noted))." }
        }
        return text
    }
}
