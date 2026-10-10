import EngramCore
import Foundation
import GRDB

// MARK: - Réglages

/// Réglages simples de l'app, dans la table `setting`.
public struct SettingStore: Sendable {
    public enum Key: String, Sendable {
        /// « 1 » : ajouter automatiquement les rendez-vous datés au calendrier de l'iPhone.
        case calendarAutoAdd = "calendar.autoAdd"
        /// Identifiant du calendrier cible (absent = calendrier par défaut d'iOS).
        case calendarTarget = "calendar.targetIdentifier"
        /// Moteur de transcription : « whisper » (défaut) ou « apple ».
        case transcriptionEngine = "transcription.engine"
        /// Modèle Whisper choisi (identifiant WhisperKit) ; Turbo par défaut.
        case whisperModel = "transcription.whisperModel"
        /// « 1 » : afficher « Vérifie ta note » avant de classer une dictée (désactivé par défaut depuis P5 :
        /// « je parle, je termine, c'est enregistré »).
        case reviewBeforeFiling = "transcription.reviewBeforeFiling"
        /// « 1 » (défaut) : l'enregistrement s'arrête tout seul quand on se tait.
        case autoStopOnSilence = "recording.autoStopOnSilence"
        /// « 1 » (défaut) : notifications locales pour les tâches et rendez-vous datés.
        case remindersEnabled = "reminders.enabled"
        /// « 1 » (défaut) : résumé du matin (8 h) des choses du jour et en retard.
        case digestMorning = "reminders.digestMorning"
        /// « 1 » (défaut) : résumé de la semaine, le dimanche à 18 h.
        case digestWeekly = "reminders.digestWeekly"
        /// « 1 » : sauvegarde chiffrée automatique, une fois par semaine.
        case backupWeekly = "backup.weekly"
        /// « 1 » : Engram se verrouille avec Face ID (ou le code de l'iPhone).
        case appLock = "privacy.appLock"
        /// Stratégie de langue de Whisper : « bilingual » (défaut), « french » ou « automatic ».
        case whisperStrategy = "transcription.whisperStrategy"
        /// « 1 » : les notes de santé restent sur l'iPhone (jamais envoyées à Groq).
        case healthStaysLocal = "privacy.healthStaysLocal"
        /// « 1 » : aucune note n'est envoyée à un service en ligne (tout est classé par l'IA d'Apple).
        case keepEverythingLocal = "privacy.keepEverythingLocal"
        /// Moment (ISO 8601) de la dernière relecture des mesures (P10). Rangé dans la base : une sauvegarde restaurée
        /// sans lui fait tout relire.
        case measurementsScannedAt = "trackers.scannedAt"
        /// Moment (ISO 8601) de la première relecture complète des habitudes (P17) : absent, toutes les notes sont relues.
        case habitsScannedAt = "habits.scannedAt"
        /// « 1 » (défaut) : « Te souviens-tu ? », une vieille idée chaque soir à 19 h (P13).
        case resurfacing = "reminders.resurfacing"
        /// « 1 » (défaut) : l'adresse d'un lieu dicté est cherchée toute seule autour du propriétaire (P30).
        case autoLocatePlaces = "places.autoLocate"
        /// « 1 » (défaut) : « Garde ta série » à 20 h quand une série d'habitude n'est pas encore faite (P21).
        case habitNudges = "reminders.habitNudges"
        /// Moment (ISO 8601) de la relecture unique des anciennes notes (P31) : fêtes manquantes, suivis mal remplis.
        case filingFixesAt = "fixes.p31.doneAt"
        /// Moment (ISO 8601) où les anciennes notes de fête ont été rangées dans le dossier des fêtes (P33).
        case birthdayFolderAt = "fixes.p33.doneAt"
        /// Modèles Gemini choisis au test de la clé (« flash,flash-lite »), sans la clé elle-même.
        case geminiModels = "cloud.gemini.models"
    }

    public let database: AppDatabase
    public let dates: any DateProvider

    public init(database: AppDatabase, dates: any DateProvider = SystemDateProvider()) {
        self.database = database
        self.dates = dates
    }

    public func string(_ key: Key) throws -> String? {
        try database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key.rawValue])
        }
    }

    /// `nil` efface le réglage.
    public func set(_ value: String?, for key: Key) throws {
        let now = dates.now()
        try database.writer.write { db in
            if let value {
                try db.execute(sql: """
                    INSERT INTO setting(key, value, updated_at) VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                    """, arguments: [key.rawValue, value, now])
            } else {
                try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [key.rawValue])
            }
        }
    }

    public func bool(_ key: Key, default defaultValue: Bool) throws -> Bool {
        guard let value = try string(key) else { return defaultValue }
        return value == "1"
    }

    public func set(_ value: Bool, for key: Key) throws {
        try set(value ? "1" : "0", for: key)
    }
}

// MARK: - Liens avec le calendrier de l'iPhone

/// Un événement du calendrier créé par Engram pour un souvenir.
public struct CalendarLink: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "calendar_link" }

    public var memoryID: UUID
    public var eventIdentifier: String
    public var calendarIdentifier: String?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case eventIdentifier = "event_identifier"
        case calendarIdentifier = "calendar_identifier"
        case createdAt = "created_at"
    }
}

