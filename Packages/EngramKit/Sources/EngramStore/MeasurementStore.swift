import EngramCore
import Foundation
import GRDB

/// P10 — les suivis : les mesures des notes, relevées au classement et au lancement de l'app. Une note à la corbeille
/// sort des graphiques ; supprimée pour de bon, ses mesures disparaissent avec elle.
public struct MeasurementStore: Sendable {
    public let database: AppDatabase
    public let dates: any DateProvider
    public let calendar: Calendar

    public init(database: AppDatabase, dates: any DateProvider = SystemDateProvider(), calendar: Calendar = .current) {
        self.database = database
        self.dates = dates
        self.calendar = calendar
    }

    /// Une ligne de la liste des mesures d'un suivi, avec sa note.
    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let memoryID: UUID
        public let title: String
        public let date: Date
        public let value: Double
        public let secondValue: Double?
        public let unit: String
    }

    /// Les notes qui comptent : vivantes ou faites, jamais la corbeille ni les dictées qui attendent leur vérification.
    static let countedNotes = """
        m.status IN ('active','unsorted','archived')
        AND m.source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)
        """

    // MARK: - Lecture

    public func measurements(for memoryID: UUID) throws -> [MetricMeasurement] {
        try database.writer.read { db in
            try MetricMeasurement.filter(Column("memory_id") == memoryID).order(Column("measured_at")).fetchAll(db)
        }
    }

    public func measurementsStream(for memoryID: UUID) -> AsyncThrowingStream<[MetricMeasurement], any Error> {
        database.stream { db in
            try MetricMeasurement.filter(Column("memory_id") == memoryID).order(Column("measured_at")).fetchAll(db)
        }
    }

    /// Les points d'un graphique, du plus ancien au plus récent ; le poids dans l'unité choisie (« lb » ou « kg »).
    public func points(metric: Metric, weightUnit: String) throws -> [MetricPoint] {
        try database.writer.read { db in try Self.points(db, metric: metric, weightUnit: weightUnit) }
    }

    public func pointsStream(metric: Metric, weightUnit: String) -> AsyncThrowingStream<[MetricPoint], any Error> {
        database.stream { db in try Self.points(db, metric: metric, weightUnit: weightUnit) }
    }

    static func points(_ db: Database, metric: Metric, weightUnit: String) throws -> [MetricPoint] {
        try rows(db, metric: metric).map { measurement, _ in
            let (value, second, _) = converted(measurement, weightUnit: weightUnit)
            return MetricPoint(date: measurement.measuredAt, value: value, secondValue: second)
        }
    }

    /// Chaque mesure d'un suivi avec sa note, de la plus récente à la plus ancienne.
    public func entries(metric: Metric, weightUnit: String) throws -> [Entry] {
        try database.writer.read { db in try Self.entries(db, metric: metric, weightUnit: weightUnit) }
    }

    public func entriesStream(metric: Metric, weightUnit: String) -> AsyncThrowingStream<[Entry], any Error> {
        database.stream { db in try Self.entries(db, metric: metric, weightUnit: weightUnit) }
    }

    static func entries(_ db: Database, metric: Metric, weightUnit: String) throws -> [Entry] {
        try rows(db, metric: metric).reversed().map { measurement, title in
            let (value, second, unit) = converted(measurement, weightUnit: weightUnit)
            return Entry(id: measurement.id, memoryID: measurement.memoryID, title: title, date: measurement.measuredAt,
                         value: value, secondValue: second, unit: unit)
        }
    }

    /// Les suivis qui ont au moins une mesure, dans l'ordre habituel (poids, sommeil, tension…).
    public func metricsWithData() throws -> [Metric] {
        try database.writer.read { db in try Self.metricsWithData(db) }
    }

    public func metricsStream() -> AsyncThrowingStream<[Metric], any Error> {
        database.stream { db in try Self.metricsWithData(db) }
    }

    static func metricsWithData(_ db: Database) throws -> [Metric] {
        let present = Set(try String.fetchAll(db, sql: """
            SELECT DISTINCT ms.metric FROM measurement ms JOIN memory m ON m.id = ms.memory_id WHERE \(countedNotes)
            """).compactMap(Metric.init(rawValue:)))
        return Metric.allCases.filter { present.contains($0) }
    }

    static func rows(_ db: Database, metric: Metric) throws -> [(MetricMeasurement, String)] {
        try Row.fetchAll(db, sql: """
            SELECT ms.*, m.title AS note_title FROM measurement ms JOIN memory m ON m.id = ms.memory_id
            WHERE ms.metric = ? AND \(countedNotes)
            ORDER BY ms.measured_at, ms.created_at
            """, arguments: [metric.rawValue]).map { row in (try MetricMeasurement(row: row), row["note_title"]) }
    }

    /// Le poids dans l'unité choisie ; les autres mesures telles quelles.
    static func converted(_ measurement: MetricMeasurement, weightUnit: String) -> (Double, Double?, String) {
        guard measurement.metric == .weight, measurement.unit != weightUnit else {
            return (measurement.value, measurement.secondValue, measurement.unit)
        }
        let value = weightUnit == "kg" ? MetricUnits.kilograms(fromPounds: measurement.value)
                                       : MetricUnits.pounds(fromKilograms: measurement.value)
        return (value, nil, weightUnit)
    }

    // MARK: - Relevé

    /// Relit le texte d'une note et remplace ses mesures. Renvoie le nombre de mesures gardées.
    @discardableResult
    func record(_ db: Database, memoryID: UUID, text: String, capturedAt: Date, now: Date) throws -> Int {
        try MetricMeasurement.filter(Column("memory_id") == memoryID).deleteAll(db)
        let found = MeasurementParser.parse(text)
        for parsed in found {
            let measuredAt = calendar.date(byAdding: .day, value: -parsed.daysBefore, to: capturedAt) ?? capturedAt
            try MetricMeasurement(memoryID: memoryID, metric: parsed.metric, value: parsed.value,
                                  secondValue: parsed.secondValue, unit: parsed.unit, measuredAt: measuredAt, now: now)
                .insert(db)
        }
        return found.count
    }

    /// Au lancement et au retour dans l'app : les notes nouvelles ou modifiées depuis `since` (toutes si nil) dont les
    /// mesures ne sont pas à jour. Le texte est lu hors du verrou de la base ; seules les notes qui changent sont
    /// écrites. Renvoie le nombre de mesures ajoutées. Tout se passe sur l'iPhone.
    public func backfill(since: Date? = nil) throws -> Int {
        let now = dates.now()
        // Les habitudes (P17) sont relues en même temps ; le nombre renvoyé reste celui des mesures.
        try backfillHabits(since: since)
        let (notes, measured) = try database.writer.read { db in
            (try Memory.fetchAll(db, sql: """
                SELECT m.* FROM memory m
                WHERE \(Self.countedNotes) AND (? IS NULL OR m.updated_at > ?)
                  AND NOT EXISTS (SELECT 1 FROM measurement ms WHERE ms.memory_id = m.id AND ms.created_at >= m.updated_at)
                """, arguments: [since, since]),
             Set(try UUID.fetchAll(db, sql: "SELECT DISTINCT memory_id FROM measurement")))
        }
        // La reconnaissance (des expressions régulières) se fait sans bloquer la base ; une note sans mesure, ni
        // avant ni maintenant, n'est pas écrite.
        let changed = notes.filter {
            !MeasurementParser.parse($0.content).isEmpty || measured.contains($0.id) || !GoalParser.parse($0.content).isEmpty
        }
        guard !changed.isEmpty else { return 0 }
        return try database.writer.write { db in
            try changed.reduce(0) { total, memory in
                // Les objectifs dits dans une ancienne note sont repris aussi (P11).
                try recordGoals(db, memoryID: memory.id, text: memory.content, capturedAt: memory.capturedAt)
                return total + (try record(db, memoryID: memory.id, text: memory.content, capturedAt: memory.capturedAt,
                                           now: now))
            }
        }
    }
}
