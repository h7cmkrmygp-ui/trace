import EngramCore
import Foundation
import GRDB

public enum AssignmentOutcome: Sendable, Equatable {
    case assigned
    case alreadyAssigned
    /// Le propriétaire avait retiré ce lien : l'IA ne le recrée pas.
    case skippedRejectedByUser
}

/// Un lien souvenir ↔ catégorie ou tag.
protocol AssignmentRow: FetchableRecord, PersistableRecord {
    var origin: AssignmentOrigin { get set }
    var confirmed: Bool { get set }
    var rejected: Bool { get set }
    var updatedAt: Date { get set }
}

extension CategoryAssignment: AssignmentRow {}
extension TagAssignment: AssignmentRow {}

/// Règle « le propriétaire décide » : l'IA n'écrase jamais un choix du propriétaire.
enum AssignmentRules {
    static func assign<Row: AssignmentRow>(
        _ db: Database, existing: Row?, makeNew: () -> Row, origin: AssignmentOrigin, now: Date
    ) throws -> AssignmentOutcome {
        guard var row = existing else {
            try makeNew().insert(db)
            return .assigned
        }
        switch origin {
        case .ai:
            return row.rejected ? .skippedRejectedByUser : .alreadyAssigned
        case .user:
            if row.origin == .user && row.confirmed { return .alreadyAssigned }
            row.origin = .user
            row.confirmed = true
            row.rejected = false
            row.updatedAt = now
            try row.update(db)
            return .assigned
        }
    }

    /// Retrait par le propriétaire : le lien est gardé comme « rejeté ». Retrait par l'IA : seulement ses propres liens non confirmés.
    static func remove<Row: AssignmentRow>(_ db: Database, row: Row, by origin: AssignmentOrigin, now: Date) throws {
        var row = row
        switch origin {
        case .user:
            row.origin = .user
            row.confirmed = false
            row.rejected = true
            row.updatedAt = now
            try row.update(db)
        case .ai:
            guard row.origin == .ai, !row.confirmed, !row.rejected else { throw StoreError.protectedByUser }
            _ = try row.delete(db)
        }
    }

    static func confirm<Row: AssignmentRow>(_ db: Database, row: Row, now: Date) throws {
        var row = row
        row.origin = .user
        row.confirmed = true
        row.rejected = false
        row.updatedAt = now
        try row.update(db)
    }
}
