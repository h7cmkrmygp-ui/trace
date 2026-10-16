import Foundation

/// P40 — un dossier tel que le ménage le voit.
public struct TidyFolder: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let parentID: UUID?
    /// Créé ou nommé par le propriétaire : jamais fusionné dans un autre, jamais renommé, jamais replié.
    public let createdByOwner: Bool
    /// Notes du dossier (sous-dossiers compris).
    public let noteCount: Int
    public let createdAt: Date
    /// Une note y a été rangée ou confirmée par le propriétaire.
    public let hasOwnerNotes: Bool
    public let hasChildren: Bool

    public init(id: UUID, name: String, parentID: UUID?, createdByOwner: Bool, noteCount: Int, createdAt: Date,
                hasOwnerNotes: Bool, hasChildren: Bool) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdByOwner = createdByOwner
        self.noteCount = noteCount
        self.createdAt = createdAt
        self.hasOwnerNotes = hasOwnerNotes
        self.hasChildren = hasChildren
    }
}

/// P40 — une note rangée par l'IA, avec ses dossiers et le vote de ses notes semblables (sans elle).
public struct TidyNote: Sendable, Equatable {
    public let id: UUID
    public let paths: [String]
    public let evidence: [FolderEvidence]
    /// F24 — le texte de la note : un suivi qui la refuserait n'est jamais visé.
    public let text: String

    public init(id: UUID, paths: [String], evidence: [FolderEvidence], text: String = "") {
        self.id = id
        self.paths = paths
        self.evidence = evidence
        self.text = text
    }
}

/// P40 — un changement du ménage.
public enum TidyAction: Sendable, Equatable {
    case merge(source: UUID, into: UUID)
    case rename(folder: UUID, to: String)
    case fold(folder: UUID, into: UUID)
    case move(memory: UUID, from: String, to: String)
}

/// P40 — le ménage automatique : il décide, sans toucher à rien ; le magasin applique et note chaque changement.
public enum TidyPlanner {
    /// Noms de dossiers qui veulent dire la même chose (sans accents, au singulier), et le nom français à garder.
    static let synonyms: [(french: String, keys: Set<String>)] = [
        ("Automobile", ["auto", "automobile", "voiture", "vehicule", "char", "car"]),
        ("Finances", ["finance", "argent", "money"]),
        ("Travail", ["travail", "emploi", "boulot", "work"]),
        ("Santé", ["sante", "health"]),
        ("Maison", ["maison", "domicile", "logement", "home", "house"]),
        ("Famille", ["famille", "family"]),
        ("Achats", ["achat", "magasinage", "shopping"]),
        ("Épicerie", ["epicerie", "grocerie", "grocery"]),
        ("Voyages", ["voyage", "vacance", "travel", "trip"]),
        ("Idées", ["idee", "idea"]),
        ("Projets", ["projet", "project"]),
        ("Études", ["etude", "ecole", "school", "studie", "study"]),
        ("Sport", ["sport", "entrainement", "fitness", "workout"]),
        ("Loisirs", ["loisir", "hobbie", "hobby", "divertissement"]),
        ("Anniversaires", ["anniversaire", "fete", "birthday"]),
        ("Assurances", ["assurance", "insurance"]),
        ("Pièces auto", ["piece auto", "car part", "auto part"]),
    ]

    /// Noms anglais courants de dossiers (sans accents, au singulier) et leur nom français.
    static let english: [String: String] = [
        "car": "Automobile", "car part": "Pièces auto", "auto part": "Pièces auto", "money": "Finances", "work": "Travail",
        "health": "Santé", "home": "Maison", "house": "Maison", "family": "Famille", "shopping": "Achats",
        "grocerie": "Épicerie", "grocery": "Épicerie", "travel": "Voyages", "trip": "Voyages", "idea": "Idées",
        "project": "Projets", "school": "Études", "studie": "Études", "study": "Études", "birthday": "Anniversaires",
        "insurance": "Assurances", "hobbie": "Loisirs", "hobby": "Loisirs", "friend": "Amis", "food": "Alimentation",
        "recipe": "Recettes", "bill": "Factures", "taxe": "Impôts", "tax": "Impôts", "appointment": "Rendez-vous",
        "garden": "Jardin", "pet": "Animaux", "music": "Musique", "movie": "Films", "book": "Livres", "kid": "Enfants",
        "maintenance": "Entretien", "repair": "Réparations", "gift": "Cadeaux", "event": "Événements", "task": "Tâches",
        "reminder": "Rappels", "personal": "Personnel", "workout": "Entraînement",
    ]

    /// Un sous-dossier de moins de 3 notes, plus vieux que ça, est replié dans son dossier.
    static let foldAge: TimeInterval = 14 * 86_400
    static let foldMinimumNotes = 3
    /// Notes semblables dans un autre dossier pour déplacer une note.
    static let moveMinimumNotes = 3

