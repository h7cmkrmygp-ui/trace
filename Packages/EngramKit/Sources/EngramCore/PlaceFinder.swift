import Foundation

/// P30 — l'adresse d'un lieu trouvée toute seule : parmi les résultats d'une recherche autour du propriétaire, les
/// succursales les plus proches (« quand j'arrive au Costco » : n'importe quel Costco des environs). Un lieu à soi
/// (la maison, le bureau, chez Julie) ne se cherche jamais.
public enum PlaceFinder {
    public struct Point: Sendable, Equatable {
        public let latitude: Double
        public let longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public struct Result: Sendable, Equatable {
        public let name: String
        public let address: String?
        public let latitude: Double
        public let longitude: Double

        public init(name: String, address: String?, latitude: Double, longitude: Double) {
            self.name = name
            self.address = address
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// Des lieux à soi : une recherche trouverait celui de quelqu'un d'autre.
    static let personal: Set<String> = [
        "maison", "nous", "moi", "home", "bureau", "travail", "job", "work", "office", "chalet", "ecole",
        "school", "garderie", "appartement", "appart", "condo", "garage", "gym", "cour", "sous sol",
    ]

    /// Peut-on chercher ce lieu ? Jamais un lieu à soi, ni le nom d'une personne connue (« chez Julie »).
    public static func canSearch(_ placeName: String, people: [String]) -> Bool {
        let key = EntityName.key(placeName)
        guard key.count >= 2, !personal.contains(key) else { return false }
        return !people.contains { EntityName.key($0) == key }
    }

    /// Les `maximum` résultats les plus proches à moins de `distance` mètres ; ceux dont le nom contient le lieu
    /// (« Costco Laval » pour « Costco ») passent d'abord, sinon (un mot général comme « pharmacie ») tout ce qui a été
    /// trouvé. Deux résultats à moins de 100 m l'un de l'autre n'en font qu'un.
    public static func choose(_ results: [Result], near point: Point, placeName: String, maximum: Int = 3,
                              within distance: Double = 40_000) -> [Result] {
        let measured = results
            .map { (result: $0, metres: self.distance(point, Point(latitude: $0.latitude, longitude: $0.longitude))) }
            .filter { $0.metres <= distance }
        let key = EntityName.key(placeName)
        let named = measured.filter { EntityName.key($0.result.name).contains(key) }
        var chosen: [Result] = []
        for candidate in (named.isEmpty ? measured : named).sorted(by: { $0.metres < $1.metres }) {
            guard chosen.count < maximum else { break }
            let spot = Point(latitude: candidate.result.latitude, longitude: candidate.result.longitude)
            let duplicate = chosen.contains {
                self.distance(spot, Point(latitude: $0.latitude, longitude: $0.longitude)) < 100
            }
            if !duplicate { chosen.append(candidate.result) }
        }
        return chosen
    }

    /// La distance à vol d'oiseau, en mètres.
    public static func distance(_ first: Point, _ second: Point) -> Double {
        let radius = 6_371_000.0
        let lat1 = first.latitude * .pi / 180
        let lat2 = second.latitude * .pi / 180
        let dLat = (second.latitude - first.latitude) * .pi / 180
        let dLon = (second.longitude - first.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
