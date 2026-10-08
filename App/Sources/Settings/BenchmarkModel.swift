import EngramCapture
import EngramCore
import Foundation
import Observation
import UIKit

/// Banc d'essai Whisper : les phrases lues par le propriétaire et ses notes réelles corrigées sont transcrites
/// par chaque modèle et chaque stratégie, puis comparées. Tout reste sur l'iPhone ; aucun changement n'est
/// appliqué sans la validation du propriétaire.
@MainActor
@Observable
final class BenchmarkModel {
    struct Recording: Codable, Identifiable, Equatable {
        /// « phrase-15 » ou « note-<identifiant> ».
        var id: String
        var sentenceID: Int?
        var sourceID: UUID?
        /// Relatif au dossier du banc d'essai (phrase) ou au dossier Engram (note).
        var relativePath: String
        var duration: Double
        var reference: String
        var englishWords: [String]
    }

    struct Run: Codable, Equatable {
        var recordingID: String
        /// « <modèle>|<stratégie> ».
        var configuration: String
        var text: String
        var seconds: Double
    }

    struct Measures: Codable, Equatable {
        /// Modèle → pourcentage de batterie utilisé par minute d'audio transcrite.
        var batteryPerMinute: [String: Double] = [:]
        var loadFailures: Set<String> = []
        var seriousHeat: Set<String> = []
    }

    struct Saved: Codable, Equatable {
        var sentences: [Recording] = []
        var runs: [Run] = []
        var measures = Measures()
    }

    struct Row: Identifiable {
        let id: String
        let model: WhisperModel
        let strategy: TranscriptionStrategy
        let wordErrorRate: Double?
        let englishRetention: Double?
        let realTimeFactor: Double?
        let batteryPerMinute: Double?
    }

    private(set) var saved = Saved()
    /// Notes réelles dont le propriétaire a corrigé la transcription (recalculées à l'ouverture).
    private(set) var notes: [Recording] = []
    private(set) var progress: (done: Int, total: Int)?
    private(set) var statusMessage: String?
    /// Modèles qu'Argmax déclare pris en charge par cette puce (nil : table inconnue, sans effet sur la règle).
    var supportedModels: Set<String>?
    let recorder = VoiceRecorder()
    private var runTask: Task<Void, Never>?

    static func configuration(_ model: WhisperModel, _ strategy: TranscriptionStrategy) -> String {
        "\(model.rawValue)|\(strategy.rawValue)"
    }

    var isRunning: Bool { runTask != nil }

    var nextSentence: BenchmarkSentence? {
        BilingualTestSet.sentences.first { sentence in !saved.sentences.contains { $0.sentenceID == sentence.id } }
    }

    // MARK: - Chargement et sauvegarde

