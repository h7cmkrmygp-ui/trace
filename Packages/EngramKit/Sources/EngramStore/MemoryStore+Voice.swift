import EngramCore
import Foundation
import GRDB

/// Notes vocales : l'audio est sauvegardé dès l'arrêt, la transcription suit, puis l'analyse.
extension MemoryStore {
    public static let pendingTranscriptTitle = "Note vocale"
    public static let emptyTranscriptTitle = "Note vocale sans transcription"
    static let pendingTranscriptContent = "(transcription en cours — l'audio est conservé)"
    static let emptyTranscriptContent = "(aucune parole reconnue — l'audio est conservé)"

    /// Étape 1 : source vocale « en attente de transcription » et souvenir provisoire « À classer ».
    public func saveVoiceRecording(audioPath: String, duration: Double?) throws -> Memory {
        let now = dates.now()
        return try database.writer.write { db in
            try saveVoiceRecording(db, audioPath: audioPath, duration: duration, now: now)
        }
    }

    func saveVoiceRecording(_ db: Database, audioPath: String, duration: Double?, now: Date) throws -> Memory {
        let source = Source(kind: .voice, audioPath: audioPath, audioDuration: duration,
                            contentHash: ContentHasher.textHash("audio:" + audioPath),
                            capturedAt: now, processingStatus: .pending, createdAt: now, updatedAt: now)
        try source.insert(db)
        let draft = MemoryDraft(sourceID: source.id, excerpt: Self.pendingTranscriptContent,
                                title: Self.pendingTranscriptTitle, content: Self.pendingTranscriptContent,
                                status: .unsorted, analysisVersion: Self.interimAnalysisVersion)
        return try createMemory(db, draft: draft, actor: .system, now: now)
    }

    /// Étape 2 : la transcription est jointe à la source (qui passe en attente d'analyse) et au souvenir
    /// provisoire, sauf s'il a été modifié à la main.
    @discardableResult
    public func attachTranscript(sourceID: UUID, transcript: String, languages: [String], engine: String?) throws -> Memory? {
        let now = dates.now()
        return try database.writer.write { db in
            try attachTranscript(db, sourceID: sourceID, transcript: transcript, languages: languages, engine: engine, now: now)
        }
    }

    func attachTranscript(_ db: Database, sourceID: UUID, transcript: String, languages: [String],
                          engine: String?, now: Date) throws -> Memory? {
        guard var source = try Source.fetchOne(db, key: sourceID) else { throw StoreError.notFound }
        // Une transcription tardive (traitement en double) ne rouvre jamais une source déjà transcrite ou classée.
        guard source.processingStatus == .pending else {
            return try Memory
                .filter(Column("source_id") == sourceID && Column("analysis_version") == Self.interimAnalysisVersion)
                .fetchOne(db)
        }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        source.originalText = text.isEmpty ? nil : text
        source.languages = languages
        source.transcriptionEngine = engine
        source.processingStatus = .waiting
        source.updatedAt = now
        try source.update(db)

        guard var interim = try Memory
            .filter(Column("source_id") == sourceID && Column("analysis_version") == Self.interimAnalysisVersion)
            .fetchOne(db)
        else { return nil }
        guard !interim.userEdited else { return interim }
        let body = text.isEmpty ? Self.emptyTranscriptContent : text
        interim.title = text.isEmpty ? Self.emptyTranscriptTitle : TitleMaker.fallbackTitle(from: text)
        interim.content = body
        interim.excerpt = body
        interim.spanStart = text.isEmpty ? nil : 0
        interim.spanEnd = text.isEmpty ? nil : text.utf16.count
        interim.version += 1
        interim.updatedAt = now
        try interim.update(db)
        try MemoryVersion(memory: interim, changedBy: .system, reason: "transcription", at: now).insert(db)
        return interim
    }

