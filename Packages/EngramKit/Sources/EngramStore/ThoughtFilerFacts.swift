import EngramCore
import Foundation
import GRDB

extension ThoughtFiler {
    /// F16 — chaque date dite de la note, avec son rôle, sa résolution dans le fuseau de la capture et ce fuseau.
    static func recordTemporal(_ db: Database, memoryID: UUID, mentions: [TemporalMention], capturedAt: Date,
                               calendar: Calendar) throws {
        for (position, mention) in mentions.enumerated() {
            let resolved = DateResolver.resolve(mention.phrase, relativeTo: capturedAt, calendar: calendar)
            try db.execute(sql: """
                INSERT INTO memory_temporal (memory_id, position, role, phrase, resolved_at, has_time, time_zone)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [memoryID, position, mention.role.rawValue, mention.phrase, resolved?.date,
                                 resolved?.hasTime ?? false, calendar.timeZone.identifier])
        }
    }

    /// F21 — combien de jours en arrière une correction cherche la note qu'elle corrige.
    static let correctionWindow: TimeInterval = 180 * 24 * 3_600

    /// F21 — « Finalement le rendez-vous est jeudi », « Correction : le loyer est de 1250 $ » : la seule note du même type,
    /// sur le même sujet, encore actuelle et jamais touchée par le propriétaire, est archivée et reliée à la correction
    /// (l'historique reste). Aucune ou plusieurs cibles possibles, ou une cible protégée : rien ne change, la correction
    /// reste à classer pour que le propriétaire décide.
    @discardableResult
    static func supersede(_ db: Database, with correction: Memory, now: Date) throws -> Bool {
        let words = CorrectionMatch.words(correction.excerpt)
        let candidates = try Memory
            .filter(Column("source_id") != correction.sourceID && Column("id") != correction.id
                    && [MemoryStatus.active.rawValue, MemoryStatus.unsorted.rawValue].contains(Column("status"))
                    && Column("superseded_by") == nil && Column("kind") == correction.kind?.rawValue
                    && Column("captured_at") <= correction.capturedAt
                    && Column("captured_at") >= correction.capturedAt.addingTimeInterval(-correctionWindow))
            .fetchAll(db)
            .filter { CorrectionMatch.same(words, CorrectionMatch.words($0.excerpt)) }
        if candidates.count == 1, var target = candidates.first, !(try isTouchedByOwner(db, target)) {
            target.status = .archived
            target.supersededBy = correction.id
            target.version += 1
            target.updatedAt = now
            try target.update(db)
            try MemoryVersion(memory: target, changedBy: .system, reason: "remplacée par une correction", at: now).insert(db)
            return true
        }
        guard var review = try Memory.fetchOne(db, key: correction.id), review.status != .unsorted else { return false }
        review.status = .unsorted
        review.updatedAt = now
        try review.update(db)
        return false
    }
}
