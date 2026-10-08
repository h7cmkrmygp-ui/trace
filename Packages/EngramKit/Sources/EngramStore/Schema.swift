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
        return migrator
    }

    /// Tables suivies par le journal des changements, avec la colonne qui identifie l'entité.
    static let trackedTables: [(table: String, idColumn: String)] = [
        ("source", "id"), ("memory", "id"), ("category", "id"), ("tag", "id"),
        ("memory_category", "memory_id"), ("memory_tag", "memory_id"),
    ]

    static func createChangeLogTriggers(_ db: Database) throws {
        for (table, idColumn) in trackedTables {
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
