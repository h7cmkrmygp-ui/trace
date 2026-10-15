import EngramCore
import Foundation
import GRDB

/// P40 — un changement du ménage, noté dans l'historique (annulable).
public struct TidyRecord: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let runAt: Date
    public let summary: String
    public let undone: Bool

    public init(id: UUID, runAt: Date, summary: String, undone: Bool) {
        self.id = id
        self.runAt = runAt
        self.summary = summary
        self.undone = undone
    }
}

/// Ce qu'il faut pour défaire un changement : les dossiers touchés et tous les liens des notes touchées, tels qu'avant.
struct TidySnapshot: Codable {
    var categories: [EngramCategory]
    var assignments: [CategoryAssignment]
    var memoryIDs: [UUID]
    /// Dossiers créés par le changement (archivés à l'annulation s'ils sont vides).
    var createdCategoryIDs: [UUID]
}

/// P40 — le ménage automatique des dossiers : appliqué, noté, annulable ; rien ne se perd (une note n'est jamais
/// supprimée, un dossier vidé est archivé).
extension CategoryStore {
    /// Les dossiers actifs, tels que le ménage les voit.
    public func tidyFolders() throws -> [TidyFolder] {
        try database.writer.read { db in
            let active = try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
            let totals = Dictionary(uniqueKeysWithValues: try Self.librarySummary(db).categories.map { ($0.category.id, $0.totalCount) })
            let parents = Set(active.compactMap(\.parentID))
            let ownerFolders = Set(try UUID.fetchAll(db, sql: """
                SELECT DISTINCT category_id FROM memory_category WHERE rejected = 0 AND (origin = 'user' OR confirmed = 1)
                """))
            return active.map { category in
                TidyFolder(id: category.id, name: category.name, parentID: category.parentID,
                           createdByOwner: category.origin == .user, noteCount: totals[category.id] ?? 0,
                           createdAt: category.createdAt, hasOwnerNotes: ownerFolders.contains(category.id),
                           hasChildren: parents.contains(category.id))
            }
        }
    }

    /// Applique les changements (en sautant ceux qui toucheraient un choix du propriétaire) et les note, un par un.
    public func applyTidy(_ actions: [TidyAction]) throws -> [TidyRecord] {
        var records: [TidyRecord] = []
        for action in actions {
            let now = dates.now()
            if let record = try database.writer.write({ db in try apply(db, action, now: now) }) { records.append(record) }
        }
        return records
    }

