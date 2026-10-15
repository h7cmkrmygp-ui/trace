import EngramCore
import Foundation
import GRDB

/// P19 — cocher ou retirer des cases à la voix.
extension ListStore {
    /// Coche ou retire les choses dites, dans la liste nommée ou dans celle qui les contient (l'épicerie d'abord).
    /// nil : aucune liste ne convient ; `changed` vide : une liste existe mais rien n'a changé.
    func apply(_ db: Database, _ action: ListAction, now: Date) throws -> (memory: Memory, changed: [String])? {
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
        for var memory in candidates {
            let body = memory.summary ?? ""
            let result = action.kind == .check ? ListMerge.checking(action.items, in: body)
                                               : ListMerge.removing(action.items, from: body)
            guard !result.changed.isEmpty else { continue }
            memory.summary = result.body
            memory.version += 1
            memory.updatedAt = now
            try memory.update(db)
            let verb = action.kind == .check ? "coché" : "retiré"
            try MemoryVersion(memory: memory, changedBy: .user,
                              reason: "\(verb) à la voix : \(result.changed.joined(separator: ", "))", at: now).insert(db)
            return (memory, result.changed)
        }
        return candidates.first.map { ($0, []) }
    }
}
