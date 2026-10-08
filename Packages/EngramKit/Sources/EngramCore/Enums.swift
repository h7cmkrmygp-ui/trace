import Foundation

/// Type d'une capture.
public enum SourceKind: String, Codable, Sendable, CaseIterable { case voice, text }

/// Avancement du traitement d'une source.
public enum ProcessingStatus: String, Codable, Sendable, CaseIterable {
    case pending, transcribing, analyzing, classifying, indexing, done, waiting, failed
}

/// État d'un souvenir. « À classer » = `unsorted`.
public enum MemoryStatus: String, Codable, Sendable, CaseIterable {
    case active, unsorted, archived, trashed
}

/// Nature de l'information extraite.
public enum MemoryKind: String, Codable, Sendable, CaseIterable {
    case idea, task, appointment, decision, preference, info, other
}

/// Texte de référence d'un extrait : transcription originale ou corrigée.
public enum TextVersion: String, Codable, Sendable { case original, corrected }

/// Qui a créé une catégorie ou un tag.
public enum Origin: String, Codable, Sendable { case seed, ai, user }

/// Qui a posé un lien souvenir ↔ catégorie ou tag.
public enum AssignmentOrigin: String, Codable, Sendable { case ai, user }

/// Qui a modifié un souvenir.
public enum ChangeActor: String, Codable, Sendable { case user, ai, system }

/// État d'une catégorie.
public enum CategoryStatus: String, Codable, Sendable { case active, archived }