    static func key(_ name: String) -> String { TextNormalizer.normalizedName(name) }

    /// Les doublons d'un même niveau (racines, ou sous-dossiers d'un même dossier) vont dans le dossier du propriétaire,
    /// sinon le plus gros (à égalité : le nom français, puis le plus ancien). Un dossier du propriétaire n'est jamais
    /// fusionné dans un autre.
    public static func merges(_ folders: [TidyFolder]) -> [TidyAction] {
        var actions: [TidyAction] = []
        let levels = Dictionary(grouping: folders, by: \.parentID)
        for group in synonyms {
            for (_, siblings) in levels.sorted(by: { ($0.key?.uuidString ?? "") < ($1.key?.uuidString ?? "") }) {
                let same = siblings.filter { group.keys.contains(key($0.name)) }
                guard same.count >= 2, let target = same.max(by: { better($1, than: $0) }) else { continue }
                for folder in same where folder.id != target.id && !folder.createdByOwner {
                    actions.append(.merge(source: folder.id, into: target.id))
                }
            }
        }
        // Dans l'ordre où les dossiers ont été donnés.
        let order = Dictionary(uniqueKeysWithValues: folders.enumerated().map { ($1.id, $0) })
        return actions.sorted { lhs, rhs in
            guard case .merge(let a, _) = lhs, case .merge(let b, _) = rhs else { return false }
            return (order[a] ?? 0) < (order[b] ?? 0)
        }
    }

    /// Vrai si `lhs` doit garder ses notes plutôt que `rhs`.
    static func better(_ lhs: TidyFolder, than rhs: TidyFolder) -> Bool {
        if lhs.createdByOwner != rhs.createdByOwner { return lhs.createdByOwner }
        if lhs.noteCount != rhs.noteCount { return lhs.noteCount > rhs.noteCount }
        let lhsFrench = english[key(lhs.name)] == nil
        let rhsFrench = english[key(rhs.name)] == nil
        if lhsFrench != rhsFrench { return lhsFrench }
        return lhs.createdAt < rhs.createdAt
    }

    /// Un dossier créé par l'IA avec un nom anglais courant prend son nom français, s'il n'existe pas déjà à côté.
    public static func renames(_ folders: [TidyFolder]) -> [TidyAction] {
        folders.compactMap { folder in
            guard !folder.createdByOwner, let french = english[key(folder.name)] else { return nil }
            let taken = folders.contains { $0.parentID == folder.parentID && $0.id != folder.id && key($0.name) == key(french) }
            return taken ? nil : .rename(folder: folder.id, to: french)
        }
    }

    /// Un sous-dossier créé par l'IA qui a encore moins de 3 notes après deux semaines est replié dans son dossier
    /// (jamais s'il a des sous-dossiers ou une note rangée par le propriétaire).
    public static func folds(_ folders: [TidyFolder], now: Date) -> [TidyAction] {
        let ids = Set(folders.map(\.id))
        return folders.compactMap { folder in
            guard let parent = folder.parentID, ids.contains(parent), !folder.createdByOwner, !folder.hasOwnerNotes,
                  !folder.hasChildren, folder.noteCount < foldMinimumNotes,
                  now.timeIntervalSince(folder.createdAt) >= foldAge else { return nil }
            return .fold(folder: folder.id, into: parent)
        }
    }

    /// Une note rangée par l'IA dont au moins 3 notes semblables sont dans un même autre dossier, et aucune dans le sien,
    /// les rejoint.
    public static func moves(_ notes: [TidyNote]) -> [TidyAction] {
        notes.compactMap { note in
            guard let from = note.paths.first, let top = note.evidence.first, top.notes >= moveMinimumNotes,
                  Set(note.paths).isDisjoint(with: note.evidence.map(\.path)) else { return nil }
            return .move(memory: note.id, from: from, to: top.path)
        }
    }

    /// « 1 note », « 3 notes ».
    public static func notes(_ count: Int) -> String { count == 1 ? "1 note" : "\(count) notes" }

    public static func summary(merged source: String, into target: String, notes count: Int) -> String {
        "« \(source) » fusionné dans « \(target) » (\(notes(count)))."
    }

    public static func summary(renamed old: String, to new: String) -> String {
        "« \(old) » renommé « \(new) »."
    }

    public static func summary(folded folder: String, into parent: String, notes count: Int) -> String {
        "« \(folder) » replié dans « \(parent) » (\(notes(count)))."
    }

    public static func summary(moved title: String, from: String, to: String) -> String {
        "« \(title) » déplacée de « \(from) » vers « \(to) »."
    }
}
