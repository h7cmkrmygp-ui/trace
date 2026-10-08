import EngramCore
import Foundation
import GRDB

/// Ce qui a été classé pour une source.
public struct FilingSummary: Sendable, Equatable {
    public let memories: [Memory]
    /// Chemins de catégories posés, sans doublon, dans l'ordre des pensées.
    public let categoryPaths: [String]
    /// Chemin posé sur chaque souvenir (absent = « À classer »).
    public let pathByMemory: [UUID: String]
}

/// Range les pensées validées d'une source, en **une seule transaction** :
/// les souvenirs provisoires sont remplacés (sauf ceux modifiés à la main), les catégories manquantes créées,
/// les liens et tags posés (origine IA), puis la source marquée « traitée ».
public struct ThoughtFiler: Sendable {
    public static let analysisVersion = "p2-v1"

    public let database: AppDatabase
    public let dates: any DateProvider
    /// Calendrier (fuseau) utilisé pour calculer les échéances.
    public let calendar: Calendar

    public init(database: AppDatabase, dates: any DateProvider = SystemDateProvider(), calendar: Calendar = .current) {
        self.database = database
        self.dates = dates
        self.calendar = calendar
    }

    public func file(_ thoughts: [ValidThought], sourceID: UUID) throws -> FilingSummary {
        let now = dates.now()
        let memoryStore = MemoryStore(database: database, dates: dates)
        let categoryStore = CategoryStore(database: database, dates: dates)
        return try database.writer.write { db in
            guard var source = try Source.fetchOne(db, key: sourceID) else { throw StoreError.notFound }
            let interims = try Memory
                .filter(Column("source_id") == sourceID && Column("analysis_version") == MemoryStore.interimAnalysisVersion)
                .fetchAll(db)
            let kept = interims.filter(\.userEdited)
            for memory in interims where !memory.userEdited { _ = try memory.delete(db) }

            var filedIDs: [UUID] = []
            var paths: [String] = []
            var pathByMemory: [UUID: String] = [:]

            func classify(_ memoryID: UUID, with thought: ValidThought) throws {
                if !thought.categoryPath.isEmpty {
                    let chain = try categoryStore.resolveChain(db, names: thought.categoryPath, origin: .ai, now: now)
                    if let target = chain.last {
                        let outcome = try categoryStore.assign(db, memoryID: memoryID, categoryID: target.id,
                                                               origin: .ai, confidence: nil, now: now)
                        if outcome != .skippedRejectedByUser {
                            let display = CategoryPaths.display(chain.map(\.name))
                            pathByMemory[memoryID] = display
                            if !paths.contains(display) { paths.append(display) }
                        }
                    }
                }
                for name in thought.tags {
                    guard let tag = try? categoryStore.upsertTag(db, name: name, origin: .ai, now: now) else { continue }
                    _ = try categoryStore.tag(db, memoryID: memoryID, tagID: tag.id, origin: .ai, confidence: nil, now: now)
                }
            }

            if kept.isEmpty {
                for thought in thoughts {
                    let due = DateResolver.firstDate(in: thought.mentionedDates, excerpt: thought.excerpt,
                                                     relativeTo: source.capturedAt, calendar: calendar)
                    let draft = MemoryDraft(
                        sourceID: sourceID, excerpt: thought.excerpt, spanStart: thought.spanStart, spanEnd: thought.spanEnd,
                        spanTextVersion: source.correctedText == nil ? .original : .corrected,
                        title: thought.title, summary: thought.summary, content: thought.excerpt, kind: thought.kind,
                        status: .unsorted, mentionedDates: thought.mentionedDates, analysisVersion: Self.analysisVersion,
                        dueAt: due?.date, dueHasTime: due?.hasTime ?? false)
                    let memory = try memoryStore.createMemory(db, draft: draft, actor: .ai, now: now)
                    try classify(memory.id, with: thought)
                    filedIDs.append(memory.id)
                }
            } else {
                // Le propriétaire a déjà modifié sa note : on ne la remplace pas, on la classe seulement.
                for memory in kept {
                    if let first = thoughts.first { try classify(memory.id, with: first) }
                    filedIDs.append(memory.id)
                }
            }

            source.processingStatus = .done
            source.updatedAt = now
            try source.update(db)
            let memories = try filedIDs.compactMap { try Memory.fetchOne(db, key: $0) }
            return FilingSummary(memories: memories, categoryPaths: paths, pathByMemory: pathByMemory)
        }
    }

    /// Repli : l'analyse a échoué. Le souvenir provisoire reste « À classer » et la source est close.
    public func markFallback(sourceID: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard var source = try Source.fetchOne(db, key: sourceID) else { throw StoreError.notFound }
            source.processingStatus = .done
            source.updatedAt = now
            try source.update(db)
        }
    }
}
