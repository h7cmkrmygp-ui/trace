import EngramCore
import Foundation
import GRDB

/// P19 — cocher ou retirer des cases à la voix.
extension ListStore {
    /// Coche ou retire les choses dites, dans la liste nommée ou dans celle qui les contient (l'épicerie d'abord).
    /// nil : aucune liste ne convient ; `changed` vide : une liste existe mais rien n'a changé ; `replayed` : cette dictée
    /// l'avait déjà fait (F08, rejeu sans effet).
    /// - Parameter sourceID: la dictée qui le demande : la liste prend ses interdictions (F01), et chaque opération faite
    ///   est notée pour ne jamais être refaite (F08).
    func apply(_ db: Database, _ action: ListAction, sourceID: UUID? = nil,
               now: Date) throws -> (memory: Memory, changed: [String], replayed: Bool)? {
        let wanted = action.listName.map(ListCommandParser.key)
        let grocery = ListCommandParser.key("épicerie")
        var candidates: [Memory] = []
        for record in try ListRecord.fetchAll(db) where wanted == nil || record.normalizedName == wanted {
            guard let memory = try Memory.fetchOne(db, key: record.memoryID), memory.status != .trashed else { continue }
            candidates.append(memory)
        }
        let keys = try Dictionary(uniqueKeysWithValues: ListRecord.fetchAll(db).map { ($0.memoryID, $0.normalizedName) })
        candidates.sort { first, second in
            let a = keys[first.id] == grocery
            let b = keys[second.id] == grocery
            return a != b ? a : first.updatedAt > second.updatedAt
        }
        let kind: OperationKind = action.kind == .check ? .check : .remove
        var items = action.items
        if let sourceID {
            items = try Self.notYetApplied(db, kind, items: action.items, listKey: nil, sourceID: sourceID)
            // Déjà fait par cette même dictée : rien n'est refait (une case recochée, une chose retirée à nouveau).
            if items.isEmpty { return candidates.first.map { ($0, [], true) } }
        }
        for var memory in candidates {
            let body = memory.summary ?? ""
            let result = action.kind == .check ? ListMerge.checking(items, in: body) : ListMerge.removing(items, from: body)
            guard !result.changed.isEmpty else { continue }
            memory.summary = result.body
            memory.version += 1
            memory.updatedAt = now
            try memory.update(db)
            let verb = action.kind == .check ? "coché" : "retiré"
            // F09 — une demande comprise par l'IA, pas une modification à la main.
            try MemoryVersion(memory: memory, changedBy: .ai,
                              reason: "\(verb) à la voix : \(result.changed.joined(separator: ", "))", at: now).insert(db)
            try Self.syncItems(db, listMemoryID: memory.id, body: result.body, actor: .ai, sourceID: sourceID, now: now)
            if let sourceID {
                if let key = keys[memory.id] { try Self.restrict(db, key: key, by: sourceID) }
                let done = items.filter { item in result.changed.contains { ListMerge.matches(item, $0) } }
                try Self.recordApplied(db, kind, items: done, listKey: nil, sourceID: sourceID, now: now)
            }
            return (memory, result.changed, false)
        }
        return candidates.first.map { ($0, [], false) }
    }
}
