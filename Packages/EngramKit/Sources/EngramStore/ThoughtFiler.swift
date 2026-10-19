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
    /// P41 — les choses ajoutées à chaque liste (note de la liste → choses), pour le résumé après la dictée.
    public var listAdditions: [UUID: [String]] = [:]
    /// F29 — ce que le rangement a fait, sans aucun mot de la note (pour la trace et le diagnostic).
    public var trace: [String] = []
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
    /// - Parameter route: F13 — la décision de confidentialité, enregistrée dans la même transaction que le classement.
    ///   - expected: F10 — la version analysée de la source ; si elle a changé depuis, rien n'est écrit (`staleRevision`).
    public func file(_ thoughts: [ValidThought], sourceID: UUID, route: AnalysisRoute? = nil, expected: SourceSnapshot? = nil,
                     keepInterimIfUncovered: Bool = false,
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
            // F10 — le résultat doit porter sur la version de la source telle qu'elle est maintenant (texte, révision,
            // confidentialité) : sinon il est obsolète et rien n'est écrit.
            if let expected {
                let current = source.snapshot
                guard current.revision == expected.revision, current.textHash == expected.textHash,
                      current.policyVersion == expected.policyVersion else { throw StoreError.staleRevision }
            }
            // F16 — le calendrier de la capture (son fuseau), pour lire « demain à 9 h » comme le propriétaire l'a dit.
            var captureCalendar = calendar
            if let zone = source.capturedTimeZone.flatMap(TimeZone.init(identifier:)) { captureCalendar.timeZone = zone }
            // F13 — la décision de confidentialité d'abord, dans cette même transaction : aucun dérivé (note, liste,
            // rappel) n'est jamais visible sans elle.
            if let route {
                source.privacyLevel = route.level
                source.privacyBasis = source.keepLocal ? .ownerKeepLocal : route.effectiveBasis
                source.analysisProvider = route.provider
                source.routeReason = route.reason
                source.needsCloudRetry = route.needsCloudRetry
                source.updatedAt = now
                try source.update(db)
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
            // F11, F12 — les notes d'une analyse précédente de cette source (retranscription, nouvel essai) : celles que le
            // propriétaire a modifiées, archivées ou liées au calendrier sont gardées et ne sont pas recréées ; les autres
            // sont remplacées maintenant, d'un coup, par la nouvelle analyse (jamais avant qu'elle réussisse). Une liste reste.
            let listMemoryIDs = Set(try UUID.fetchAll(db, sql: "SELECT memory_id FROM memory_list"))
            var protectedPrevious: [Memory] = []
            for memory in try Memory
                .filter(Column("source_id") == sourceID && Column("status") != MemoryStatus.trashed.rawValue
                        && Column("analysis_version") != MemoryStore.interimAnalysisVersion)
                .fetchAll(db) where !listMemoryIDs.contains(memory.id) {
                if try Self.isTouchedByOwner(db, memory) { protectedPrevious.append(memory) } else { _ = try memory.delete(db) }
            }
            // F05 : chaque passage qu'aucune pensée ne reprend (positions exactes, négations et commandes courtes comprises)
            // reste « À classer », à sa place ; jamais une copie de toute la dictée, et pas pour des « euh ». Sans
            // `keepInterimIfUncovered`, l'ancienne règle s'applique.
            let passages = keepInterimIfUncovered
                ? AnalysisValidator.uncoveredPassages(of: source.referenceText ?? "", thoughts: thoughts) : []
            let keepUntouched = keepInterimIfUncovered ? !passages.isEmpty : forceKeepInterim
            if touched.isEmpty && !keepUntouched {
                for memory in untouched { _ = try memory.delete(db) }
            }
            if touched.isEmpty, !passages.isEmpty {
                for other in untouched.dropFirst() { _ = try other.delete(db) }
                var reusable = untouched.first
                var pieces: [Memory] = []
                let version: TextVersion = source.correctedText == nil ? .original : .corrected
                for passage in passages {
                    if var piece = reusable {
                        reusable = nil
                        piece.content = passage.text
                        piece.excerpt = passage.text
                        piece.title = TitleMaker.fallbackTitle(from: passage.text)
                        piece.spanStart = passage.start
                        piece.spanEnd = passage.end
                        piece.spanTextVersion = version
                        piece.analysisVersion = Self.leftoverAnalysisVersion
                        piece.updatedAt = now
                        try piece.update(db)
                        pieces.append(piece)
                    } else {
                        let draft = MemoryDraft(sourceID: sourceID, excerpt: passage.text, spanStart: passage.start,
                                                spanEnd: passage.end, spanTextVersion: version,
                                                title: TitleMaker.fallbackTitle(from: passage.text), content: passage.text,
                                                status: .unsorted, analysisVersion: Self.leftoverAnalysisVersion)
                        pieces.append(try memoryStore.createMemory(db, draft: draft, actor: .system, now: now))
                    }
                }
                untouched = pieces
            }
            let kept = touched

            var filedIDs: [UUID] = []
            var paths: [String] = []
            var pathByMemory: [UUID: String] = [:]
            var listAdditions: [UUID: [String]] = [:]
            // F29 — ce qui est fait, pensée par pensée, sans aucun mot de la note.
            var trace: [String] = []

            func classify(_ memoryID: UUID, with thought: ValidThought) throws {
                if !thought.categoryPath.isEmpty {
                    // Une fête va dans le dossier des fêtes que le propriétaire a déjà, s'il en a un (P33).
                    let ownFolder = try thought.birthdayOf == nil ? nil : categoryStore.birthdayFolderPath(db)
                    let chain = try categoryStore.resolveChain(db, names: ownFolder ?? thought.categoryPath, origin: .ai, now: now)
                    if ownFolder == nil, let root = chain.first, let description = thought.categoryDescription {
                        try categoryStore.describeIfMissing(db, categoryID: root.id, description: description, now: now)
                    }
                    if let target = chain.last {
                        // La phrase où l'IA explique son choix est gardée avec le lien (P32).
                        let outcome = try categoryStore.assign(db, memoryID: memoryID, categoryID: target.id,
                                                               origin: .ai, confidence: nil, reason: thought.categoryReason,
                                                               now: now)
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

            // F09 — les choses que cette analyse demande, par liste : une analyse précédente de la même dictée qui en avait
            // ajouté d'autres (jamais touchées depuis) les voit retirées à la fin.
            var requestedItems: [UUID: Set<String>] = [:]
            if kept.isEmpty {
                if keepUntouched { filedIDs.append(contentsOf: untouched.map(\.id)) }
                for proposed in thoughts {
                    // F03, F04 — l'intention, sa polarité et la forme de la phrase décident de l'opération ; les analyseurs
                    // de listes ne font que fournir ses arguments. Un dossier dont le rôle ne convient pas est refusé.
                    let plan = ActionPlanner.plan(proposed)
                    var thought = proposed
                    trace.append("pensée : intention \(proposed.intent?.rawValue ?? "inconnue")"
                                 + (plan.review == nil ? "" : ", refus motivé"))
                    if !plan.keepsFolder {
                        trace.append("dossier proposé refusé (rôle incompatible)")
                        thought.categoryPath = []
                        thought.categoryReason = nil
                    }
                    var noteKind = thought.kind
                    var handled = false
                    for operation in plan.operations {
                        switch operation {
                        case .note(let kind):
                            noteKind = kind
                        case .checkInList(let name, let items), .removeFromList(let name, let items):
                            // « coche le lait », « j'ai acheté le pain » : la case est cochée, sans nouvelle note (P19).
                            // « J'ai acheté une tondeuse », sans case qui corresponde, reste une note.
                            var isCheck = false
                            if case .checkInList = operation { isCheck = true }
                            let explicit = ListActionParser.parse(thought.excerpt)?.isExplicit ?? false
                            let action = ListAction(kind: isCheck ? .check : .remove, listName: name, items: items,
                                                    isExplicit: explicit)
                            if let outcome = try listStore.apply(db, action, sourceID: sourceID, now: now),
                               !outcome.changed.isEmpty || explicit || outcome.replayed {
                                if !filedIDs.contains(outcome.memory.id) { filedIDs.append(outcome.memory.id) }
                                trace.append((isCheck ? "cochée dans une liste" : "retirée d'une liste")
                                             + " : \(outcome.changed.count) case(s)")
                                handled = true
                            }
                        case .appendToList(let name, let items):
                            // « ajoute du lait à ma liste d'épicerie » (P15), des choses à recevoir, à acheter ou à offrir
                            // (P41) : elles vont dans leur liste (retrouvée même dite autrement), sans note à part.
                            handled = true
                            // Déjà fait par cette dictée, et la liste jetée depuis par le propriétaire : rien n'est recréé.
                            guard let list = try listStore.add(db, ListCommand(listName: name, items: items),
                                                               sourceID: sourceID, excerpt: thought.excerpt,
                                                               people: thought.people, memoryStore: memoryStore,
                                                               now: now) else { continue }
                            requestedItems[list.memory.id, default: []].formUnion(items.map(ListCommandParser.key))
                            trace.append("ajout à une liste\(list.created ? " (créée)" : "") : \(list.added.count) chose(s)")
                            if list.created {
                                try classify(list.memory.id, with: thought)
                            } else {
                                // « des écouteurs pour Julie » : la liste est reliée à la personne nommée.
                                try entityStore.linkNames(db, people: thought.people, places: thought.places,
                                                          to: list.memory.id, now: now)
                            }
                            if !list.added.isEmpty {
                                listAdditions[list.memory.id, default: []].append(contentsOf: list.added)
                            }
                            if !filedIDs.contains(list.memory.id) { filedIDs.append(list.memory.id) }
                        }
                    }
                    if handled { continue }
                    // F11 — la même intention qu'une note gardée d'une analyse précédente : elle n'est pas recréée à côté.
                    if let match = protectedPrevious.first(where: { IntentionMatch.same(thought, as: $0) }) {
                        if !filedIDs.contains(match.id) { filedIDs.append(match.id) }
                        continue
                    }
                    // Une fête n'a pas d'échéance : la page de la personne la rappelle chaque année (P33). F03 : une
                    // négation, une hypothèse, une question, une citation ou un récit ne donnent ni échéance ni rappel.
                    // F16 — les dates se lisent dans le fuseau de la capture (« demain à 9 h » dit à Toronto reste 9 h à
                    // Toronto) ; un rendez-vous prend la date de l'événement, jamais celle d'un rappel.
                    let event = noteKind == .appointment
                        ? thought.temporal.first { $0.role == .event || $0.role == .start }?.phrase : nil
                    let due = thought.birthdayOf != nil || !plan.schedules ? nil
                        : DateResolver.firstDate(in: event.map { [$0] + thought.mentionedDates } ?? thought.mentionedDates,
                                                 excerpt: thought.excerpt, relativeTo: source.capturedAt,
                                                 calendar: captureCalendar)
                    // « aujourd'hui », « demain »… deviennent la vraie date dans le titre et le texte rédigé ; les mots
                    // exacts de la dictée (contenu, extrait) restent tels quels.
                    let title = TitleMaker.fallbackTitle(
                        from: RelativeDateWording.anchored(thought.title, on: source.capturedAt, calendar: captureCalendar))
                    let summary = thought.summary.map {
                        RelativeDateWording.anchored($0, on: source.capturedAt, calendar: captureCalendar)
                    }
                    let draft = MemoryDraft(
                        sourceID: sourceID, excerpt: thought.excerpt, spanStart: thought.spanStart, spanEnd: thought.spanEnd,
                        spanTextVersion: source.correctedText == nil ? .original : .corrected,
                        title: title, summary: summary, content: thought.excerpt, kind: noteKind,
                        status: .unsorted, mentionedDates: thought.mentionedDates, analysisVersion: Self.analysisVersion,
                        dueAt: due?.date, dueHasTime: due?.hasTime ?? false)
                    let memory = try memoryStore.createMemory(db, draft: draft, actor: .ai, now: now)
                    // F16 — chaque date dite garde son rôle (événement, échéance, rappel…) et sa résolution.
                    try Self.recordTemporal(db, memoryID: memory.id, mentions: thought.temporal,
                                            capturedAt: source.capturedAt, calendar: captureCalendar)
                    try classify(memory.id, with: thought)
                    // F03 — une phrase niée (« je ne pèse plus 180 livres ») n'enregistre ni mesure, ni habitude, ni
                    // objectif, ni fête ; une négation, une hypothèse, une question, une citation ou un récit ne posent ni
                    // rappel de lieu ni récurrence.
                    let affirmed = thought.polarity != .negative
                    if affirmed {
                        // Les mesures dites (« je pèse 162,5 livres ») vont dans les suivis (P10).
                        try measurementStore.record(db, memoryID: memory.id, text: thought.excerpt,
                                                    capturedAt: source.capturedAt, now: now)
                        // « j'ai médité 10 minutes » : l'habitude du jour (P17).
                        try measurementStore.recordHabits(db, memoryID: memory.id, text: thought.excerpt,
                                                          capturedAt: source.capturedAt, now: now)
                        // « mon objectif : méditer 5 fois par semaine » (P21).
                        try measurementStore.recordHabitGoals(db, memoryID: memory.id, text: thought.excerpt,
                                                              capturedAt: source.capturedAt)
                        // « Mon objectif : 155 livres » fixe l'objectif du suivi (P11).
                        try measurementStore.recordGoals(db, memoryID: memory.id, text: thought.excerpt,
                                                         capturedAt: source.capturedAt)
                        // « l'anniversaire de Julie est le 12 mars » : la fête va sur la page de Julie (P20).
                        // Une seule pensée : si son extrait a perdu le début de la phrase, la dictée entière est relue (P31).
                        try entityStore.recordBirthday(db, memoryID: memory.id, text: thought.excerpt,
                                                       fallback: thoughts.count == 1 ? source.referenceText : nil,
                                                       saidOn: source.capturedAt, calendar: calendar, now: now)
                    }
                    if plan.schedules {
                        // « quand j'arrive chez Costco » : le rappel attend le lieu (P14).
                        try entityStore.recordPlaceTrigger(db, memoryID: memory.id, text: thought.excerpt, now: now)
                        // « tous les lundis » : la tâche revient (P16).
                        try memoryStore.recordRecurrence(db, memoryID: memory.id, text: thought.excerpt,
                                                         capturedAt: source.capturedAt, now: now)
                    }
                    // F21 — une correction remplace la note qu'elle corrige, si c'est la seule possible et qu'elle n'est
                    // pas protégée ; sinon les deux restent et la correction est à classer (revue).
                    if thought.intent == .correction {
                        trace.append(try Self.supersede(db, with: memory, now: now) ? "correction : remplace une note"
                                     : "correction : cible ambiguë ou protégée, à classer")
                    }
                    trace.append("note créée (\(noteKind.rawValue))"
                                 + (thought.categoryPath.isEmpty ? ", à classer" : ", rangée dans un dossier"))
                    filedIDs.append(memory.id)
                }
            } else {
                // Le propriétaire a déjà touché sa note : on ne la remplace pas. Si elle est encore en usage,
                // on la classe seulement ; si elle est archivée ou à la corbeille, on n'y touche pas du tout.
                for memory in kept {
                    if memory.status == .active || memory.status == .unsorted, var first = thoughts.first {
                        // F03 — le même plan décide du dossier et de l'échéance.
                        let plan = ActionPlanner.plan(first)
                        if !plan.keepsFolder {
                            first.categoryPath = []
                            first.categoryReason = nil
                        }
                        try classify(memory.id, with: first)
                        // Le texte du propriétaire n'est pas touché, mais l'échéance dictée est posée si la note n'en a pas.
                        if memory.dueAt == nil, first.birthdayOf == nil, plan.schedules,
                           var current = try Memory.fetchOne(db, key: memory.id),
                           let due = DateResolver.firstDate(in: first.mentionedDates, excerpt: first.excerpt,
                                                            relativeTo: source.capturedAt, calendar: captureCalendar) {
                            current.dueAt = due.date
                            current.dueHasTime = due.hasTime
                            current.updatedAt = now
                            try current.update(db)
                        }
                    }
                    filedIDs.append(memory.id)
                }
            }

            if kept.isEmpty {
                _ = try ListStore.retract(db, sourceID: sourceID, keeping: requestedItems, now: now)
            }
            source.processingStatus = .done
            source.updatedAt = now
            try source.update(db)
            let memories = try filedIDs.compactMap { try Memory.fetchOne(db, key: $0) }
            return FilingSummary(memories: memories, categoryPaths: paths, pathByMemory: pathByMemory,
                                 listAdditions: listAdditions, trace: trace)
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

    /// Repli : l'analyse a échoué. Le souvenir provisoire reste « À classer » et la source est close ; P35 : elle sera
    /// réessayée plus tard, `maxAnalysisAttempts` fois au plus.
    /// F12 : un essai compte une seule fois (une reprise l'a déjà compté) ; le suivant attend un délai croissant, et les
    /// notes déjà tirées d'une analyse précédente restent en place.
    public func markFallback(sourceID: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard var source = try Source.fetchOne(db, key: sourceID) else { throw StoreError.notFound }
            source.processingStatus = .done
            source.analysisAttempts = max(source.analysisAttempts, 1)
            source.needsCloudRetry = source.analysisAttempts < Self.maxAnalysisAttempts
            source.retryAfter = now.addingTimeInterval(MemoryStore.retryDelay(afterAttempt: source.analysisAttempts))
            source.updatedAt = now
            try source.update(db)
        }
    }

    /// P35 — essais de classement au plus pour une même note avant de la laisser au propriétaire.
    public static let maxAnalysisAttempts = 3
    /// P35 — la partie d'une dictée qu'aucune pensée ne reprend (gardée « À classer »).
    public static let leftoverAnalysisVersion = "p35-reste"
}
