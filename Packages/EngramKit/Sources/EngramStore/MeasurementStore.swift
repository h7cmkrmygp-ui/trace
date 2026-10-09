import EngramCore
import Foundation
import GRDB

/// P10 — les suivis : les mesures des notes, relevées au classement et au lancement de l'app.
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

    public func measurements(for memoryID: UUID) throws -> [Measurement] { [] }

    public func points(metric: Metric, weightUnit: String) throws -> [MetricPoint] { [] }

    public func entries(metric: Metric, weightUnit: String) throws -> [Entry] { [] }

    public func metricsWithData() throws -> [Metric] { [] }

    public func backfill() throws -> Int { 0 }
}
