import GRDB

/// Schéma de la base. Une migration publiée n'est JAMAIS modifiée : on en ajoute une nouvelle.
enum Schema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: v1Tables)
            try db.execute(sql: v1FullText)
            try createChangeLogTriggers(db)
        }
        migrator.registerMigration("v2_due_dates_calendar") { db in
            try db.execute(sql: v2DueDatesAndCalendar)
        }
        migrator.registerMigration("v3_review_privacy_routing") { db in
            try db.execute(sql: v3ReviewPrivacyRouting)
        }
        migrator.registerMigration("v4_owner_corrections") { db in
            try db.execute(sql: v4OwnerCorrections)
        }
        migrator.registerMigration("v5_people_places") { db in
            try db.execute(sql: v5PeoplePlaces)
            try createChangeLogTriggers(db, for: [("entity", "id"), ("memory_entity", "memory_id")])
        }
        migrator.registerMigration("v6_measurements") { db in
            try db.execute(sql: v6Measurements)
        }
        migrator.registerMigration("v7_pins_goals") { db in
            try db.execute(sql: v7PinsGoals)
        }
        migrator.registerMigration("v8_place_reminders") { db in
            try db.execute(sql: v8PlaceReminders)
        }
        migrator.registerMigration("v9_lists") { db in
            try db.execute(sql: v9Lists)
        }
        migrator.registerMigration("v10_recurrence") { db in
            try db.execute(sql: v10Recurrence)
        }
        migrator.registerMigration("v11_habits") { db in
            try db.execute(sql: v11Habits)
        }
        migrator.registerMigration("v12_birthdays") { db in
            try db.execute(sql: v12Birthdays)
        }
        migrator.registerMigration("v13_habit_goals") { db in
            try db.execute(sql: v13HabitGoals)
        }
        migrator.registerMigration("v14_duplicates") { db in
            try db.execute(sql: v14Duplicates)
        }
        return migrator
    }

    /// v14 (P23) : les paires écartées (« ce n'est pas un doublon ») ou déjà réunies.
    static let v14Duplicates = """
        CREATE TABLE duplicate_dismissal (
          first_id BLOB NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          second_id BLOB NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          dismissed_at DATETIME NOT NULL,
          PRIMARY KEY (first_id, second_id)
        );
        """

    /// v13 (P21) : l'objectif de chaque habitude, en fois par semaine.
    static let v13HabitGoals = """
        CREATE TABLE habit_goal (
          habit TEXT PRIMARY KEY NOT NULL CHECK (length(habit) > 0),
          per_week INTEGER NOT NULL CHECK (per_week BETWEEN 1 AND 7),
          set_at DATETIME NOT NULL,
          memory_id BLOB REFERENCES memory(id) ON DELETE SET NULL
        );
        """

    /// v12 (P20) : la fête des personnes (une par personne), dite dans une note ou posée à la main.
    static let v12Birthdays = """
        CREATE TABLE person_birthday (
          entity_id BLOB PRIMARY KEY NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
          month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
          day INTEGER NOT NULL CHECK (day BETWEEN 1 AND 31),
          year INTEGER CHECK (year IS NULL OR year BETWEEN 1800 AND 2300),
          memory_id BLOB REFERENCES memory(id) ON DELETE SET NULL,
          updated_at DATETIME NOT NULL
        );
        """

    /// v11 (P17) : les habitudes faites, relevées dans les notes (recalculables depuis le texte).
    static let v11Habits = """
        CREATE TABLE habit_entry (
          id BLOB PRIMARY KEY NOT NULL,
          memory_id BLOB NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          habit TEXT NOT NULL CHECK (length(habit) > 0),
          quantity REAL,
          unit TEXT,
          done_at DATETIME NOT NULL,
          created_at DATETIME NOT NULL
        );
        CREATE INDEX habit_entry_memory ON habit_entry(memory_id);
        CREATE INDEX habit_entry_habit ON habit_entry(habit, done_at);
        """

    /// v10 (P16) : le rythme des tâches qui reviennent (une règle par note, en JSON).
    static let v10Recurrence = """
        CREATE TABLE memory_recurrence (
          memory_id BLOB PRIMARY KEY NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          rule TEXT NOT NULL CHECK (length(rule) > 0),
          anchor_at DATETIME NOT NULL,
          done_count INTEGER NOT NULL DEFAULT 0 CHECK (done_count >= 0),
          last_done_at DATETIME,
          created_at DATETIME NOT NULL
        );
        """

    /// v9 (P15) : une note par liste (épicerie, cadeaux…), et les dictées déjà ajoutées à chacune.
    static let v9Lists = """
        CREATE TABLE memory_list (
          normalized_name TEXT PRIMARY KEY NOT NULL CHECK (length(normalized_name) > 0),
          name TEXT NOT NULL CHECK (length(trim(name)) > 0),
          memory_id BLOB NOT NULL UNIQUE REFERENCES memory(id) ON DELETE CASCADE,
          created_at DATETIME NOT NULL
        );
        CREATE TABLE memory_list_addition (
          source_id BLOB NOT NULL REFERENCES source(id) ON DELETE CASCADE,
          normalized_name TEXT NOT NULL,
          added_at DATETIME NOT NULL,
          PRIMARY KEY (source_id, normalized_name)
        );
        """

    /// v8 (P14) : l'adresse des lieux et les notes qui attendent un lieu (une par note).
    static let v8PlaceReminders = """
        CREATE TABLE place_location (
          entity_id BLOB PRIMARY KEY NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
          latitude REAL NOT NULL CHECK (latitude BETWEEN -90 AND 90),
          longitude REAL NOT NULL CHECK (longitude BETWEEN -180 AND 180),
          radius REAL NOT NULL CHECK (radius > 0),
          label TEXT,
          updated_at DATETIME NOT NULL
        );
        CREATE TABLE place_trigger (
          memory_id BLOB PRIMARY KEY NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          entity_id BLOB NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
          event TEXT NOT NULL CHECK (event IN ('arrive','leave')),
          origin TEXT NOT NULL CHECK (origin IN ('ai','user')),
          created_at DATETIME NOT NULL
        );
        CREATE INDEX place_trigger_entity ON place_trigger(entity_id);
        """

    /// v7 (P11) : notes épinglées et objectifs des suivis.
    static let v7PinsGoals = """
        CREATE TABLE memory_pin (
          memory_id BLOB PRIMARY KEY NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          pinned_at DATETIME NOT NULL
        );
        CREATE TABLE tracker_goal (
          metric TEXT PRIMARY KEY NOT NULL
            CHECK (metric IN ('weight','sleep','blood_pressure','heart_rate','steps','glucose')),
          target REAL NOT NULL,
          unit TEXT NOT NULL CHECK (length(unit) > 0),
          set_at DATETIME NOT NULL,
          memory_id BLOB REFERENCES memory(id) ON DELETE SET NULL
        );
        """

    /// v6 (P10) : les mesures des notes (poids, sommeil, tension, pouls, pas, glycémie). Recalculables depuis le texte.
    static let v6Measurements = """
        CREATE TABLE measurement (
          id BLOB PRIMARY KEY NOT NULL,
          memory_id BLOB NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          metric TEXT NOT NULL CHECK (metric IN ('weight','sleep','blood_pressure','heart_rate','steps','glucose')),
          value REAL NOT NULL,
          second_value REAL,
          unit TEXT NOT NULL CHECK (length(unit) > 0),
          measured_at DATETIME NOT NULL,
          created_at DATETIME NOT NULL
        );
        CREATE INDEX measurement_memory ON measurement(memory_id);
        CREATE INDEX measurement_metric ON measurement(metric, measured_at);
        """

    /// v5 (P9) : les personnes et les lieux, leurs anciens noms, et leurs liens avec les notes.
    static let v5PeoplePlaces = """
        CREATE TABLE entity (
          id BLOB PRIMARY KEY NOT NULL,
          kind TEXT NOT NULL CHECK (kind IN ('person','place')),
          name TEXT NOT NULL CHECK (length(trim(name)) > 0),
          normalized_name TEXT NOT NULL CHECK (length(normalized_name) > 0),
          status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','hidden')),
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL,
          UNIQUE (kind, normalized_name)
        );
        CREATE TABLE entity_alias (
          kind TEXT NOT NULL CHECK (kind IN ('person','place')),
          normalized_name TEXT NOT NULL CHECK (length(normalized_name) > 0),
          entity_id BLOB NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
          PRIMARY KEY (kind, normalized_name)
        );
        CREATE INDEX entity_alias_entity ON entity_alias(entity_id);
        CREATE TABLE memory_entity (
          memory_id BLOB NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          entity_id BLOB NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
          origin TEXT NOT NULL CHECK (origin IN ('ai','user')),
          confirmed INTEGER NOT NULL DEFAULT 0 CHECK (confirmed IN (0,1)),
          rejected INTEGER NOT NULL DEFAULT 0 CHECK (rejected IN (0,1)),
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL,
          PRIMARY KEY (memory_id, entity_id),
          CHECK (NOT (confirmed = 1 AND rejected = 1))
        );
        CREATE INDEX memory_entity_entity ON memory_entity(entity_id);
        """

    /// v4 (P4) : distinguer une correction du propriétaire d'une retranscription automatique.
    static let v4OwnerCorrections = """
        ALTER TABLE source ADD COLUMN corrected_by_owner INTEGER NOT NULL DEFAULT 0 CHECK (corrected_by_owner IN (0,1));
        """

    /// v3 (P4) : vérification avant classement, « Garder sur l'iPhone », niveau de confidentialité et routage.
    static let v3ReviewPrivacyRouting = """
        ALTER TABLE source ADD COLUMN needs_review INTEGER NOT NULL DEFAULT 0 CHECK (needs_review IN (0,1));
        ALTER TABLE source ADD COLUMN keep_local INTEGER NOT NULL DEFAULT 0 CHECK (keep_local IN (0,1));
        ALTER TABLE source ADD COLUMN privacy_level TEXT CHECK (privacy_level IN ('neutral','personal','secret'));
        ALTER TABLE source ADD COLUMN analysis_provider TEXT;
        ALTER TABLE source ADD COLUMN route_reason TEXT;
        ALTER TABLE source ADD COLUMN needs_cloud_retry INTEGER NOT NULL DEFAULT 0 CHECK (needs_cloud_retry IN (0,1));
        CREATE INDEX source_needs_review ON source(needs_review) WHERE needs_review = 1;
        CREATE INDEX source_needs_cloud_retry ON source(needs_cloud_retry) WHERE needs_cloud_retry = 1;
        """

    /// v2 (P3) : échéances des souvenirs, liens avec les événements du calendrier, index de la corbeille.
    static let v2DueDatesAndCalendar = """
        ALTER TABLE memory ADD COLUMN due_at DATETIME;
        ALTER TABLE memory ADD COLUMN due_has_time INTEGER NOT NULL DEFAULT 0 CHECK (due_has_time IN (0,1));
        CREATE INDEX memory_due_at ON memory(due_at);
        CREATE INDEX memory_trashed_at ON memory(trashed_at);
        CREATE TABLE calendar_link (
          memory_id BLOB PRIMARY KEY NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          event_identifier TEXT NOT NULL,
          calendar_identifier TEXT,
          created_at DATETIME NOT NULL
        );
        """

    /// Tables suivies par le journal des changements, avec la colonne qui identifie l'entité.
    static let trackedTables: [(table: String, idColumn: String)] = [
        ("source", "id"), ("memory", "id"), ("category", "id"), ("tag", "id"),
        ("memory_category", "memory_id"), ("memory_tag", "memory_id"),
    ]

    static func createChangeLogTriggers(_ db: Database, for tables: [(table: String, idColumn: String)] = trackedTables) throws {
        for (table, idColumn) in tables {
            for (op, row) in [("insert", "new"), ("update", "new"), ("delete", "old")] {
                try db.execute(sql: """
                    CREATE TRIGGER \(table)_log_\(op) AFTER \(op.uppercased()) ON \(table) BEGIN
                      INSERT INTO change_log(entity, entity_id, op, changed_at)
                      VALUES ('\(table)', \(row).\(idColumn), '\(op)', strftime('%Y-%m-%d %H:%M:%f', 'now'));
                    END;
                    """)
            }
        }
    }

    static let v1Tables = """
        CREATE TABLE source (
          id BLOB PRIMARY KEY NOT NULL,
          kind TEXT NOT NULL CHECK (kind IN ('voice','text')),
          audio_path TEXT,
          audio_duration REAL,
          original_text TEXT,
          corrected_text TEXT,
          languages TEXT NOT NULL DEFAULT '[]',
          transcription_engine TEXT,
          content_hash TEXT NOT NULL,
          captured_at DATETIME NOT NULL,
          processing_status TEXT NOT NULL CHECK (processing_status IN
            ('pending','transcribing','analyzing','classifying','indexing','done','waiting','failed')),
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL
        );
        CREATE INDEX source_content_hash ON source(content_hash);
        CREATE INDEX source_captured_at ON source(captured_at);

        CREATE TABLE memory (
          id BLOB PRIMARY KEY NOT NULL,
          source_id BLOB NOT NULL REFERENCES source(id) ON DELETE RESTRICT,
          excerpt TEXT NOT NULL,
          span_start INTEGER,
          span_end INTEGER,
          span_text_version TEXT NOT NULL DEFAULT 'original' CHECK (span_text_version IN ('original','corrected')),
          title TEXT NOT NULL CHECK (length(trim(title)) > 0),
          summary TEXT,
          content TEXT NOT NULL,
          kind TEXT CHECK (kind IN ('idea','task','appointment','decision','preference','info','other')),
          memory_type TEXT,
          status TEXT NOT NULL CHECK (status IN ('active','unsorted','archived','trashed')),
          confidence REAL CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
          suggested_topic TEXT,
          mentioned_dates TEXT NOT NULL DEFAULT '[]',
          user_edited INTEGER NOT NULL DEFAULT 0 CHECK (user_edited IN (0,1)),
          possible_duplicate_of BLOB REFERENCES memory(id) ON DELETE SET NULL,
          analysis_version TEXT NOT NULL,
          captured_at DATETIME NOT NULL,
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL,
          trashed_at DATETIME,
          version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
          CHECK ((status = 'trashed') = (trashed_at IS NOT NULL))
        );
        CREATE INDEX memory_status ON memory(status);
        CREATE INDEX memory_source ON memory(source_id);
        CREATE INDEX memory_captured_at ON memory(captured_at);

        CREATE TABLE memory_version (
          id BLOB PRIMARY KEY NOT NULL,
          memory_id BLOB NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          version INTEGER NOT NULL,
          snapshot TEXT NOT NULL,
          changed_by TEXT NOT NULL CHECK (changed_by IN ('user','ai','system')),
          change_reason TEXT,
          created_at DATETIME NOT NULL,
          UNIQUE (memory_id, version)
        );

        CREATE TABLE category (
          id BLOB PRIMARY KEY NOT NULL,
          name TEXT NOT NULL CHECK (length(trim(name)) > 0),
          normalized_name TEXT NOT NULL CHECK (length(normalized_name) > 0),
          description TEXT,
          parent_id BLOB REFERENCES category(id) ON DELETE RESTRICT,
          origin TEXT NOT NULL CHECK (origin IN ('seed','ai','user')),
          status TEXT NOT NULL CHECK (status IN ('active','archived')),
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL
        );
        CREATE UNIQUE INDEX category_unique_active_name
          ON category(ifnull(parent_id, x''), normalized_name) WHERE status = 'active';
        CREATE INDEX category_parent ON category(parent_id);

        CREATE TABLE memory_category (
          memory_id BLOB NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          category_id BLOB NOT NULL REFERENCES category(id) ON DELETE CASCADE,
          origin TEXT NOT NULL CHECK (origin IN ('ai','user')),
          confidence REAL CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
          confirmed INTEGER NOT NULL DEFAULT 0 CHECK (confirmed IN (0,1)),
          rejected INTEGER NOT NULL DEFAULT 0 CHECK (rejected IN (0,1)),
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL,
          PRIMARY KEY (memory_id, category_id),
          CHECK (NOT (confirmed = 1 AND rejected = 1))
        );
        CREATE INDEX memory_category_category ON memory_category(category_id);

        CREATE TABLE tag (
          id BLOB PRIMARY KEY NOT NULL,
          name TEXT NOT NULL CHECK (length(trim(name)) > 0),
          normalized_name TEXT NOT NULL UNIQUE CHECK (length(normalized_name) > 0),
          origin TEXT NOT NULL CHECK (origin IN ('seed','ai','user')),
          created_at DATETIME NOT NULL
        );

        CREATE TABLE memory_tag (
          memory_id BLOB NOT NULL REFERENCES memory(id) ON DELETE CASCADE,
          tag_id BLOB NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
          origin TEXT NOT NULL CHECK (origin IN ('ai','user')),
          confidence REAL CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
          confirmed INTEGER NOT NULL DEFAULT 0 CHECK (confirmed IN (0,1)),
          rejected INTEGER NOT NULL DEFAULT 0 CHECK (rejected IN (0,1)),
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL,
          PRIMARY KEY (memory_id, tag_id),
          CHECK (NOT (confirmed = 1 AND rejected = 1))
        );
        CREATE INDEX memory_tag_tag ON memory_tag(tag_id);

        CREATE TABLE embedding (
          id BLOB PRIMARY KEY NOT NULL,
          owner_kind TEXT NOT NULL CHECK (owner_kind IN ('memory','category')),
          owner_id BLOB NOT NULL,
          model TEXT NOT NULL,
          dimensions INTEGER NOT NULL CHECK (dimensions > 0),
          vector BLOB NOT NULL,
          input_hash TEXT NOT NULL,
          created_at DATETIME NOT NULL,
          UNIQUE (owner_kind, owner_id, model)
        );
        CREATE TRIGGER memory_embedding_cleanup AFTER DELETE ON memory BEGIN
          DELETE FROM embedding WHERE owner_kind = 'memory' AND owner_id = old.id;
        END;
        CREATE TRIGGER category_embedding_cleanup AFTER DELETE ON category BEGIN
          DELETE FROM embedding WHERE owner_kind = 'category' AND owner_id = old.id;
        END;

        CREATE TABLE processing_job (
          id BLOB PRIMARY KEY NOT NULL,
          source_id BLOB NOT NULL REFERENCES source(id) ON DELETE CASCADE,
          step TEXT NOT NULL CHECK (step IN ('transcribe','analyze','classify','index')),
          status TEXT NOT NULL CHECK (status IN ('queued','running','succeeded','waiting','failed')),
          attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
          max_attempts INTEGER NOT NULL DEFAULT 3 CHECK (max_attempts >= 1),
          next_attempt_at DATETIME,
          last_error TEXT,
          idempotency_key TEXT NOT NULL UNIQUE,
          created_at DATETIME NOT NULL,
          updated_at DATETIME NOT NULL
        );
        CREATE INDEX processing_job_status ON processing_job(status, next_attempt_at);

        CREATE TABLE change_log (
          seq INTEGER PRIMARY KEY AUTOINCREMENT,
          entity TEXT NOT NULL,
          entity_id BLOB NOT NULL,
          op TEXT NOT NULL CHECK (op IN ('insert','update','delete')),
          changed_at DATETIME NOT NULL
        );

        CREATE TABLE setting (
          key TEXT PRIMARY KEY NOT NULL,
          value TEXT NOT NULL,
          updated_at DATETIME NOT NULL
        );
        """

    /// Index plein texte : sa propre copie du texte. Chaque souvenir y a un rowid entier attribué par
    /// `memory_fts_map` (clé entière explicite, stable même après un VACUUM) : les mises à jour et suppressions
    /// visent la ligne par son rowid au lieu de parcourir tout l'index. L'index n'est réécrit que si le texte change.
    static let v1FullText = """
        CREATE TABLE memory_fts_map (
          fts_rowid INTEGER PRIMARY KEY,
          memory_id BLOB NOT NULL UNIQUE
        );
        CREATE VIRTUAL TABLE memory_fts USING fts5(
          title, summary, content, excerpt,
          tokenize = 'unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER memory_fts_insert AFTER INSERT ON memory BEGIN
          INSERT INTO memory_fts_map(memory_id) VALUES (new.id);
          INSERT INTO memory_fts(rowid, title, summary, content, excerpt)
          VALUES ((SELECT fts_rowid FROM memory_fts_map WHERE memory_id = new.id),
                  new.title, ifnull(new.summary, ''), new.content, new.excerpt);
        END;
        CREATE TRIGGER memory_fts_delete AFTER DELETE ON memory BEGIN
          DELETE FROM memory_fts WHERE rowid = (SELECT fts_rowid FROM memory_fts_map WHERE memory_id = old.id);
          DELETE FROM memory_fts_map WHERE memory_id = old.id;
        END;
        CREATE TRIGGER memory_fts_update AFTER UPDATE OF title, summary, content, excerpt ON memory
        WHEN old.title IS NOT new.title OR old.summary IS NOT new.summary
          OR old.content IS NOT new.content OR old.excerpt IS NOT new.excerpt
        BEGIN
          DELETE FROM memory_fts WHERE rowid = (SELECT fts_rowid FROM memory_fts_map WHERE memory_id = old.id);
          INSERT INTO memory_fts(rowid, title, summary, content, excerpt)
          VALUES ((SELECT fts_rowid FROM memory_fts_map WHERE memory_id = new.id),
                  new.title, ifnull(new.summary, ''), new.content, new.excerpt);
        END;
        """
}
