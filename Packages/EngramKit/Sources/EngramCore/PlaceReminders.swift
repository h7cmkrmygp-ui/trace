import Foundation

/// P14 — arriver à un lieu, ou en partir.
public enum PlaceEvent: String, Codable, Sendable, CaseIterable {
    case arrive, leave
}

/// « quand j'arrive chez Costco » : le lieu dit (tel quel, sans article) et le moment.
public struct ParsedPlaceTrigger: Sendable, Equatable {
    public let place: String
    public let event: PlaceEvent

    public init(place: String, event: PlaceEvent) {
        self.place = place
        self.event = event
    }
}

/// Reconnaît, sur l'iPhone et sans IA, un rappel qui attend un lieu : « quand j'arrive chez Costco », « en sortant du
/// gym », « une fois rendu au bureau », « when I get home ». Une phrase ordinaire (« quand j'arrive à dormir », « à
/// l'aise », « au bout ») n'en est pas un.
public enum PlaceTriggerParser {
    /// Une façon de dire le moment, et les petits mots qui peuvent suivre (« chez », « au », « du »…).
    struct Pattern: Sendable {
        let pattern: String
        let event: PlaceEvent
        let prepositions: [String]
    }

    /// Après « arriver » : « chez », « à la », « au »… (« à » seul exige un nom propre : « à Laval »).
    static let toward = ["chez", "à la", "a la", "à l'", "a l'", "aux", "au", "à", "a"]
    /// Après « partir », « sortir » : « de chez », « du », « de la »…
    static let away = ["de chez", "de la", "de l'", "des", "du", "de", "d'"]
    /// Après « quitter » : « le travail », « la job », ou un nom propre.
    static let quitting = ["les", "le", "la", "l'", ""]
    static let englishToward = ["at the", "to the", "by the", "at", "to", "in", "by", "the", ""]
    static let englishAway = ["the", ""]

    static let patterns: [Pattern] = {
        func make(_ pattern: String, _ event: PlaceEvent, _ prepositions: [String]) -> Pattern {
            Pattern(pattern: pattern, event: event, prepositions: prepositions)
        }
        let me = "(?:j'|je\\s+)"
        let arriveVerbs = "(?:arrive|arriverai|serai|suis|passe|passerai|vais|irai|retourne|retournerai)"
        let leaveVerbs = "(?:pars|partirai|repars|sors|sortirai)"
        return [
            make("\\b(?:quand|lorsque|dès que|des que|aussitôt que|aussitot que)\\s+\(me)\(arriveVerbs)\\s+(?:rendue?\\s+)?",
                 .arrive, toward),
            make("\\b(?:la\\s+)?prochaine fois que\\s+\(me)\(arriveVerbs)\\s+", .arrive, toward),
            make("\\ben\\s+(?:arrivant|passant)\\s+", .arrive, toward),
            make("\\bune fois\\s+(?:rendue?s?|arrivée?s?)\\s+", .arrive, toward),
            make("(?:^|[,.;:!?]\\s*)rendue?\\s+", .arrive, toward),
            make("\\b(?:quand|lorsque|dès que|des que|aussitôt que|aussitot que)\\s+\(me)\(leaveVerbs)\\s+", .leave, away),
            make("\\ben\\s+(?:partant|sortant)\\s+", .leave, away),
            make("\\b(?:quand|lorsque|dès que|des que)\\s+\(me)(?:quitte|quitterai)\\s+", .leave, quitting),
            make("\\ben\\s+quittant\\s+", .leave, quitting),
            make("\\b(?:when|once|as soon as|next time|whenever)\\s+i(?:'m|\\s+am)?\\s+(?:get|arrive|go|stop by|stop|reach|come)?\\s*(?:back\\s+)?",
                 .arrive, englishToward),
            make("\\b(?:when|once|as soon as|before)\\s+i(?:'m|\\s+am)?\\s+(?:leave|leaving|exit|get out of)\\s+", .leave,
                 englishAway),
        ]
    }()

