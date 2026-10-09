import Foundation

/// P30 — l'adresse d'un lieu trouvée toute seule.
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

    public static func choose(_ results: [Result], near point: Point, placeName: String, maximum: Int = 3,
                              within distance: Double = 40_000) -> [Result] { [] }

    public static func canSearch(_ placeName: String, people: [String]) -> Bool { true }

    public static func distance(_ first: Point, _ second: Point) -> Double { 0 }
}
