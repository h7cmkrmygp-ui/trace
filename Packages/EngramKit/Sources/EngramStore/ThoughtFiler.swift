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

    /// Part minimale du texte que les extraits doivent couvrir pour remplacer la note provisoire.
    public static let minimumCoverage = 0.6

    /// - Parameters:
    ///   - keepInterimIfUncovered: garder la note provisoire (texte complet, « À classer ») si les extraits
    ///     couvrent moins de `minimumCoverage` du texte.
    ///   - forceKeepInterim: la garder quoi qu'il arrive (des pensées ont été rejetées par le validateur).
    public func file(_ thoughts: [ValidThought], sourceID: UUID, keepInterimIfUncovered: Bool = false,
                     forceKeepInterim: Bool = false) throws -> FilingSummary {
        let now = dates.now()
        let memoryStore = MemoryStore(database: database, dates: dates)
        let categoryStore = CategoryStore(database: database, dates: dates)
        return try database.writer.write { db in
            guard var source = try Source.fetchOne(db, key: sourceID) else { throw StoreError.notFound }
            // Déjà classée (traitement en double) : rien ne change.
            if source.processingStatus == .done {
                let existing = try Memory.filter(Column("source_id") == sourceID).order(Column("created_at")).fetchAll(db)
                return FilingSummary(memories: existing, categoryPaths: [], pathByMemory: [:])
            }
            let interims = try Memory
                .filter(Column("source_id") == sourceID && Column("analysis_version") == MemoryStore.interimAnalysisVersion)
                .fetchAll(db)
            // Une note provisoire que le propriétaire a touchée (texte, statut, catégorie, tag) n'est jamais remplacée.
            var touched: [Memory] = []
            var untouched: [Memory] = []
            for memory in interims {
                if try Self.isTouchedByOwner(db, memory) { touched.append(memory) } else { untouched.append(memory) }
            }
            let coverage = AnalysisValidator.coverage(of: thoughts.map(\.excerpt), in: source.referenceText ?? "")
            let keepUntouched = forceKeepInterim || (keepInterimIfUncovered && coverage < Self.minimumCoverage)
            if touched.isEmpty && !keepUntouched {
                for memory in untouched { _ = try memory.delete(db) }
            }
            let kept = touched

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
                if keepUntouched { filedIDs.append(contentsOf: untouched.map(\.id)) }
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
                // Le propriétaire a déjà touché sa note : on ne la remplace pas. Si elle est encore en usage,
                // on la classe seulement ; si elle est archivée ou à la corbeille, on n'y touche pas du tout.
                for memory in kept {
                    if memory.status == .active || memory.status == .unsorted, let first = thoughts.first {
                        try classify(memory.id, with: first)
                    }
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

    /// Texte modifié, statut changé (archive, corbeille, classée), ou catégorie/tag posé ou retiré à la main.
    static func isTouchedByOwner(_ db: Database, _ memory: Memory) throws -> Bool {
        if memory.userEdited || memory.status != .unsorted { return true }
        return try Bool.fetchOne(db, sql: """
            SELECT EXISTS(SELECT 1 FROM memory_category WHERE memory_id = ? AND origin = 'user')
                OR EXISTS(SELECT 1 FROM memory_tag WHERE memory_id = ? AND origin = 'user')
            """, arguments: [memory.id, memory.id]) ?? false
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
