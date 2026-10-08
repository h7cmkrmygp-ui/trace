import EngramCalendar
import EngramCapture
import EngramCore
import EngramIntelligence
import EngramPipeline
import EngramStore
import Foundation
import Observation

/// Services partagés par tous les écrans, et dernière erreur à afficher.
@MainActor
@Observable
final class AppModel {
    let database: AppDatabase
    /// Dossier Engram (base, enregistrements audio).
    let storageDirectory: URL
    let memories: MemoryStore
    let categories: CategoryStore
    let processor: ThoughtProcessor
    let settings: SettingStore
    let calendarLinks: CalendarLinkStore
    let transcriber = FileTranscriber()
    let calendarService = CalendarService()
    var errorMessage: String?
    private var isResuming = false

    init(database: AppDatabase, storageDirectory: URL) {
        self.database = database
        self.storageDirectory = storageDirectory
        memories = MemoryStore(database: database)
        categories = CategoryStore(database: database)
        settings = SettingStore(database: database)
        calendarLinks = CalendarLinkStore(database: database)
        processor = ThoughtProcessor(memories: memories, categories: categories,
                                     filer: ThoughtFiler(database: database), analyzer: AppleThoughtAnalyzer())
    }

    /// Ouvre la base sur l'appareil. Plus de catégories de départ : celles de P1 restées vides sont archivées.
    static func launch() -> Result<AppModel, any Error> {
        Result {
            let model = AppModel(database: try AppDatabase.openOnDisk(),
                                 storageDirectory: try DatabaseRecovery.storageDirectory())
            _ = try model.categories.archiveUnusedSeeds()
            return model
        }
    }

    // MARK: - Traitement des pensées

    /// Transcrit une note vocale. Renvoie `false` si ce n'est pas possible pour l'instant (la note reste en attente).
    func transcribe(sourceID: UUID, audioPath: String) async -> Bool {
        let url = AudioFiles.url(forRelativePath: audioPath, in: storageDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Fichier introuvable : on clôt la transcription pour ne pas réessayer indéfiniment (la note reste « À classer »).
            _ = try? memories.attachTranscript(sourceID: sourceID, transcript: "", languages: [], engine: nil)
            return true
        }
        do {
            let transcript = try await transcriber.transcribe(url: url)
            try memories.attachTranscript(sourceID: sourceID, transcript: transcript.text,
                                          languages: [transcript.localeIdentifier], engine: FileTranscriber.engineName)
            return true
        } catch {
            return false
        }
    }

    func process(sourceID: UUID) async -> ProcessingOutcome {
        await processor.process(sourceID: sourceID)
    }

    /// Reprend le travail interrompu : transcriptions puis analyses en attente.
    func resumePendingWork() async {
        guard !isResuming else { return }
        isResuming = true
        defer { isResuming = false }
        if let pending = try? memories.sourcesAwaitingTranscription() {
            for source in pending {
                if let path = source.audioPath { _ = await transcribe(sourceID: source.id, audioPath: path) }
            }
        }
        _ = await processor.processPending()
        await syncAppointments(askPermission: false)
    }

    /// Ajoute au calendrier de l'iPhone les rendez-vous datés pas encore ajoutés, si l'option est active.
    /// `askPermission` : demander l'accès au calendrier s'il n'a jamais été demandé (juste après une dictée).
    func syncAppointments(askPermission: Bool) async {
        guard (try? settings.bool(.calendarAutoAdd, default: true)) ?? true else { return }
        guard let pending = try? calendarLinks.unlinkedAppointments(), !pending.isEmpty else { return }
        if calendarService.access == .notDetermined {
            guard askPermission, await calendarService.requestAccess() else { return }
        }
        guard calendarService.access == .granted || calendarService.access == .writeOnly else { return }
        let target = (try? settings.string(.calendarTarget)) ?? nil
        for memory in pending {
            guard let start = memory.dueAt else { continue }
            guard let added = try? calendarService.addAppointment(title: memory.title, start: start,
                                                                  hasTime: memory.dueHasTime, notes: memory.summary,
                                                                  calendarIdentifier: target) else { continue }
            try? calendarLinks.link(memoryID: memory.id, eventIdentifier: added.eventID, calendarIdentifier: added.calendarID)
        }
    }

    /// Suppression définitive, y compris le fichier audio s'il n'est plus utilisé.
    func deletePermanently(_ id: UUID) throws {
        let deletion = try memories.deletePermanently(id)
        if let path = deletion.audioPathToRemove {
            try? FileManager.default.removeItem(at: AudioFiles.url(forRelativePath: path, in: storageDirectory))
        }
    }

    // MARK: - Erreurs

    /// Exécute une action ; en cas d'erreur, l'affiche dans une alerte.
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = Self.describe(error) }
    }

    static func describe(_ error: any Error) -> String {
        if let error = error as? StoreError {
            switch error {
            case .emptyContent: return "Le contenu est vide."
            case .notFound: return "Cet élément n'existe plus."
            case .protectedByUser: return "Ce souvenir a été modifié à la main : il est protégé."
            case .nameConflict: return "Une catégorie porte déjà ce nom à cet endroit."
            case .invalidName: return "Ce nom n'est pas valide (vide ou trop long)."
            case .invalidOperation(let reason): return "Opération impossible : \(reason)."
            }
        }
        if let error = error as? MemoryValidationError {
            switch error {
            case .emptyTitle: return "Le titre ne peut pas être vide."
            case .titleTooLong: return "Le titre dépasse 80 caractères."
            case .emptyContent: return "Le contenu ne peut pas être vide."
            case .emptyExcerpt, .invalidStatus, .invalidConfidence: return "Données de souvenir invalides."
            }
        }
        return error.localizedDescription
    }
}