    /// Ces mots après « au », « à la »… ne sont pas des lieux (« au bout », « à l'aise », « à la fin »).
    static let notPlaces: Set<String> = [
        "aise", "heure", "instant", "avance", "occasion", "envers", "bout", "point", "moins", "plus", "cas", "fond",
        "debut", "lieu", "final", "fin", "travers", "temps", "peu", "nouveau", "chaque", "meme", "demain", "soir", "matin",
        "midi", "retard", "rien", "tout", "milieu", "courant", "sujet", "propos", "sec", "pied", "velo", "jour", "limite",
        "suite", "moment", "fois", "mieux", "pire", "rendez-vous", "the", "a", "an", "tomorrow", "tonight", "today",
        "back", "there", "it", "that", "this", "up", "out", "done", "ready", "sure",
    ]
    /// Sans petit mot, en anglais : « when I get home », « when I leave work ».
    static let bareEnglish: Set<String> = ["home", "work", "school", "church", "office", "campus"]
    static let home: Set<String> = ["nous", "moi", "maison", "home", "chez nous", "chez moi"]
    static let possessives: Set<String> = ["mon", "ma", "mes", "ton", "ta", "notre", "nos", "my", "our"]
    /// Un mot en majuscule qui n'allonge pas le nom (« Costco Rappelle-moi »).
    static let stopWords: Set<String> = [
        "rappelle", "rappelle-moi", "rappeler", "acheter", "achète", "achete", "faut", "il", "je", "j", "pour", "et", "puis",
        "pis", "then", "and", "remind", "pick", "buy", "call", "appeler", "demander", "prendre", "passer", "dire", "penser",
    ]

    public static func parse(_ text: String) -> ParsedPlaceTrigger? {
        let cleaned = text.replacingOccurrences(of: "’", with: "'")
        let whole = NSRange(cleaned.startIndex..., in: cleaned)
        var found: [(position: Int, trigger: ParsedPlaceTrigger)] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: cleaned, range: whole) {
                guard let end = Range(match.range, in: cleaned)?.upperBound else { continue }
                let rest = cleaned[end...].prefix { !",.;:!?\n«»\"()".contains($0) }
                if let place = place(in: String(rest), prepositions: pattern.prepositions) {
                    found.append((position: match.range.location, trigger: ParsedPlaceTrigger(place: place, event: pattern.event)))
                    break
                }
            }
        }
        return found.min { $0.position < $1.position }?.trigger
    }

    /// Le lieu au début de `rest`, après l'un des petits mots permis.
    static func place(in rest: String, prepositions: [String]) -> String? {
        let lower = rest.lowercased()
        for preposition in prepositions {
            let elided = preposition.hasSuffix("'")
            let prefix = preposition.isEmpty || elided ? preposition : preposition + " "
            guard lower.hasPrefix(prefix) else { continue }
            let tokens = rest.dropFirst(prefix.count).split(whereSeparator: \.isWhitespace).map(String.init)
            guard let first = tokens.first else { continue }
            let firstKey = key(first)
            if home.contains(firstKey) && (preposition == "chez" || firstKey == "maison" || firstKey == "home") {
                return "Maison"
            }
            guard !notPlaces.contains(firstKey) else { return nil }
            let english = prepositions == englishToward || prepositions == englishAway
            if preposition.isEmpty && english {
                // « when I get home », « when I leave work » ; jamais « when I see Marc ».
                guard bareEnglish.contains(firstKey) else { return nil }
            } else if ["à", "a", "at", "to", "in", "by", ""].contains(preposition) && !isCapitalized(first)
                        && !(english && bareEnglish.contains(firstKey)) {
                // « quand j'arrive à dormir », « à travers » : un « à » nu n'introduit qu'un nom propre (« à Laval »).
                return nil
            }
            var words = [first]
            var index = 1
            if possessives.contains(firstKey), tokens.count > 1 {
                words.append(tokens[1])
                index = 2
            }
            // Un nom en plusieurs mots : « Canadian Tire », « Costco Laval », « Marché Jean-Talon ».
            while index < tokens.count, words.count < 4 {
                let token = tokens[index]
                guard isCapitalized(token), !stopWords.contains(key(token)) else { break }
                words.append(token)
                index += 1
            }
            let name = words.joined(separator: " ")
            guard EntityName.isAcceptable(name) else { return nil }
            return name
        }
        return nil
    }

    static func key(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CA"))
            .lowercased()
            .trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: "-")).inverted)
    }

    static func isCapitalized(_ word: String) -> Bool {
        word.first.map { $0.isUppercase || $0.isNumber } ?? false
    }
}

