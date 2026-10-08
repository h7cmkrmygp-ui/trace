import EngramCapture
import EngramCore
import EngramPipeline
import EngramStore
import Foundation
import Observation
import UIKit

/// Parcours d'une capture : enregistrer → sauvegarder → transcrire → vérifier → classer → afficher le résultat.
/// À chaque étape, la pensée est déjà sauvegardée : un échec ne fait jamais rien perdre.
@MainActor
@Observable
final class RecordModel {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        /// « Vérifie ta note » : la transcription attend la confirmation du propriétaire.
        case review
        case filing
        case result
        case message(String)
    }

    struct FiledItem: Identifiable, Equatable {
        let id: UUID
        let title: String
        let path: String?
    }

    private(set) var phase: Phase = .idle
    private(set) var items: [FiledItem] = []
    /// Dictée en cours de vérification (phase `.review`).
    var review: ReviewDraft?
    private(set) var reviewAudioURL: URL?
    let recorder = VoiceRecorder()

    var isBusy: Bool { phase == .transcribing || phase == .filing }

    func toggle(app: AppModel) async {
        switch recorder.state {
        case .idle: await start(app: app)
        case .recording, .finished: await finish(app: app)
        }
    }

    func start(app: AppModel) async {
        guard await VoiceRecorder.requestPermission() else {
            phase = .message("Autorise le micro : Réglages › Engram › Micro.")
            return
        }
        // Une nouvelle dictée pendant une vérification : la précédente reste « À vérifier » dans les Notes.
        review = nil
        reviewAudioURL = nil
        do {
            try recorder.start(in: app.storageDirectory)
            // L'écran ne se verrouille pas pendant une dictée (sinon l'enregistrement serait coupé).
            UIApplication.shared.isIdleTimerDisabled = true
            items = []
            phase = .recording
        } catch {
            phase = .message("Impossible de démarrer l'enregistrement.")
        }
    }

    func finish(app: AppModel) async {
        UIApplication.shared.isIdleTimerDisabled = false
        guard let result = recorder.stop() else {
            phase = .idle
            return
        }
        do {
            let memory = try app.memories.saveVoiceRecording(audioPath: result.relativePath, duration: result.duration)
            phase = .transcribing
            guard await app.transcribe(sourceID: memory.sourceID, audioPath: result.relativePath) else {
                phase = .message("Pensée enregistrée. La transcription se fera dès que possible.")
                return
            }
            if let source = try? app.memories.source(id: memory.sourceID), source.needsReview {
                review = ReviewDraft(sourceID: source.id, text: source.originalText ?? "")
                reviewAudioURL = result.url
                phase = .review
                return
            }
            await file(sourceID: memory.sourceID, app: app)
        } catch {
            phase = .message(AppModel.describe(error))
        }
    }

    /// « Classer » sur la carte de vérification.
    func confirmReview(app: AppModel) async {
        guard let review else { return }
        do {
            try app.memories.confirmReview(sourceID: review.sourceID, text: review.text, keepLocal: review.keepLocal)
        } catch {
            phase = .message(AppModel.describe(error))
            return
        }
        self.review = nil
        reviewAudioURL = nil
        await file(sourceID: review.sourceID, app: app)
    }

    /// « Annuler » sur la carte de vérification : la note va à la corbeille, sans être analysée.
    func discardReview(app: AppModel) {
        guard let review else { return }
        do {
            try app.memories.discardReview(sourceID: review.sourceID)
            phase = .message("Note annulée : elle est dans la corbeille si tu changes d'avis.")
        } catch {
            phase = .message(AppModel.describe(error))
        }
        self.review = nil
        reviewAudioURL = nil
    }

    func submit(text: String, keepLocal: Bool = false, app: AppModel) async {
        do {
            switch try app.memories.saveTextNoteWithoutAnalysis(text, keepLocal: keepLocal) {
            case .duplicate:
                phase = .message("Cette pensée vient déjà d'être enregistrée.")
            case .saved(let memory):
                await file(sourceID: memory.sourceID, app: app)
            }
        } catch {
            phase = .message(AppModel.describe(error))
        }
    }

    func cancel() {
        UIApplication.shared.isIdleTimerDisabled = false
        recorder.cancel()
        phase = .idle
    }

    private func file(sourceID: UUID, app: AppModel) async {
        phase = .filing
        switch await app.process(sourceID: sourceID) {
        case .filed(let summary):
            items = summary.memories.map { FiledItem(id: $0.id, title: $0.title, path: summary.pathByMemory[$0.id]) }
            phase = .result
            await app.syncAppointments(askPermission: true)
        case .waiting(let reason):
            phase = .message("Pensée gardée dans « À classer ». \(reason)")
        case .fallback:
            phase = .message("Pensée gardée dans « À classer » : l'IA n'a pas su la classer.")
        }
    }
}
