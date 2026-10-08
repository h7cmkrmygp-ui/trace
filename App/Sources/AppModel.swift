import EngramCalendar
import EngramCapture
import EngramCore
import EngramIntelligence
import EngramPipeline
import EngramStore
import Foundation
import Observation
import UIKit

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
    /// Modèles Whisper téléchargés (hors du dossier Engram : jamais dans les exports ni dans la sauvegarde iCloud).
    let whisperModels: WhisperModelStore
    let appleTranscriber = FileTranscriber()
    let calendarService = CalendarService()
    var errorMessage: String?
    /// Progression (0 à 1) des modèles Whisper en cours de téléchargement.
    var modelDownloads: [WhisperModel: Double] = [:]
    /// Dernier repli vers la reconnaissance d'Apple, expliqué dans les Réglages.
    var transcriptionNotice: String?
    private var whisperTranscribers: [WhisperModel: WhisperTranscriber] = [:]
    private var isResuming = false
    private var isSyncingCalendar = false
    /// Transcriptions en cours : une même note n'est jamais transcrite deux fois en parallèle.
    private var transcribing: Set<UUID> = []

    init(database: AppDatabase, storageDirectory: URL) {
        self.database = database
        self.storageDirectory = storageDirectory
        memories = MemoryStore(database: database)
        categories = CategoryStore(database: database)
        settings = SettingStore(database: database)
        calendarLinks = CalendarLinkStore(database: database)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        whisperModels = WhisperModelStore(directory: support.appendingPathComponent("WhisperModels", isDirectory: true))
        processor = ThoughtProcessor(memories: memories, categories: categories,
                                     filer: ThoughtFiler(database: database), analyzer: AppleThoughtAnalyzer())
    }

    // MARK: - Réglages de transcription

    var transcriptionEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: ((try? settings.string(.transcriptionEngine)) ?? nil) ?? "") ?? .default
    }

    var whisperModel: WhisperModel {
        WhisperModel(rawValue: ((try? settings.string(.whisperModel)) ?? nil) ?? "") ?? .default
    }

    var reviewsBeforeFiling: Bool {
        (try? settings.bool(.reviewBeforeFiling, default: true)) ?? true
    }

    func whisperTranscriber(for model: WhisperModel) -> WhisperTranscriber {
        if let existing = whisperTranscribers[model] { return existing }
        let created = WhisperTranscriber(model: model, store: whisperModels)
        whisperTranscribers[model] = created
        return created
    }

    /// Télécharge un modèle Whisper (en Wi-Fi de préférence ; l'écran reste allumé pendant le téléchargement).
    func downloadWhisperModel(_ model: WhisperModel) async {
        guard modelDownloads[model] == nil, !whisperModels.isDownloaded(model) else { return }
        modelDownloads[model] = 0
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            modelDownloads[model] = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
        do {
            try await whisperModels.download(model) { [weak self] value in
                guard let self else { return }
                Task { @MainActor in
                    guard self.modelDownloads[model] != nil else { return }
                    self.modelDownloads[model] = value
                }
            }
        } catch {
            errorMessage = "Le téléchargement du modèle a échoué. Vérifie ta connexion (Wi-Fi conseillé) et réessaie."
        }
    }

    func deleteWhisperModel(_ model: WhisperModel) async {
        if let loaded = whisperTranscribers.removeValue(forKey: model) { await loaded.unload() }
        perform { try whisperModels.delete(model) }
    }

    /// Ouvre la base sur l'appareil. Plus de catégories de départ : celles de P1 restées vides sont archivées.
    static func launch() -> Result<AppModel, any Error> {
        Result {
            let model = AppModel(database: try AppDatabase.openOnDisk(),
                                 storageDirectory: try DatabaseRecovery.storageDirectory())
            // Un échec du nettoyage ne doit pas empêcher l'app de s'ouvrir.
            _ = try? model.categories.archiveUnusedSeeds()
            return model
        }
    }

    // MARK: - Traitement des pensées

    /// Transcrit une note vocale. Renvoie `false` si ce n'est pas possible pour l'instant (la note reste en attente).
    func transcribe(sourceID: UUID, audioPath: String) async -> Bool {
        guard !transcribing.contains(sourceID) else { return false }
        transcribing.insert(sourceID)
        defer { transcribing.remove(sourceID) }
        let url = AudioFiles.url(forRelativePath: audioPath, in: storageDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Fichier introuvable : on clôt la transcription pour ne pas réessayer indéfiniment (la note reste « À classer »).
            _ = try? memories.attachTranscript(sourceID: sourceID, transcript: "", languages: [], engine: nil)
            return true
        }
        do {
            let (transcript, engine) = try await runTranscription(url: url)
            try memories.attachTranscript(sourceID: sourceID, transcript: transcript.text,
                                          languages: Self.languages(of: transcript), engine: engine,
                                          needsReview: reviewsBeforeFiling)
            return true
        } catch {
            return false
        }
    }

    /// Whisper si c'est le moteur choisi et que son modèle est sur l'iPhone, sinon la reconnaissance d'Apple.
    private func runTranscription(url: URL) async throws -> (Transcript, String) {
        if transcriptionEngine == .whisper {
            let model = whisperModel
            if whisperModels.isDownloaded(model) {
                let whisper = whisperTranscriber(for: model)
                do {
                    let transcript = try await whisper.transcribe(url: url)
                    transcriptionNotice = nil
                    return (transcript, whisper.engineName)
                } catch {
                    transcriptionNotice = "Whisper n'a pas pu transcrire la dernière note : la reconnaissance d'Apple a pris le relais."
                }
            } else {
                transcriptionNotice = "Le modèle Whisper n'est pas encore téléchargé : la reconnaissance d'Apple a pris le relais."
            }
        }
        let transcript = try await appleTranscriber.transcribe(url: url)
        return (transcript, appleTranscriber.engineName)
    }

    static func languages(of transcript: Transcript) -> [String] {
        transcript.localeIdentifier.split(separator: "+").map(String.init).filter { !$0.isEmpty }
    }

    /// « Vérifie ta note » confirmé : la correction est enregistrée, puis la note est classée.
    func confirmReview(sourceID: UUID, text: String, keepLocal: Bool) async -> ProcessingOutcome? {
        do {
            try memories.confirmReview(sourceID: sourceID, text: text, keepLocal: keepLocal)
        } catch {
            errorMessage = Self.describe(error)
            return nil
        }
        let outcome = await processor.process(sourceID: sourceID)
        if case .filed = outcome { await syncAppointments(askPermission: true) }
        return outcome
    }

    /// Relit l'audio d'une note vocale avec Whisper, puis la reclasse. Les notes modifiées à la main sont gardées.
    @discardableResult
    func retranscribe(sourceID: UUID) async -> Bool {
        guard let source = try? memories.source(id: sourceID), let path = source.audioPath else { return false }
        let url = AudioFiles.url(forRelativePath: path, in: storageDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "L'enregistrement de cette note n'existe plus."
            return false
        }
        let model = whisperModel
        guard whisperModels.isDownloaded(model) else {
            errorMessage = "Télécharge d'abord le modèle Whisper dans Réglages › Transcription."
            return false
        }
        guard !transcribing.contains(sourceID) else { return false }
        transcribing.insert(sourceID)
        defer { transcribing.remove(sourceID) }
        do {
            let whisper = whisperTranscriber(for: model)
            let transcript = try await whisper.transcribe(url: url)
            guard !transcript.text.isEmpty else {
                errorMessage = "Whisper n'a reconnu aucune parole dans cet enregistrement."
                return false
            }
            try memories.retranscribe(sourceID: sourceID, transcript: transcript.text,
                                      languages: Self.languages(of: transcript), engine: whisper.engineName)
            _ = await processor.process(sourceID: sourceID)
            await syncAppointments(askPermission: false)
            return true
        } catch {
            errorMessage = Self.describe(error)
            return false
        }
    }

    /// Retranscrit avec Whisper toutes les notes vocales qui ne l'ont pas encore été. Renvoie le nombre de notes refaites.
    func retranscribeAll(progress: (Int, Int) -> Void) async -> Int {
        let pending = ((try? memories.voiceSources()) ?? []).filter { !($0.transcriptionEngine ?? "").hasPrefix("whisperkit") }
        var done = 0
        for (index, source) in pending.enumerated() {
            progress(index, pending.count)
            if await retranscribe(sourceID: source.id) { done += 1 }
        }
        progress(pending.count, pending.count)
        return done
    }

    func process(sourceID: UUID) async -> ProcessingOutcome {
        await processor.process(sourceID: sourceID)
    }

    /// Reprend le travail interrompu : transcriptions puis analyses en attente.
    func resumePendingWork() async {
        guard !isResuming else { return }
        isResuming = true
        defer { isResuming = false }
        adoptOrphanedRecordings()
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
        guard !isSyncingCalendar else { return }
        isSyncingCalendar = true
        defer { isSyncingCalendar = false }
        guard (try? settings.bool(.calendarAutoAdd, default: true)) ?? true else { return }
        guard let waiting = try? calendarLinks.unlinkedAppointments(), !waiting.isEmpty else { return }
        if calendarService.access == .notDetermined {
            guard askPermission, await calendarService.requestAccess() else { return }
        }
        guard calendarService.access == .granted || calendarService.access == .writeOnly else { return }
        let target = (try? settings.string(.calendarTarget)) ?? nil
        // Relire la liste après l'attente de l'autorisation, et revérifier chaque lien juste avant d'ajouter.
        guard let pending = try? calendarLinks.unlinkedAppointments() else { return }
        for memory in pending {
            guard let start = memory.dueAt, (try? calendarLinks.link(for: memory.id)) == nil else { continue }
            guard let added = try? calendarService.addAppointment(title: memory.title, start: start,
                                                                  hasTime: memory.dueHasTime, notes: memory.summary,
                                                                  calendarIdentifier: target) else { continue }
            try? calendarLinks.link(memoryID: memory.id, eventIdentifier: added.eventID, calendarIdentifier: added.calendarID)
        }
    }

    /// Enregistrements restés sur le disque sans note (app fermée pendant l'enregistrement) : ils deviennent
    /// des notes vocales à transcrire. Seuls les fichiers de plus de 6 minutes sont pris (jamais celui en cours).
    func adoptOrphanedRecordings() {
        guard let referenced = try? memories.referencedAudioPaths(),
              let orphans = try? AudioFiles.orphanedRecordings(in: storageDirectory, referenced: referenced,
                                                               olderThan: Date().addingTimeInterval(-6 * 60))
        else { return }
        for path in orphans { _ = try? memories.saveVoiceRecording(audioPath: path, duration: nil) }
    }

    /// Suppression définitive, y compris le fichier audio s'il n'est plus utilisé.
    func deletePermanently(_ id: UUID) throws {
        let deletion = try memories.deletePermanently(id)
        if let path = deletion.audioPathToRemove {
            try? FileManager.default.removeItem(at: AudioFiles.url(forRelativePath: path, in: storageDirectory))
        }
    }

    /// Vide la corbeille, avec les fichiers audio qui ne servent plus.
    func emptyTrash() throws {
        for deletion in try memories.emptyTrash() {
            if let path = deletion.audioPathToRemove {
                try? FileManager.default.removeItem(at: AudioFiles.url(forRelativePath: path, in: storageDirectory))
            }
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
        if let error = error as? TranscriptionError {
            switch error {
            case .unsupportedLanguage: return "La reconnaissance vocale ne prend pas en charge cette langue sur cet iPhone."
            case .modelUnavailable(let reason): return reason
            case .unreadableAudio: return "L'enregistrement ne peut pas être lu."
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
