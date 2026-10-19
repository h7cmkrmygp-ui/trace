import EngramCore
import Foundation
import GRDB

/// P33 — les fêtes ont leur dossier : « Anniversaires », ou celui que le propriétaire a déjà (« Fêtes »…).
extension CategoryStore {
    /// Noms d'un dossier de fêtes (sans accents, au singulier, comme `normalized_name`).
    static let birthdayFolderKeys: Set<String> = ["anniversaire", "fete", "birthday", "fete et anniversaire",
                                                  "anniversaire et fete"]

    /// Le chemin du dossier des fêtes que le propriétaire a déjà (« Fêtes », « Famille › Anniversaires »…), sinon nil.
    /// À la racine d'abord, puis le chemin le plus court.
    func birthdayFolderPath(_ db: Database) throws -> [String]? {
        let active = try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
        let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        return active
            .filter { Self.birthdayFolderKeys.contains($0.normalizedName) }
            .map { CategoryPaths.components(of: $0, in: byID) }
            .min { ($0.count, CategoryPaths.display($0)) < ($1.count, CategoryPaths.display($1)) }
    }

    /// Une seule fois : les anciennes notes qui disent seulement une fête vont dans le dossier des fêtes, comme des choses
    /// à retenir (sans échéance ni « À faire »). Une note que le propriétaire a modifiée ou rangée lui-même n'est jamais
    /// touchée. Renvoie le nombre de notes rangées.
    public func refileBirthdayNotes() throws -> Int {
        let now = dates.now()
        return try database.writer.write { db -> Int in
            let candidates = try Memory.fetchAll(db, sql: """
                SELECT m.* FROM memory m
                WHERE m.status IN ('active','unsorted') AND m.user_edited = 0
                  AND m.source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)
                  AND NOT EXISTS (SELECT 1 FROM memory_category mc
                                  WHERE mc.memory_id = m.id AND (mc.origin = 'user' OR mc.confirmed = 1))
                """)
            var refiled = 0
            for var memory in candidates {
                // Le texte de la note ; puis la dictée entière si elle n'a donné qu'une note (extrait incomplet).
                var texts = [memory.content]
                if try Memory.filter(Column("source_id") == memory.sourceID).fetchCount(db) == 1,
                   let whole = try Source.fetchOne(db, key: memory.sourceID)?.referenceText {
                    texts.append(whole)
                }
                guard let text = texts.first(where: { BirthdayParser.isOnlyABirthday($0) }),
                      let birthday = BirthdayParser.parse(text) else { continue }
                let ownFolder = try birthdayFolderPath(db)
                let chain = try resolveChain(db, names: ownFolder ?? [AnalysisValidator.birthdayFolder], origin: .ai, now: now)
                guard let target = chain.last else { continue }
                let links = try CategoryAssignment
                    .filter(Column("memory_id") == memory.id && Column("rejected") == false)
                    .fetchAll(db)
                let alreadyFiled = links.count == 1 && links[0].categoryID == target.id
                guard !alreadyFiled || memory.kind != .info || memory.dueAt != nil else { continue }
                // D'abord la note (une chose à retenir, sans échéance), puis ses dossiers (le statut suit).
                memory.kind = .info
                memory.dueAt = nil
                memory.dueHasTime = false
                memory.updatedAt = now
                try memory.update(db)
                if ownFolder == nil, let root = chain.first {
                    try describeIfMissing(db, categoryID: root.id, description: AnalysisValidator.birthdayFolderDescription,
                                          now: now)
                }
                for link in links where link.categoryID != target.id {
                    try AssignmentRules.remove(db, row: link, by: .ai, now: now)
                }
                if !alreadyFiled {
                    _ = try assign(db, memoryID: memory.id, categoryID: target.id, origin: .ai, confidence: nil,
                                   reason: AnalysisValidator.birthdayReason(birthday), now: now)
                }
                try SortingStatus.refresh(db, memoryID: memory.id, now: now)
                refiled += 1
            }
            return refiled
        }
    }
}