    /// L'historique du ménage, le plus récent d'abord.
    public func tidyHistory(limit: Int = 100) throws -> [TidyRecord] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, run_at, summary, undone_at FROM tidy_action ORDER BY run_at DESC, rowid DESC LIMIT ?
                """, arguments: [limit])
                .map { row in
                    let undoneAt: Date? = row["undone_at"]
                    return TidyRecord(id: row["id"], runAt: row["run_at"], summary: row["summary"], undone: undoneAt != nil)
                }
        }
    }

    /// Remet les dossiers et les notes comme avant ce changement.
    public func undoTidy(_ id: UUID) throws {
        let now = dates.now()
        try database.writer.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT undo_data, undone_at FROM tidy_action WHERE id = ?",
                                             arguments: [id]) else { throw StoreError.notFound }
            let undoneAt: Date? = row["undone_at"]
            guard undoneAt == nil else { return }
            let data: Data = row["undo_data"]
            let snapshot = try JSONDecoder().decode(TidySnapshot.self, from: data)
            for category in snapshot.categories { try category.update(db) }
            for memoryID in snapshot.memoryIDs {
                try CategoryAssignment.filter(Column("memory_id") == memoryID).deleteAll(db)
            }
            for assignment in snapshot.assignments { try assignment.insert(db) }
            // Deux passes : un sous-dossier créé est archivé avant son dossier parent créé lui aussi.
            for _ in 0..<2 {
                for categoryID in snapshot.createdCategoryIDs {
                    let used = try CategoryAssignment.filter(Column("category_id") == categoryID && Column("rejected") == false)
                        .fetchCount(db) > 0
                    let children = try EngramCategory
                        .filter(Column("parent_id") == categoryID && Column("status") == CategoryStatus.active)
                        .fetchCount(db) > 0
                    guard !used, !children, var created = try EngramCategory.fetchOne(db, key: categoryID),
                          created.status == .active else { continue }
                    created.status = .archived
                    created.updatedAt = now
                    try created.update(db)
                }
            }
            for memoryID in snapshot.memoryIDs { try SortingStatus.refresh(db, memoryID: memoryID, now: now) }
            try db.execute(sql: "UPDATE tidy_action SET undone_at = ? WHERE id = ?", arguments: [now, id])
        }
    }

    // MARK: - Un changement

    func apply(_ db: Database, _ action: TidyAction, now: Date) throws -> TidyRecord? {
        let activeBefore = Set(try UUID.fetchAll(db, sql: "SELECT id FROM category WHERE status = 'active'"))
        var snapshot: TidySnapshot
        let summary: String
        switch action {
        case .merge(let sourceID, let targetID):
            guard let source = try EngramCategory.fetchOne(db, key: sourceID), source.status == .active, source.origin != .user,
                  let target = try EngramCategory.fetchOne(db, key: targetID), target.status == .active else { return nil }
            let notes = try CategoryAssignment.filter(Column("category_id") == sourceID && Column("rejected") == false).fetchCount(db)
            let children = try UUID.fetchAll(db, sql: "SELECT id FROM category WHERE parent_id = ? AND status = 'active'",
                                             arguments: [sourceID])
            snapshot = try takeSnapshot(db, categoryIDs: [sourceID, targetID] + children, memoriesIn: [sourceID, targetID])
            try merge(db, from: sourceID, into: targetID, now: now)
            summary = TidyPlanner.summary(merged: source.name, into: target.name, notes: notes)
        case .rename(let folderID, let newName):
            guard var folder = try EngramCategory.fetchOne(db, key: folderID), folder.status == .active, folder.origin != .user,
                  let cleaned = try? Self.cleanName(newName, maxLength: Self.maxNameLength) else { return nil }
            let normalized = TextNormalizer.normalizedName(cleaned)
            guard try activeSibling(db, normalizedName: normalized, parentID: folder.parentID, excluding: folderID) == nil else {
                return nil
            }
            snapshot = try takeSnapshot(db, categoryIDs: [folderID], memoriesIn: [])
            let old = folder.name
            folder.name = cleaned
            folder.normalizedName = normalized
            folder.updatedAt = now
            try folder.update(db)
            summary = TidyPlanner.summary(renamed: old, to: cleaned)
        case .fold(let folderID, let parentID):
            guard var folder = try EngramCategory.fetchOne(db, key: folderID), folder.status == .active, folder.origin != .user,
                  folder.parentID == parentID, let parent = try EngramCategory.fetchOne(db, key: parentID),
                  parent.status == .active else { return nil }
            let links = try CategoryAssignment.filter(Column("category_id") == folderID && Column("rejected") == false).fetchAll(db)
            guard !links.contains(where: { $0.origin == .user || $0.confirmed }) else { return nil }
            snapshot = try takeSnapshot(db, categoryIDs: [folderID, parentID], memoriesIn: [folderID, parentID])
            let reason = "Le sous-dossier « \(folder.name) » n'avait que \(TidyPlanner.notes(links.count)) : rangée dans « \(parent.name) »."
            for link in links {
                _ = try link.delete(db)
                _ = try assign(db, memoryID: link.memoryID, categoryID: parentID, origin: .ai, confidence: nil, reason: reason,
                               now: now)
            }
            folder.status = .archived
            folder.updatedAt = now
            try folder.update(db)
            summary = TidyPlanner.summary(folded: folder.name, into: parent.name, notes: links.count)
        case .move(let memoryID, let fromPath, let toPath):
            guard let from = try category(db, atPath: fromPath),
                  let link = try CategoryAssignment.fetchOne(db, key: ["memory_id": memoryID, "category_id": from.id]),
                  link.origin == .ai, !link.confirmed, !link.rejected,
                  let memory = try Memory.fetchOne(db, key: memoryID) else { return nil }
            let names = toPath.components(separatedBy: CategoryPaths.separator)
            snapshot = try takeSnapshot(db, categoryIDs: [from.id], memoriesIn: [], memoryIDs: [memoryID])
            let chain = try resolveChain(db, names: names, origin: .ai, now: now)
            guard let target = chain.last else { return nil }
            try AssignmentRules.remove(db, row: link, by: .ai, now: now)
            _ = try assign(db, memoryID: memoryID, categoryID: target.id, origin: .ai, confidence: nil,
                           reason: "Rangée avec ses notes semblables (\(toPath)) lors du ménage des dossiers.", now: now)
            summary = TidyPlanner.summary(moved: memory.title, from: fromPath, to: toPath)
        }
        let activeAfter = Set(try UUID.fetchAll(db, sql: "SELECT id FROM category WHERE status = 'active'"))
        snapshot.createdCategoryIDs = Array(activeAfter.subtracting(activeBefore))
        let id = UUID()
        try db.execute(sql: """
            INSERT INTO tidy_action (id, run_at, kind, summary, undo_data) VALUES (?, ?, ?, ?, ?)
            """, arguments: [id, now, Self.kind(of: action), summary, try JSONEncoder().encode(snapshot)])
        return TidyRecord(id: id, runAt: now, summary: summary, undone: false)
    }

    /// Les dossiers donnés et tous les liens des notes qui sont dans `memoriesIn` (ou de `memoryIDs`), tels qu'ils sont.
    func takeSnapshot(_ db: Database, categoryIDs: [UUID], memoriesIn folders: [UUID], memoryIDs: [UUID] = []) throws -> TidySnapshot {
        let categories = try EngramCategory.filter(keys: categoryIDs).fetchAll(db)
        var memories = Set(memoryIDs)
        if !folders.isEmpty {
            memories.formUnion(try CategoryAssignment.filter(folders.contains(Column("category_id"))).fetchAll(db).map(\.memoryID))
        }
        let assignments = memories.isEmpty ? []
            : try CategoryAssignment.filter(Array(memories).contains(Column("memory_id"))).fetchAll(db)
        return TidySnapshot(categories: categories, assignments: assignments, memoryIDs: Array(memories), createdCategoryIDs: [])
    }

    /// Le dossier actif à ce chemin (« Automobile › Pièces »).
    func category(_ db: Database, atPath path: String) throws -> EngramCategory? {
        var parentID: UUID?
        var found: EngramCategory?
        for name in path.components(separatedBy: CategoryPaths.separator) {
            guard let next = try activeSibling(db, normalizedName: TextNormalizer.normalizedName(name), parentID: parentID) else {
                return nil
            }
            found = next
            parentID = next.id
        }
        return found
    }

    static func kind(of action: TidyAction) -> String {
        switch action {
        case .merge: "merge"
        case .rename: "rename"
        case .fold: "fold"
        case .move: "move"
        }
    }
}
