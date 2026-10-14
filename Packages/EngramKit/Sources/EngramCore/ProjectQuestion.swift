import Foundation

/// P45 — « Qu'est-ce que j'avais prévu pour le chalet ? », « Qu'est-ce qu'il reste à faire pour ce projet ? » : Retrouver
/// répond avec ce qui reste à faire dans le dossier du projet, et ce qui y est noté.
public enum ProjectQuestion {
    /// Le dossier dont parle la question : par son nom, ou « ce projet » (le seul projet de la dernière dictée) ; nil sinon.
    public static func folder(in question: String, among folders: [String], recent: RecentContext?) -> String? { nil }

    /// « Pour « Projets › Chalet », à faire : Réparer le quai et Acheter du bois. Aussi noté : Budget du chalet. »
    public static func answer(folder: String, open: [String], notes: [String]) -> String { "" }
}
