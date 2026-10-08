import EngramCapture
import EngramCore
import EngramPipeline
import EngramStore
import Foundation
import Observation

/// Parcours d'une capture : enregistrer → sauvegarder → transcrire → classer → afficher le résultat.
/// À chaque étape, la pensée est déjà sauvegardée : un échec ne fait jamais rien perdre.
@MainActor
@Observable
final class RecordModel {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
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
        do {
            try recorder.start(in: app.storageDirectory)
            items = []
            phase = .recording
        } catch {
            phase = .message("Impossible de démarrer l'enregistrement.")
        }
    }

    func finish(app: AppModel) async {
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
            await file(sourceID: memory.sourceID, app: app)
        } catch {
            phase = .message(AppModel.describe(error))
        }
    }

    func submit(text: String, app: AppModel) async {
        do {
            switch try app.memories.saveTextNoteWithoutAnalysis(text) {
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
        recorder.cancel()
        phase = .idle
    }

    private func file(sourceID: UUID, app: AppModel) async {
        phase = .filing
        switch await app.process(sourceID: sourceID) {
        case .filed(let summary):
            items = summary.memories.map { FiledItem(id: $0.id, title: $0.title, path: summary.pathByMemory[$0.id]) }
            phase = .result
        case .waiting(let reason):
            phase = .message("Pensée gardée dans « À classer ». \(reason)")
        case .fallback:
            phase = .message("Pensée gardée dans « À classer » : l'IA n'a pas su la classer.")
        }
    }
}