    func load(app: AppModel) {
        if let data = try? Data(contentsOf: resultsFile(app)), let decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = decoded
        }
        // Seules les corrections faites à la main servent de référence (jamais une retranscription automatique).
        notes = ((try? app.memories.voiceSources()) ?? []).compactMap { source in
            guard source.correctedByOwner, let corrected = source.correctedText, let path = source.audioPath,
                  FileManager.default.fileExists(atPath: AudioFiles.url(forRelativePath: path, in: app.storageDirectory).path)
            else { return nil }
            return Recording(id: "note-\(source.id.uuidString)", sentenceID: nil, sourceID: source.id, relativePath: path,
                             duration: source.audioDuration ?? 0, reference: corrected, englishWords: [])
        }
    }

    private func resultsFile(_ app: AppModel) -> URL {
        app.benchmarkDirectory.appendingPathComponent("results.json")
    }

    private func save(_ app: AppModel) {
        do {
            try FileManager.default.createDirectory(at: app.benchmarkDirectory, withIntermediateDirectories: true)
            var directory = app.benchmarkDirectory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
            try JSONEncoder().encode(saved).write(to: resultsFile(app), options: .atomic)
        } catch {
            app.errorMessage = "Impossible d'enregistrer le banc d'essai."
        }
    }

    // MARK: - Lecture des phrases

    func startRecording(app: AppModel) async {
        guard await VoiceRecorder.requestPermission() else {
            statusMessage = "Autorise le micro : Réglages › Engram › Micro."
            return
        }
        do {
            try FileManager.default.createDirectory(at: app.benchmarkDirectory, withIntermediateDirectories: true)
            try recorder.start(in: app.benchmarkDirectory)
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            statusMessage = "Impossible de démarrer l'enregistrement."
        }
    }

    func stopRecording(sentence: BenchmarkSentence, app: AppModel) {
        UIApplication.shared.isIdleTimerDisabled = false
        guard let result = recorder.stop() else { return }
        let id = "phrase-\(sentence.id)"
        saved.sentences.removeAll { $0.id == id }
        saved.runs.removeAll { $0.recordingID == id }
        saved.sentences.append(Recording(id: id, sentenceID: sentence.id, sourceID: nil, relativePath: result.relativePath,
                                         duration: result.duration, reference: sentence.text,
                                         englishWords: sentence.englishWords))
        save(app)
    }

    func cancelRecording() {
        UIApplication.shared.isIdleTimerDisabled = false
        recorder.cancel()
    }

    /// Recommence la dernière phrase lue (mal prononcée, bruit…).
    func redoLastSentence(app: AppModel) {
        guard let last = saved.sentences.last else { return }
        try? FileManager.default.removeItem(at: app.benchmarkDirectory.appendingPathComponent(last.relativePath))
        saved.sentences.removeLast()
        saved.runs.removeAll { $0.recordingID == last.id }
        save(app)
    }

    // MARK: - Comparaison

    func startComparison(app: AppModel) {
        guard runTask == nil else { return }
        runTask = Task {
            await runComparison(app: app)
            runTask = nil
        }
    }

    func cancelComparison() {
        runTask?.cancel()
    }

    private func runComparison(app: AppModel) async {
        let missingModels = WhisperModel.allCases.filter { !app.whisperModels.isDownloaded($0) }
        guard missingModels.isEmpty else {
            statusMessage = "Télécharge d'abord les deux modèles dans Réglages › Transcription."
            return
        }
        let recordings = saved.sentences + notes
        let total = WhisperModel.allCases.count * TranscriptionStrategy.allCases.count * recordings.count
        var done = saved.runs.filter { run in recordings.contains { $0.id == run.recordingID } }.count
        progress = (done, total)
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            progress = nil
        }
        statusMessage = nil
        for model in WhisperModel.allCases {
            // Un seul grand modèle en mémoire à la fois.
            for other in WhisperModel.allCases where other != model { await app.whisperTranscriber(for: other).unload() }
            let whisper = app.whisperTranscriber(for: model)
            let batteryStart = Self.batteryLevel()
            var audioSeconds = 0.0
            strategies: for strategy in TranscriptionStrategy.allCases {
                let configuration = Self.configuration(model, strategy)
                for recording in recordings where run(recording.id, configuration) == nil {
                    if Task.isCancelled {
                        save(app)
                        statusMessage = "Comparaison interrompue : elle reprendra là où elle s'est arrêtée."
                        return
                    }
                    let url = recording.sentenceID != nil
                        ? app.benchmarkDirectory.appendingPathComponent(recording.relativePath)
                        : AudioFiles.url(forRelativePath: recording.relativePath, in: app.storageDirectory)
                    let start = Date()
                    do {
                        let transcript = try await whisper.transcribe(url: url, strategy: strategy)
                        saved.runs.append(Run(recordingID: recording.id, configuration: configuration,
                                              text: transcript.text, seconds: Date().timeIntervalSince(start)))
                        audioSeconds += recording.duration
                    } catch TranscriptionError.modelUnavailable {
                        // Le modèle ne se charge pas sur cet iPhone : inutile de réessayer avec les autres stratégies.
                        saved.measures.loadFailures.insert(model.rawValue)
                        save(app)
                        break strategies
                    } catch {
                        continue
                    }
                    if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                        saved.measures.seriousHeat.insert(model.rawValue)
                    }
                    done += 1
                    progress = (done, total)
                }
                save(app)
            }
            if let batteryStart, let batteryEnd = Self.batteryLevel(), audioSeconds > 0 {
                saved.measures.batteryPerMinute[model.rawValue] = max(0, batteryStart - batteryEnd) * 100 / (audioSeconds / 60)
            }
            save(app)
        }
        // Libérer le modèle qui n'est pas utilisé au quotidien.
        for other in WhisperModel.allCases where other != app.whisperModel { await app.whisperTranscriber(for: other).unload() }
        statusMessage = "Comparaison terminée."
    }

    /// Niveau de batterie (0 à 1), ou nil s'il est inconnu ou si l'iPhone est branché (mesure faussée).
    static func batteryLevel() -> Double? {
        let device = UIDevice.current
        guard device.batteryState == .unplugged, device.batteryLevel >= 0 else { return nil }
        return Double(device.batteryLevel)
    }

    func run(_ recordingID: String, _ configuration: String) -> Run? {
        saved.runs.first { $0.recordingID == recordingID && $0.configuration == configuration }
    }

    // MARK: - Résultats

    var rows: [Row] {
        let recordings = saved.sentences + notes
        return WhisperModel.allCases.flatMap { model in
            TranscriptionStrategy.allCases.map { strategy in
                let configuration = Self.configuration(model, strategy)
                var words = 0
                var errors = 0
                var retention: [Double] = []
                var seconds = 0.0
                var audio = 0.0
                for recording in recordings {
                    guard let run = run(recording.id, configuration) else { continue }
                    let reference = WordErrorRate.words(recording.reference)
                    words += reference.count
                    errors += WordErrorRate.errors(reference: reference, hypothesis: WordErrorRate.words(run.text))
                    if let value = EnglishRetention.rate(englishWords: recording.englishWords, hypothesis: run.text) {
                        retention.append(value)
                    }
                    seconds += run.seconds
                    audio += recording.duration
                }
                return Row(id: configuration, model: model, strategy: strategy,
                           wordErrorRate: words > 0 ? Double(errors) / Double(words) : nil,
                           englishRetention: retention.isEmpty ? nil : retention.reduce(0, +) / Double(retention.count),
                           realTimeFactor: audio > 0 ? seconds / audio : nil,
                           batteryPerMinute: saved.measures.batteryPerMinute[model.rawValue])
            }
        }
    }

    /// Preuves pour remplacer `baseline` par `candidate` : seuls les enregistrements transcrits par les deux comptent.
    func evidence(baseline: String, candidate: String, candidateModel: WhisperModel) -> BenchmarkEvidence {
        var items: [BenchmarkItem] = []
        var sentencesRead = 0
        var correctedNotes = 0
        for recording in saved.sentences + notes {
            guard let base = run(recording.id, baseline), let cand = run(recording.id, candidate) else { continue }
            let reference = WordErrorRate.words(recording.reference)
            guard !reference.isEmpty else { continue }
            items.append(BenchmarkItem(
                referenceWords: reference.count,
                baselineErrors: WordErrorRate.errors(reference: reference, hypothesis: WordErrorRate.words(base.text)),
                candidateErrors: WordErrorRate.errors(reference: reference, hypothesis: WordErrorRate.words(cand.text))))
            if recording.sentenceID != nil { sentencesRead += 1 } else { correctedNotes += 1 }
        }
        let speed = rows.first { $0.id == candidate }?.realTimeFactor
        let runsWell = (supportedModels.map { $0.contains(candidateModel.rawValue) } ?? true)
            && !saved.measures.loadFailures.contains(candidateModel.rawValue)
            && !saved.measures.seriousHeat.contains(candidateModel.rawValue)
            && (speed.map { $0 <= 1.0 } ?? false)
        return BenchmarkEvidence(sentencesRead: sentencesRead, sentencesTotal: BilingualTestSet.sentences.count,
                                 correctedNotes: correctedNotes, items: items, candidateRunsWell: runsWell)
    }

    func modelRecommendation(app: AppModel) -> (model: WhisperModel, verdict: ModelRecommendation) {
        let current = app.whisperModel
        let other = WhisperModel.allCases.first { $0 != current } ?? current
        let strategy = app.whisperStrategy
        let verdict = ModelRecommendation.evaluate(evidence(baseline: Self.configuration(current, strategy),
                                                            candidate: Self.configuration(other, strategy),
                                                            candidateModel: other))
        return (other, verdict)
    }

    /// La meilleure autre stratégie pour le modèle actuel, avec son verdict.
    func strategyRecommendation(app: AppModel) -> (strategy: TranscriptionStrategy, verdict: ModelRecommendation)? {
        let model = app.whisperModel
        let current = app.whisperStrategy
        let verdicts = TranscriptionStrategy.allCases.filter { $0 != current }.map { strategy in
            (strategy, ModelRecommendation.evaluate(evidence(baseline: Self.configuration(model, current),
                                                             candidate: Self.configuration(model, strategy),
                                                             candidateModel: model)))
        }
        if let proposed = verdicts.first(where: { if case .proposeSwitch = $0.1 { true } else { false } }) { return proposed }
        return verdicts.first
    }

    /// Efface les phrases lues et les résultats (les notes ne sont pas touchées).
    func reset(app: AppModel) {
        try? FileManager.default.removeItem(at: app.benchmarkDirectory)
        saved = Saved()
        statusMessage = nil
    }
}