public struct CalendarLinkStore: Sendable {
    public let database: AppDatabase
    public let dates: any DateProvider
    /// Fuseau des journées (un rendez-vous « aujourd'hui » sans heure commence à minuit).
    public let calendar: Calendar

    public init(database: AppDatabase, dates: any DateProvider = SystemDateProvider(), calendar: Calendar = .current) {
        self.database = database
        self.dates = dates
        self.calendar = calendar
    }

    /// Relie un souvenir à l'événement créé. Un souvenir déjà relié garde son premier événement.
    public func link(memoryID: UUID, eventIdentifier: String, calendarIdentifier: String?) throws {
        let now = dates.now()
        try database.writer.write { db in
            try CalendarLink(memoryID: memoryID, eventIdentifier: eventIdentifier,
                             calendarIdentifier: calendarIdentifier, createdAt: now)
                .insert(db, onConflict: .ignore)
        }
    }

    public func link(for memoryID: UUID) throws -> CalendarLink? {
        try database.writer.read { db in try CalendarLink.fetchOne(db, key: memoryID) }
    }

    /// Événements du calendrier de l'iPhone créés par Engram (le Calendrier d'Engram ne les affiche pas deux fois).
    public func linkedEventIdentifiers() throws -> Set<String> {
        try database.writer.read { db in
            Set(try String.fetchAll(db, sql: "SELECT event_identifier FROM calendar_link"))
        }
    }

    /// Rendez-vous datés, à venir (depuis 12 h, et toute la journée en cours), actifs ou « À classer », sans événement créé.
    /// Un rendez-vous d'aujourd'hui sans heure (échéance à minuit) est donc ajouté même dicté l'après-midi.
    public func unlinkedAppointments() throws -> [Memory] {
        let now = dates.now()
        let since = min(now.addingTimeInterval(-12 * 3600), calendar.startOfDay(for: now))
        return try database.writer.read { db in
            try Memory.fetchAll(db, sql: """
                SELECT m.* FROM memory m
                WHERE m.kind = 'appointment' AND m.due_at IS NOT NULL AND m.due_at >= ?
                  AND m.status IN ('active','unsorted')
                  AND NOT EXISTS (SELECT 1 FROM calendar_link l WHERE l.memory_id = m.id)
                ORDER BY m.due_at
                """, arguments: [since])
        }
    }
}

// MARK: - Échéances et Cerveau

extension MemoryStore {
    /// Souvenirs actifs ou « À classer » dont l'échéance tombe dans [début, fin[.
    public func memoriesStream(dueFrom start: Date, to end: Date) -> AsyncThrowingStream<[Memory], any Error> {
        database.stream { db in
            try Memory
                .filter(Column("due_at") >= start && Column("due_at") < end)
                .filter([MemoryStatus.active, MemoryStatus.unsorted].contains(Column("status")))
                .order(Column("due_at"))
                .fetchAll(db)
        }
    }
}

/// Ce qu'affiche le Cerveau : pensées vivantes avec leur catégorie la plus précise, et seulement les catégories
/// qui en contiennent (avec leurs parents).
public struct BrainSnapshot: Sendable, Equatable {
    public let categories: [BrainLayout.CategoryInput]
    public let items: [BrainLayout.ItemInput]
}

extension CategoryStore {
    public func brainSnapshotStream() -> AsyncThrowingStream<BrainSnapshot, any Error> {
        database.stream { db in try Self.brainSnapshot(db) }
    }

    static func brainSnapshot(_ db: Database) throws -> BrainSnapshot {
        let categories = try EngramCategory.filter(Column("status") == CategoryStatus.active).fetchAll(db)
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        func depth(_ id: UUID) -> Int { byID[id].map { CategoryPaths.components(of: $0, in: byID).count } ?? 0 }

        var deepest: [UUID: UUID] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT mc.memory_id AS memory_id, mc.category_id AS category_id
            FROM memory_category mc
            JOIN category c ON c.id = mc.category_id
            JOIN memory m ON m.id = mc.memory_id
            WHERE mc.rejected = 0 AND c.status = 'active' AND m.status IN ('active','unsorted')
            """) {
            let memoryID: UUID = row["memory_id"]
            let categoryID: UUID = row["category_id"]
            if let current = deepest[memoryID], depth(current) >= depth(categoryID) { continue }
            deepest[memoryID] = categoryID
        }
        // Les dictées qui attendent « Vérifie ta note » n'y figurent pas encore.
        let memories = try Memory
            .filter([MemoryStatus.active, MemoryStatus.unsorted].contains(Column("status")))
            .filter(sql: "source_id NOT IN (SELECT id FROM source WHERE needs_review = 1)")
            .fetchAll(db)
        // Catégories qui contiennent une pensée, et tous leurs parents.
        var shown: Set<UUID> = []
        for categoryID in deepest.values {
            var next: UUID? = categoryID
            while let id = next, shown.insert(id).inserted { next = byID[id]?.parentID }
        }
        return BrainSnapshot(
            categories: categories.filter { shown.contains($0.id) }
                .map { BrainLayout.CategoryInput(id: $0.id, name: $0.name, parentID: $0.parentID) },
            items: memories.map { BrainLayout.ItemInput(id: $0.id, title: $0.title, categoryID: deepest[$0.id]) })
    }
}
