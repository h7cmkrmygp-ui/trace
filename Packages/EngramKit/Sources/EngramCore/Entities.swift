import Foundation

// P9 — les personnes et les lieux de la mémoire.

public enum EntityKind: String, Codable, Sendable, CaseIterable, Hashable {
    case person, place
}

public enum EntityStatus: String, Codable, Sendable {
    case active
    /// « Ce n'est pas une personne / un lieu » : la page disparaît et l'IA ne recrée plus ce nom.
    case hidden
}

/// Une personne ou un lieu dont parlent les notes.
public struct EngramEntity: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var kind: EntityKind
    /// Nom affiché (« Mon manager », « Costco »).
    public var name: String
    /// Clé de comparaison (« manager », « costco ») : voir `EntityName.key`.
    public var normalizedName: String
    public var status: EntityStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), kind: EntityKind, name: String, now: Date) {
        self.id = id
        self.kind = kind
        self.name = name
        self.normalizedName = EntityName.key(name)
        self.status = .active
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, name, status
        case normalizedName = "normalized_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Ancien nom d'une personne ou d'un lieu (après une fusion ou un renommage) : retrouvé plus tard, il y mène.
public struct EntityAlias: Codable, Sendable, Hashable {
    public var kind: EntityKind
    public var normalizedName: String
    public var entityID: UUID

    public init(kind: EntityKind, normalizedName: String, entityID: UUID) {
        self.kind = kind
        self.normalizedName = normalizedName
        self.entityID = entityID
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case normalizedName = "normalized_name"
        case entityID = "entity_id"
    }
}

/// Lien note ↔ personne ou lieu. `rejected` = retiré par le propriétaire (l'IA ne le recréera jamais).
public struct EntityAssignment: Codable, Sendable, Hashable {
    public var memoryID: UUID
    public var entityID: UUID
    public var origin: AssignmentOrigin
    public var confirmed: Bool
    public var rejected: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(memoryID: UUID, entityID: UUID, origin: AssignmentOrigin, confirmed: Bool, rejected: Bool = false, now: Date) {
        self.memoryID = memoryID
        self.entityID = entityID
        self.origin = origin
        self.confirmed = confirmed
        self.rejected = rejected
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case origin, confirmed, rejected
        case memoryID = "memory_id"
        case entityID = "entity_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Un nom trouvé dans un texte par la reconnaissance de l'iPhone.
public struct RecognizedName: Sendable, Hashable {
    public let name: String
    public let kind: EntityKind

    public init(name: String, kind: EntityKind) {
        self.name = name
        self.kind = kind
    }
}

/// Reconnaissance des noms sur l'iPhone (NaturalLanguage dans l'app, faux reconnaisseur dans les tests).
public protocol EntityRecognizer: Sendable {
    func names(in text: String) -> [RecognizedName]
}

/// Les noms des personnes et des lieux : la clé qui reconnaît le même nom dit autrement, et le nom affiché.
public enum EntityName {
    public static let maxLength = 40

    /// Petits mots du début qui ne changent pas la personne ou le lieu (« au gym », « chez le dentiste »).
    static let articles: Set<String> = ["le", "la", "les", "l", "un", "une", "au", "aux", "a", "chez", "du", "de", "des", "d"]
    /// Possessifs : enlevés de la clé ; gardés dans le nom affiché d'une personne (« Mon manager »).
    static let possessives: Set<String> = [
        "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "nos", "votre", "vos", "leur", "leurs",
    ]
    /// Jamais une personne ni un lieu.
    static let pronouns: Set<String> = [
        "je", "j", "moi", "me", "m", "tu", "toi", "te", "il", "elle", "lui", "on", "nous", "vous", "ils", "elles", "eux",
        "quelqu un", "quelqu une", "personne", "chacun", "chacune", "tout le monde", "gens", "monde", "dehors",
        "quelque part", "ici", "la bas", "partout",
    ]

    /// « Mon manager », « le manager » → « manager » ; « au gym » → « gym » ; « L'Épicerie » → « epicerie ».
    public static func key(_ raw: String) -> String {
        var words = TextNormalizer.words(of: raw)
        while words.count > 1, let first = words.first, articles.contains(first) || possessives.contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    /// « le gym » → « Gym », « chez le dentiste » → « Dentiste » ; une personne garde son possessif (« Mon manager »).
    public static func display(_ raw: String, kind: EntityKind) -> String {
        var text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let removable = kind == .place ? articles.union(possessives) : articles
        while true {
            let lower = text.lowercased()
            // Élision collée au nom : « l'épicerie », « d'Alma ».
            if let elision = ["l'", "l’", "d'", "d’"].first(where: { lower.hasPrefix($0) }), text.count > elision.count {
                text = String(text.dropFirst(elision.count))
                continue
            }
            guard let space = text.firstIndex(of: " ") else { break }
            let first = String(text[..<space]).folding(options: [.caseInsensitive, .diacriticInsensitive],
                                                       locale: Locale(identifier: "fr_CA")).lowercased()
            guard removable.contains(first) else { break }
            text = String(text[text.index(after: space)...])
        }
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Un nom utilisable : pas vide, pas trop long, pas un pronom (« je », « moi », « quelqu'un »).
    public static func isAcceptable(_ raw: String) -> Bool {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty, collapsed.count <= maxLength else { return false }
        let normalized = Self.key(collapsed)
        return normalized.count >= 2 && !pronouns.contains(normalized)
    }

    /// Les noms proposés qui figurent dans le texte, une fois chacun, au plus `limit`.
    public static func clean(_ names: [String], in text: String, limit: Int) -> [String] {
        var seen = Set<String>()
        var kept: [String] = []
        for raw in names {
            guard kept.count < limit else { break }
            let name = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard isAcceptable(name), TextNormalizer.containsPhrase(name, in: text), seen.insert(Self.key(name)).inserted else {
                continue
            }
            kept.append(name)
        }
        return kept
    }
}
