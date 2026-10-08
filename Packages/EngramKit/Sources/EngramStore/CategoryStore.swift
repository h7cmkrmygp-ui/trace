import EngramCore
import Foundation
import GRDB

/// Catégories, tags et liens avec les souvenirs.
public struct CategoryStore: Sendable {
    public let database: AppDatabase
    public let dates: any DateProvider

    public static let defaultRootNames = [
        "Travail", "Études", "Projets", "Finances", "Santé", "Voyages", "Personnel", "Idées", "Documents",
    ]
    public static let maxNameLength = 40
    public static let maxTagLength = 30
    static let seededSettingKey = "categories.seeded.v1"

    public init(database: AppDatabase, dates: any DateProvider = SystemDateProvider()) {
        self.database = database
        self.dates = dates
    }

    public enum Creation: Sendable, Equatable {
        case created(EngramCategory)
        case existing(EngramCategory)

        public var category: EngramCategory {
            switch self {
            case .created(let category), .existing(let category): category
            }
        }
    }

    public struct CategorySummary: Sendable, Hashable, Identifiable {
        public let category: EngramCategory
        public let depth: Int
        /// Souvenirs actifs ou « À classer » liés directement à cette catégorie.
        public let memoryCount: Int
        /// Les mêmes, sous-catégories comprises.
        public let totalCount: Int
        public var id: UUID { category.id }
    }

    public struct LibrarySummary: Sendable, Equatable {
        /// Catégories actives **qui contiennent au moins une note** (elles ou leurs sous-catégories),
        /// en arbre aplati (parent puis enfants, par ordre alphabétique).
        public let categories: [CategorySummary]
        public let unsortedCount: Int
        public let archivedCount: Int
        public let trashedCount: Int
    }

    // MARK: - Catégories

