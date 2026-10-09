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
        let memoryStore = MemoryStore(database: database, dates: dates, calendar: calendar)
        let categoryStore = CategoryStore(database: database, dates: dates)
        let entityStore = EntityStore(database: database, dates: dates)
        let listStore = ListStore(database: database, dates: dates)
        let measurementStore = MeasurementStore(database: database, dates: dates, calendar: calendar)
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
                    if let root = chain.first, let description = thought.categoryDescription {
                        try categoryStore.describeIfMissing(db, categoryID: root.id, description: description, now: now)
                    }
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
                // Les personnes et les lieux de la pensée (P9).
                try entityStore.linkNames(db, people: thought.people, places: thought.places, to: memoryID, now: now)
            }

            if kept.isEmpty {
                if keepUntouched { filedIDs.append(contentsOf: untouched.map(\.id)) }
                for thought in thoughts {
                    // « ajoute du lait à ma liste d'épicerie » : la liste est complétée, sans nouvelle note (P15).
                    if let command = ListCommandParser.parse(thought.excerpt) {
                        let list = try listStore.add(db, command, sourceID: sourceID, excerpt: thought.excerpt,
                                                     memoryStore: memoryStore, now: now)
                        if list.created { try classify(list.memory.id, with: thought) }
                        if !filedIDs.contains(list.memory.id) { filedIDs.append(list.memory.id) }
                        continue
                    }
                    let due = DateResolver.firstDate(in: thought.mentionedDates, excerpt: thought.excerpt,
                                                     relativeTo: source.capturedAt, calendar: calendar)
                    // « aujourd'hui », « demain »… deviennent la vraie date dans le titre et le texte rédigé ; les mots
                    // exacts de la dictée (contenu, extrait) restent tels quels.
                    let title = TitleMaker.fallbackTitle(
                        from: RelativeDateWording.anchored(thought.title, on: source.capturedAt, calendar: calendar))
                    let summary = thought.summary.map {
                        RelativeDateWording.anchored($0, on: source.capturedAt, calendar: calendar)
                    }
                    let draft = MemoryDraft(
                        sourceID: sourceID, excerpt: thought.excerpt, spanStart: thought.spanStart, spanEnd: thought.spanEnd,
                        spanTextVersion: source.correctedText == nil ? .original : .corrected,
                        title: title, summary: summary, content: thought.excerpt, kind: thought.kind,
                        status: .unsorted, mentionedDates: thought.mentionedDates, analysisVersion: Self.analysisVersion,
                        dueAt: due?.date, dueHasTime: due?.hasTime ?? false)
                    let memory = try memoryStore.createMemory(db, draft: draft, actor: .ai, now: now)
                    try classify(memory.id, with: thought)
                    // Les mesures dites (« je pèse 162,5 livres ») vont dans les suivis (P10).
                    try measurementStore.record(db, memoryID: memory.id, text: thought.excerpt, capturedAt: source.capturedAt,
                                                now: now)
                    // « Mon objectif : 155 livres » fixe l'objectif du suivi (P11).
                    try measurementStore.recordGoals(db, memoryID: memory.id, text: thought.excerpt,
                                                     capturedAt: source.capturedAt)
                    // « quand j'arrive chez Costco » : le rappel attend le lieu (P14).
                    try entityStore.recordPlaceTrigger(db, memoryID: memory.id, text: thought.excerpt, now: now)
                    filedIDs.append(memory.id)
                }
            } else {
                // Le propriétaire a déjà touché sa note : on ne la remplace pas. Si elle est encore en usage,
                // on la classe seulement ; si elle est archivée ou à la corbeille, on n'y touche pas du tout.
                for memory in kept {
                    if memory.status == .active || memory.status == .unsorted, let first = thoughts.first {
                        try classify(memory.id, with: first)
                        // Le texte du propriétaire n'est pas touché, mais l'échéance dictée est posée si la note n'en a pas.
                        if memory.dueAt == nil, var current = try Memory.fetchOne(db, key: memory.id),
                           let due = DateResolver.firstDate(in: first.mentionedDates, excerpt: first.excerpt,
                                                            relativeTo: source.capturedAt, calendar: calendar) {
                            current.dueAt = due.date
                            current.dueHasTime = due.hasTime
                            current.updatedAt = now
                            try current.update(db)
                        }
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

    /// Modifiée par le propriétaire : texte modifié, archivée ou à la corbeille, catégorie ou tag posé ou retiré à la main,
    /// ou reliée à un événement du calendrier de l'iPhone (la remplacer créerait un doublon d'événement).
    /// Une note classée par l'IA et laissée telle quelle n'est pas « touchée » : elle peut être reclassée.
    static func isTouchedByOwner(_ db: Database, _ memory: Memory) throws -> Bool {
        if memory.userEdited || memory.status == .archived || memory.status == .trashed { return true }
        return try Bool.fetchOne(db, sql: """
            SELECT EXISTS(SELECT 1 FROM memory_category WHERE memory_id = ? AND origin = 'user')
                OR EXISTS(SELECT 1 FROM memory_tag WHERE memory_id = ? AND origin = 'user')
                OR EXISTS(SELECT 1 FROM calendar_link WHERE memory_id = ?)
            """, arguments: [memory.id, memory.id, memory.id]) ?? false
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