    /// Les deux étapes en une seule transaction, quand la transcription est déjà connue.
    public func saveVoiceNote(audioPath: String, duration: Double?, transcript: String,
                              languages: [String], engine: String?) throws -> Memory {
        let now = dates.now()
        return try database.writer.write { db in
            let recording = try saveVoiceRecording(db, audioPath: audioPath, duration: duration, now: now)
            return try attachTranscript(db, sourceID: recording.sourceID, transcript: transcript,
                                        languages: languages, engine: engine, now: now) ?? recording
        }
    }

    /// Notes vocales dont la transcription reste à faire (app fermée entre-temps, langue à télécharger…).
    public func sourcesAwaitingTranscription() throws -> [Source] {
        try database.writer.read { db in
            try Source
                .filter(Column("kind") == SourceKind.voice && Column("processing_status") == ProcessingStatus.pending)
                .order(Column("captured_at"))
                .fetchAll(db)
        }
    }

    /// Nouvelle transcription d'une note vocale par un meilleur moteur. La transcription d'origine est gardée,
    /// la nouvelle devient le texte de référence ; les souvenirs que l'IA avait tirés de l'ancienne et que le
    /// propriétaire n'a pas touchés sont remplacés par une note provisoire, qui sera ré-analysée.
    @discardableResult
    public func retranscribe(sourceID: UUID, transcript: String, languages: [String], engine: String?) throws -> Memory? {
        let now = dates.now()
        return try database.writer.write { db in
            guard var source = try Source.fetchOne(db, key: sourceID) else { throw StoreError.notFound }
            guard source.kind == .voice else { throw StoreError.invalidOperation("seule une note vocale peut être retranscrite") }
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw StoreError.emptyContent }
            source.correctedText = text
            source.languages = languages
            source.transcriptionEngine = engine
            source.processingStatus = .waiting
            source.updatedAt = now
            try source.update(db)

            var keptAny = false
            for memory in try Memory.filter(Column("source_id") == sourceID).fetchAll(db) {
                if try ThoughtFiler.isTouchedByOwner(db, memory) { keptAny = true } else { _ = try memory.delete(db) }
            }
            guard !keptAny else { return nil }
            let draft = MemoryDraft(sourceID: sourceID, excerpt: text, spanStart: 0, spanEnd: text.utf16.count,
                                    spanTextVersion: .corrected, title: TitleMaker.fallbackTitle(from: text), content: text,
                                    status: .unsorted, analysisVersion: Self.interimAnalysisVersion)
            return try createMemory(db, draft: draft, actor: .system, now: now)
        }
    }

    /// Toutes les notes vocales dont l'audio est conservé (pour les retranscrire).
    public func voiceSources() throws -> [Source] {
        try database.writer.read { db in
            try Source.filter(Column("kind") == SourceKind.voice && Column("audio_path") != nil)
                .order(Column("captured_at"))
                .fetchAll(db)
        }
    }

    /// Fichiers audio déjà connus (pour retrouver les enregistrements orphelins).
    public func referencedAudioPaths() throws -> Set<String> {
        try database.writer.read { db in
            Set(try String.fetchAll(db, sql: "SELECT audio_path FROM source WHERE audio_path IS NOT NULL"))
        }
    }

    /// Sources prêtes pour l'analyse par l'IA, de la plus ancienne à la plus récente.
    public func sourcesAwaitingAnalysis() throws -> [UUID] {
        try database.writer.read { db in
            try UUID.fetchAll(db, sql: "SELECT id FROM source WHERE processing_status = 'waiting' ORDER BY captured_at")
        }
    }

    /// Liste observée filtrée par type (pour « À faire »).
    public func memoriesStream(kinds: Set<MemoryKind>, statuses: Set<MemoryStatus>,
                               limit: Int = 500) -> AsyncThrowingStream<[Memory], any Error> {
        database.stream { db in
            try Memory
                .filter(statuses.contains(Column("status")) && kinds.contains(Column("kind")))
                .order(Column("captured_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