    /// Crée les catégories de départ une seule fois dans la vie de la base (même si on les supprime ensuite).
    public func seedDefaultsIfNeeded() throws {
        let now = dates.now()
        try database.writer.write { db in
            let seeded = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM setting WHERE key = ?)",
                                           arguments: [Self.seededSettingKey]) ?? false
            guard !seeded else { return }
            for name in Self.defaultRootNames {
                _ = try createCategory(db, name: name, parentID: nil, origin: .seed, description: nil, now: now)
            }
            try db.execute(sql: "INSERT INTO setting(key, value, updated_at) VALUES (?, '1', ?)",
                           arguments: [Self.seededSettingKey, now])
        }
    }

    /// Crée une catégorie, ou renvoie celle qui porte déjà ce nom (accents, casse, pluriel et espaces ignorés) au même endroit.
    public func createCategory(name: String, parentID: UUID?, origin: Origin, description: String? = nil) throws -> Creation {
        let now = dates.now()
        return try database.writer.write { db in
            try createCategory(db, name: name, parentID: parentID, origin: origin, description: description, now: now)
        }
    }

    func createCategory(_ db: Database, name: String, parentID: UUID?, origin: Origin,
                        description: String?, now: Date) throws -> Creation {
        let cleaned = try Self.cleanName(name, maxLength: Self.maxNameLength)
        let normalized = TextNormalizer.normalizedName(cleaned)
        if let existing = try activeSibling(db, normalizedName: normalized, parentID: parentID) {
            return .existing(existing)
        }
        if let parentID {
            guard let parent = try EngramCategory.fetchOne(db, key: parentID), parent.status == .active else {
                throw StoreError.notFound
            }
        }
        let category = EngramCategory(name: cleaned, descriptionText: description, parentID: parentID, origin: origin, now: now)
        try category.insert(db)
        return .created(category)
    }

    public func rename(_ id: UUID, to newName: String) throws -> EngramCategory {
        let now = dates.now()
        return try database.writer.write { db in
            guard var category = try EngramCategory.fetchOne(db, key: id), category.status == .active else {
                throw StoreError.notFound
            }
            let cleaned = try Self.cleanName(newName, maxLength: Self.maxNameLength)
            let normalized = TextNormalizer.normalizedName(cleaned)
            if try activeSibling(db, normalizedName: normalized, parentID: category.parentID, excluding: id) != nil {
                throw StoreError.nameConflict
            }
            category.name = cleaned
            category.normalizedName = normalized
            category.updatedAt = now
            try category.update(db)
            return category
        }
    }

    /// « Supprimer » une catégorie : elle est archivée, ses sous-catégories remontent d'un niveau,
    /// ses liens sont retirés, et les souvenirs qui n'ont plus de catégorie repassent « À classer ».
    public func archiveCategory(_ id: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard var category = try EngramCategory.fetchOne(db, key: id), category.status == .active else {
                throw StoreError.notFound
            }
            try reparentChildren(db, of: id, to: category.parentID, now: now)
            let affected = try UUID.fetchAll(db, sql: "SELECT memory_id FROM memory_category WHERE category_id = ?",
                                             arguments: [id])
            try CategoryAssignment.filter(Column("category_id") == id).deleteAll(db)
            category.status = .archived
            category.updatedAt = now
            try category.update(db)
            for memoryID in affected { try SortingStatus.refresh(db, memoryID: memoryID, now: now) }
        }
    }

    /// Fusionne `sourceID` dans `targetID` : liens et sous-catégories déplacés, `sourceID` archivée.
    public func merge(_ sourceID: UUID, into targetID: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in try merge(db, from: sourceID, into: targetID, now: now) }
    }

    func merge(_ db: Database, from sourceID: UUID, into targetID: UUID, now: Date) throws {
        guard sourceID != targetID else {
            throw StoreError.invalidOperation("une catégorie ne peut pas fusionner avec elle-même")
        }
        guard var source = try EngramCategory.fetchOne(db, key: sourceID), source.status == .active,
              let target = try EngramCategory.fetchOne(db, key: targetID), target.status == .active
        else { throw StoreError.notFound }
        if try descendantIDs(db, of: sourceID).contains(targetID) {
            throw StoreError.invalidOperation("impossible de fusionner une catégorie dans une de ses sous-catégories")
        }
        for assignment in try CategoryAssignment.filter(Column("category_id") == sourceID).fetchAll(db) {
            var moved = assignment
            moved.categoryID = targetID
            moved.updatedAt = now
            _ = try assignment.delete(db)
            if let existing = try CategoryAssignment.fetchOne(db, key: ["memory_id": assignment.memoryID, "category_id": targetID]) {
                if Self.priority(moved) > Self.priority(existing) {
                    moved.createdAt = existing.createdAt
                    try moved.update(db)
                }
            } else {
                try moved.insert(db)
            }
        }
        try reparentChildren(db, of: sourceID, to: target.id, now: now)
        source.status = .archived
        source.updatedAt = now
        try source.update(db)
    }

    public func activeCategories() throws -> [EngramCategory] {
        try database.writer.read { db in
            try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// Catégories actives d'un souvenir (liens non rejetés).
    public func categories(for memoryID: UUID) throws -> [EngramCategory] {
        try database.writer.read { db in
            try EngramCategory.fetchAll(db, sql: """
                SELECT c.* FROM category c JOIN memory_category mc ON mc.category_id = c.id
                WHERE mc.memory_id = ? AND mc.rejected = 0 AND c.status = 'active'
                ORDER BY c.name
                """, arguments: [memoryID])
        }
    }

    /// L'identifiant lui-même suivi de tous ceux de ses sous-catégories actives.
    public func descendantIDs(of id: UUID) throws -> [UUID] {
        try database.writer.read { db in try descendantIDs(db, of: id) }
    }

    func descendantIDs(_ db: Database, of id: UUID) throws -> [UUID] {
        try UUID.fetchAll(db, sql: """
            WITH RECURSIVE tree(id) AS (
              SELECT ? UNION ALL
              SELECT c.id FROM category c JOIN tree ON c.parent_id = tree.id WHERE c.status = 'active'
            ) SELECT id FROM tree
            """, arguments: [id])
    }

    // MARK: - Liens souvenir ↔ catégorie

    public func assign(memoryID: UUID, categoryID: UUID, origin: AssignmentOrigin, confidence: Double? = nil) throws -> AssignmentOutcome {
        let now = dates.now()
        return try database.writer.write { db in
            try assign(db, memoryID: memoryID, categoryID: categoryID, origin: origin, confidence: confidence, now: now)
        }
    }

    func assign(_ db: Database, memoryID: UUID, categoryID: UUID, origin: AssignmentOrigin,
                confidence: Double?, now: Date) throws -> AssignmentOutcome {
        guard try Memory.exists(db, key: memoryID) else { throw StoreError.notFound }
        guard let category = try EngramCategory.fetchOne(db, key: categoryID), category.status == .active else {
            throw StoreError.notFound
        }
        let existing = try CategoryAssignment.fetchOne(db, key: ["memory_id": memoryID, "category_id": category.id])
        let outcome = try AssignmentRules.assign(
            db, existing: existing,
            makeNew: { CategoryAssignment(memoryID: memoryID, categoryID: category.id, origin: origin,
                                          confidence: confidence, confirmed: origin == .user, now: now) },
            origin: origin, now: now)
        try SortingStatus.refresh(db, memoryID: memoryID, now: now)
        return outcome
    }

    // MARK: - Chemins de catégories (créés par l'IA)

    /// Trouve ou crée chaque niveau du chemin (« Automobile », « Corolla ») et renvoie le plus précis.
    /// Chaque niveau est comparé aux catégories actives de même parent, accents, casse et pluriel ignorés.
    public func resolvePath(_ names: [String], origin: Origin) throws -> EngramCategory {
        let now = dates.now()
        return try database.writer.write { db in
            guard let last = try resolveChain(db, names: names, origin: origin, now: now).last else {
                throw StoreError.invalidName
            }
            return last
        }
    }

    /// Pose la description proposée par l'IA sur une catégorie qui n'en a pas encore (jamais d'écrasement).
    func describeIfMissing(_ db: Database, categoryID: UUID, description: String, now: Date) throws {
        guard var category = try EngramCategory.fetchOne(db, key: categoryID),
              (category.descriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let cleaned = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        category.descriptionText = cleaned
        category.updatedAt = now
        try category.update(db)
    }

    /// Catégories du chemin, de la plus large à la plus précise.
    func resolveChain(_ db: Database, names: [String], origin: Origin, now: Date) throws -> [EngramCategory] {
        guard !names.isEmpty else { throw StoreError.invalidName }
        var chain: [EngramCategory] = []
        for name in names {
            let category = try createCategory(db, name: name, parentID: chain.last?.id, origin: origin,
                                              description: nil, now: now).category
            chain.append(category)
        }
        return chain
    }

    /// Tous les chemins actifs, triés : « Automobile », « Automobile › Corolla », « Finance »…
    public func categoryPaths() throws -> [String] {
        try database.writer.read { db in try Self.categoryPaths(db) }
    }

    static func categoryPaths(_ db: Database) throws -> [String] {
        let active = try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
        let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        return active
            .map { CategoryPaths.display(CategoryPaths.components(of: $0, in: byID)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Archive une fois pour toutes les catégories de départ (P1) qui n'ont aucun souvenir ni sous-catégorie.
    /// Renvoie le nombre de catégories archivées.
    public func archiveUnusedSeeds() throws -> Int {
        let now = dates.now()
        return try database.writer.write { db in
            let unused = try EngramCategory.fetchAll(db, sql: """
                SELECT c.* FROM category c
                WHERE c.origin = 'seed' AND c.status = 'active'
                  AND NOT EXISTS (SELECT 1 FROM memory_category mc WHERE mc.category_id = c.id AND mc.rejected = 0)
                  AND NOT EXISTS (SELECT 1 FROM category child WHERE child.parent_id = c.id AND child.status = 'active')
                """)
            for var category in unused {
                try CategoryAssignment.filter(Column("category_id") == category.id).deleteAll(db)
                category.status = .archived
                category.updatedAt = now
                try category.update(db)
            }
            return unused.count
        }
    }

    public func confirm(memoryID: UUID, categoryID: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard let row = try CategoryAssignment.fetchOne(db, key: ["memory_id": memoryID, "category_id": categoryID]) else {
                throw StoreError.notFound
            }
            try AssignmentRules.confirm(db, row: row, now: now)
            try SortingStatus.refresh(db, memoryID: memoryID, now: now)
        }
    }

    public func removeAssignment(memoryID: UUID, categoryID: UUID, by origin: AssignmentOrigin) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard let row = try CategoryAssignment.fetchOne(db, key: ["memory_id": memoryID, "category_id": categoryID]) else {
                throw StoreError.notFound
            }
            try AssignmentRules.remove(db, row: row, by: origin, now: now)
            try SortingStatus.refresh(db, memoryID: memoryID, now: now)
        }
    }

    // MARK: - Tags

    public func upsertTag(name: String, origin: Origin) throws -> EngramTag {
        let now = dates.now()
        return try database.writer.write { db in try upsertTag(db, name: name, origin: origin, now: now) }
    }

    func upsertTag(_ db: Database, name: String, origin: Origin, now: Date) throws -> EngramTag {
        let cleaned = try Self.cleanName(name, maxLength: Self.maxTagLength)
        let normalized = TextNormalizer.normalizedName(cleaned)
        if let existing = try EngramTag.filter(Column("normalized_name") == normalized).fetchOne(db) {
            return existing
        }
        let tag = EngramTag(name: cleaned, origin: origin, now: now)
        try tag.insert(db)
        return tag
    }

    public func tag(memoryID: UUID, tagID: UUID, origin: AssignmentOrigin, confidence: Double? = nil) throws -> AssignmentOutcome {
        let now = dates.now()
        return try database.writer.write { db in
            try tag(db, memoryID: memoryID, tagID: tagID, origin: origin, confidence: confidence, now: now)
        }
    }

    func tag(_ db: Database, memoryID: UUID, tagID: UUID, origin: AssignmentOrigin,
             confidence: Double?, now: Date) throws -> AssignmentOutcome {
        guard try Memory.exists(db, key: memoryID), try EngramTag.exists(db, key: tagID) else {
            throw StoreError.notFound
        }
        let existing = try TagAssignment.fetchOne(db, key: ["memory_id": memoryID, "tag_id": tagID])
        return try AssignmentRules.assign(
            db, existing: existing,
            makeNew: { TagAssignment(memoryID: memoryID, tagID: tagID, origin: origin,
                                     confidence: confidence, confirmed: origin == .user, now: now) },
            origin: origin, now: now)
    }

    public func untag(memoryID: UUID, tagID: UUID, by origin: AssignmentOrigin) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard let row = try TagAssignment.fetchOne(db, key: ["memory_id": memoryID, "tag_id": tagID]) else {
                throw StoreError.notFound
            }
            try AssignmentRules.remove(db, row: row, by: origin, now: now)
        }
    }

    public func tags(for memoryID: UUID) throws -> [EngramTag] {
        try database.writer.read { db in
            try EngramTag.fetchAll(db, sql: """
                SELECT t.* FROM tag t JOIN memory_tag mt ON mt.tag_id = t.id
                WHERE mt.memory_id = ? AND mt.rejected = 0
                ORDER BY t.name
                """, arguments: [memoryID])
        }
    }

    // MARK: - Bibliothèque

    public func librarySummaryStream() -> AsyncThrowingStream<LibrarySummary, any Error> {
        database.stream { db in try Self.librarySummary(db) }
    }

    public func memoriesStream(inCategory id: UUID) -> AsyncThrowingStream<[Memory], any Error> {
        database.stream { db in
            try Memory.fetchAll(db, sql: """
                SELECT m.* FROM memory m JOIN memory_category mc ON mc.memory_id = m.id
                WHERE mc.category_id = ? AND mc.rejected = 0 AND m.status IN ('active','unsorted')
                ORDER BY m.captured_at DESC
                """, arguments: [id])
        }
    }

    /// Une catégorie et ses notes vivantes.
    public struct CategorySection: Sendable, Equatable, Identifiable {
        public let category: EngramCategory
        public let memories: [Memory]
        public var id: UUID { category.id }
    }

    /// Écran d'une catégorie : ses propres notes, puis celles de chaque sous-catégorie (ordre alphabétique).
    /// Les sections sans note sont omises.
    public func sectionsStream(rootID: UUID) -> AsyncThrowingStream<[CategorySection], any Error> {
        database.stream { db in try Self.sections(db, rootID: rootID) }
    }

    static func sections(_ db: Database, rootID: UUID) throws -> [CategorySection] {
        guard let root = try EngramCategory.fetchOne(db, key: rootID) else { return [] }
        let children = try EngramCategory
            .filter(Column("parent_id") == rootID && Column("status") == CategoryStatus.active)
            .fetchAll(db)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return try ([root] + children).compactMap { category in
            let memories = try Memory.fetchAll(db, sql: """
                SELECT m.* FROM memory m JOIN memory_category mc ON mc.memory_id = m.id
                WHERE mc.category_id = ? AND mc.rejected = 0 AND m.status IN ('active','unsorted')
                ORDER BY m.captured_at DESC
                """, arguments: [category.id])
            return memories.isEmpty ? nil : CategorySection(category: category, memories: memories)
        }
    }

    static func librarySummary(_ db: Database) throws -> LibrarySummary {
        let categories = try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
        var counts: [UUID: Int] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT mc.category_id AS category_id, count(*) AS n
            FROM memory_category mc JOIN memory m ON m.id = mc.memory_id
            WHERE mc.rejected = 0 AND m.status IN ('active','unsorted')
            GROUP BY mc.category_id
            """) {
            let id: UUID = row["category_id"]
            let n: Int = row["n"]
            counts[id] = n
        }
        let children = Dictionary(grouping: categories, by: \.parentID)
        var totals: [UUID: Int] = [:]
        func total(_ id: UUID) -> Int {
            if let known = totals[id] { return known }
            let sum = (counts[id] ?? 0) + (children[id] ?? []).reduce(0) { $0 + total($1.id) }
            totals[id] = sum
            return sum
        }
        var flat: [CategorySummary] = []
        func visit(_ parentID: UUID?, depth: Int) {
            let siblings = (children[parentID] ?? [])
                .filter { total($0.id) > 0 }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            for category in siblings {
                flat.append(CategorySummary(category: category, depth: depth, memoryCount: counts[category.id] ?? 0,
                                            totalCount: total(category.id)))
                visit(category.id, depth: depth + 1)
            }
        }
        visit(nil, depth: 0)
        // Les dictées qui attendent « Vérifie ta note » sont comptées dans « À vérifier », pas ici.
        func count(_ status: MemoryStatus) throws -> Int {
            try Memory.filter(Column("status") == status)
                .filter(sql: "source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)")
                .fetchCount(db)
        }
        return LibrarySummary(categories: flat, unsortedCount: try count(.unsorted),
                              archivedCount: try count(.archived), trashedCount: try count(.trashed))
    }

    // MARK: - Outils

    static func cleanName(_ raw: String, maxLength: Int) throws -> String {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !TextNormalizer.normalizedName(collapsed).isEmpty, collapsed.count <= maxLength else {
            throw StoreError.invalidName
        }
        return collapsed
    }

    func activeSibling(_ db: Database, normalizedName: String, parentID: UUID?, excluding: UUID? = nil) throws -> EngramCategory? {
        var request = EngramCategory.filter(Column("normalized_name") == normalizedName && Column("status") == CategoryStatus.active)
        if let parentID {
            request = request.filter(Column("parent_id") == parentID)
        } else {
            request = request.filter(Column("parent_id") == nil)
        }
        if let excluding { request = request.filter(Column("id") != excluding) }
        return try request.fetchOne(db)
    }

    /// Déplace les sous-catégories actives sous `newParentID` ; en cas de nom identique à l'arrivée, elles fusionnent.
    func reparentChildren(_ db: Database, of parentID: UUID, to newParentID: UUID?, now: Date) throws {
        let children = try EngramCategory
            .filter(Column("parent_id") == parentID && Column("status") == CategoryStatus.active)
            .fetchAll(db)
        for var child in children {
            if let clash = try activeSibling(db, normalizedName: child.normalizedName, parentID: newParentID, excluding: child.id) {
                try merge(db, from: child.id, into: clash.id, now: now)
            } else {
                child.parentID = newParentID
                child.updatedAt = now
                try child.update(db)
            }
        }
    }

    /// Ordre de force d'une décision : confirmé > rejeté > posé par le propriétaire > proposé par l'IA.
    static func priority(_ assignment: CategoryAssignment) -> Int {
        if assignment.confirmed { return 3 }
        if assignment.rejected { return 2 }
        return assignment.origin == .user ? 1 : 0
    }
}