/// L'adresse d'un lieu : un cercle autour d'un point (table `place_location`).
public struct PlaceLocation: Codable, Sendable, Equatable {
    public var entityID: UUID
    public var latitude: Double
    public var longitude: Double
    /// Rayon en mètres.
    public var radius: Double
    /// L'adresse lisible (« 123, rue Inventée »), si elle est connue.
    public var label: String?
    public var updatedAt: Date

    public init(entityID: UUID, latitude: Double, longitude: Double, radius: Double, label: String?, updatedAt: Date) {
        self.entityID = entityID
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.label = label
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, radius, label
        case entityID = "entity_id"
        case updatedAt = "updated_at"
    }
}

/// Une note qui attend un lieu (table `place_trigger`, une par note).
public struct PlaceTrigger: Codable, Sendable, Equatable {
    public var memoryID: UUID
    public var entityID: UUID
    public var event: PlaceEvent
    public var origin: AssignmentOrigin
    public var createdAt: Date

    public init(memoryID: UUID, entityID: UUID, event: PlaceEvent, origin: AssignmentOrigin, createdAt: Date) {
        self.memoryID = memoryID
        self.entityID = entityID
        self.event = event
        self.origin = origin
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case event, origin
        case memoryID = "memory_id"
        case entityID = "entity_id"
        case createdAt = "created_at"
    }
}

/// Ce que l'iPhone surveille : les notes vivantes dont le lieu a une adresse.
public enum PlaceReminderPlanner {
    public static let identifierPrefix = "engram.place."
    /// iOS surveille au plus 20 régions par app.
    public static let maximum = 20

    public struct Coordinates: Sendable, Equatable {
        public let latitude: Double
        public let longitude: Double
        public let radius: Double

        public init(latitude: Double, longitude: Double, radius: Double) {
            self.latitude = latitude
            self.longitude = longitude
            self.radius = radius
        }
    }

    public struct Item: Sendable, Equatable {
        public let memoryID: UUID
        public let title: String
        public let status: MemoryStatus
        /// Note gardée sur l'iPhone (secrète), ou Engram verrouillé : rien sur l'écran verrouillé.
        public let isPrivate: Bool
        public let placeID: UUID
        public let placeName: String
        public let event: PlaceEvent
        public let location: Coordinates?
        /// Les autres succursales trouvées toutes seules (P30) : n'importe laquelle prévient.
        public let branches: [Coordinates]
        public let createdAt: Date

        public init(memoryID: UUID, title: String, status: MemoryStatus, isPrivate: Bool, placeID: UUID, placeName: String,
                    event: PlaceEvent, location: Coordinates?, branches: [Coordinates] = [], createdAt: Date) {
            self.branches = branches
            self.memoryID = memoryID
            self.title = title
            self.status = status
            self.isPrivate = isPrivate
            self.placeID = placeID
            self.placeName = placeName
            self.event = event
            self.location = location
            self.createdAt = createdAt
        }
    }

    public struct Planned: Sendable, Equatable {
        public let identifier: String
        public let memoryID: UUID
        public let title: String
        public let body: String
        public let event: PlaceEvent
        public let latitude: Double
        public let longitude: Double
        public let radius: Double
    }

    /// Les notes vivantes dont le lieu a une adresse, les plus récentes d'abord ; une note privée ne dit rien.
    /// Chaque succursale (P30) compte pour une région : au plus `limit` régions en tout.
    public static func plan(_ items: [Item], limit: Int = maximum) -> [Planned] {
        let watched = items
            .filter { ($0.status == .active || $0.status == .unsorted) && $0.location != nil }
            .sorted { ($0.createdAt, $0.memoryID.uuidString) > ($1.createdAt, $1.memoryID.uuidString) }
        var planned: [Planned] = []
        for item in watched {
            guard let location = item.location else { continue }
            for (index, spot) in ([location] + item.branches).enumerated() {
                guard planned.count < limit else { return planned }
                planned.append(Planned(
                    identifier: identifierPrefix + item.memoryID.uuidString + (index == 0 ? "" : ".\(index + 1)"),
                    memoryID: item.memoryID, title: item.isPrivate ? "Rappel Engram" : item.placeName,
                    body: item.isPrivate ? "Ouvre Engram pour le voir." : item.title, event: item.event,
                    latitude: spot.latitude, longitude: spot.longitude, radius: spot.radius))
            }
        }
        return planned
    }
}
