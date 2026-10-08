import Foundation
import WhisperKit

/// Les modèles Whisper téléchargés sur l'iPhone, dans un dossier exclu de la sauvegarde iCloud.
public struct WhisperModelStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private func recordFile(_ model: WhisperModel) -> URL {
        directory.appendingPathComponent("\(model.rawValue).folder")
    }

    /// Dossier du modèle, seulement si son téléchargement est allé jusqu'au bout.
    public func folder(for model: WhisperModel) -> URL? {
        guard let relative = try? String(contentsOf: recordFile(model), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !relative.isEmpty else { return nil }
        let url = directory.appendingPathComponent(relative, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func isDownloaded(_ model: WhisperModel) -> Bool { folder(for: model) != nil }

    /// Télécharge le modèle depuis Hugging Face (gratuit, une seule fois). `progress` reçoit une valeur de 0 à 1.
    public func download(_ model: WhisperModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard !isDownloaded(model) else {
            progress(1)
            return
        }
        try prepareDirectory()
        let folder = try await WhisperKit.download(variant: model.rawValue, downloadBase: directory,
                                                   progressCallback: { progress($0.fractionCompleted) })
        // Chemin relatif : le dossier de l'app peut changer de chemin absolu après une réinstallation (AltStore).
        try Self.relativePath(of: folder, in: directory).write(to: recordFile(model), atomically: true, encoding: .utf8)
    }

    /// Libère la place prise par un modèle.
    public func delete(_ model: WhisperModel) throws {
        if let folder = folder(for: model) { try FileManager.default.removeItem(at: folder) }
        try? FileManager.default.removeItem(at: recordFile(model))
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// Chemin de `folder` relatif à `base`, liens symboliques résolus (« /var » et « /private/var » sur iOS).
    static func relativePath(of folder: URL, in base: URL) -> String {
        let folderParts = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let baseParts = base.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard folderParts.starts(with: baseParts) else { return folder.lastPathComponent }
        return folderParts.dropFirst(baseParts.count).joined(separator: "/")
    }

    /// Modèles qu'Argmax déclare pris en charge par cet appareil (table officielle en ligne) ; nil si inconnue.
    public static func supportedModelsOnThisDevice() async -> Set<String>? {
        let support = await WhisperKit.recommendedRemoteModels()
        return support.supported.isEmpty ? nil : Set(support.supported)
    }
}

/// Whisper **sur l'iPhone**, avec la stratégie bilingue : chaque morceau de parole (découpé sur les silences)
/// est décodé dans sa langue dominante, ou dans les deux langues s'il est mélangé ; on garde l'hypothèse
/// la plus probable. Tâche `transcribe` uniquement : Whisper ne traduit jamais.
public final class WhisperTranscriber: AudioTranscriber, @unchecked Sendable {
    public let model: WhisperModel
    public var engineName: String { model.engineName }

    private let store: WhisperModelStore
    private let lock = NSLock()
    private var pipeline: WhisperKit?
    private var strategyValue: TranscriptionStrategy

    /// Fenêtre de Whisper : 30 s à 16 kHz.
    static let windowSamples = 480_000

    public init(model: WhisperModel, store: WhisperModelStore, strategy: TranscriptionStrategy = .default) {
        self.model = model
        self.store = store
        self.strategyValue = strategy
    }

    /// Stratégie utilisée par `transcribe(url:)` (réglée dans les Réglages).
    public var strategy: TranscriptionStrategy {
        get { lock.withLock { strategyValue } }
        set { lock.withLock { strategyValue = newValue } }
    }

    public func transcribe(url: URL) async throws -> Transcript {
        try await transcribe(url: url, strategy: strategy)
    }

    /// Transcription avec une stratégie précise (le banc d'essai compare les trois avec le même modèle chargé).
    public func transcribe(url: URL, strategy: TranscriptionStrategy) async throws -> Transcript {
        let kit = try await loadedPipeline()
        let audio: [Float]
        do {
            audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        } catch {
            throw TranscriptionError.unreadableAudio
        }
        let chunks: [[Float]]
        if audio.count > Self.windowSamples {
            chunks = try await VADAudioChunker()
                .chunkAll(audioArray: audio, maxChunkLength: Self.windowSamples, decodeOptions: nil)
                .map(\.audioSamples)
        } else {
            chunks = [audio]
        }
        let prompt = Self.promptTokens(for: kit)
        var pieces: [Hypothesis] = []
        for samples in chunks {
            try Task.checkCancellation()
            if strategy == .automatic {
                // Détection libre : Whisper choisit seul sa langue, un seul décodage.
                let results = try await kit.transcribe(audioArray: samples,
                                                       decodeOptions: Self.options(language: nil, prompt: prompt))
                let hypothesis = Self.hypothesis(language: results.first?.language ?? "auto", results: results)
                if let best = HypothesisPicker.best([hypothesis]) { pieces.append(best) }
                continue
            }
            let plan: LanguagePlan
            if let fixed = strategy.fixedPlan {
                plan = fixed
            } else if let detection = try? await kit.detectLangauge(audioArray: samples) {
                let logProbability = Double(detection.langProbs[detection.language] ?? -.infinity)
                plan = LanguagePlan.decide(detected: detection.language,
                                           probability: LanguagePlan.probability(fromLog: logProbability))
            } else {
                plan = .both
            }
            var candidates: [Hypothesis] = []
            for language in plan.languages {
                let results = try await kit.transcribe(audioArray: samples,
                                                       decodeOptions: Self.options(language: language, prompt: prompt))
                candidates.append(Self.hypothesis(language: language, results: results))
            }
            if let best = HypothesisPicker.best(candidates) { pieces.append(best) }
        }
        return TranscriptAssembler.assemble(pieces)
    }

    /// Charge le modèle à l'avance. La première fois, iOS l'optimise pour cet iPhone (cela peut prendre
    /// quelques minutes) et WhisperKit récupère son dictionnaire en ligne : mieux vaut le faire juste après le
    /// téléchargement que pendant la première dictée.
    public func prepare() async throws {
        _ = try await loadedPipeline()
    }

    /// Libère la mémoire du modèle (par exemple avant d'en charger un autre pour le banc d'essai).
    public func unload() async {
        let loaded = lock.withLock { () -> WhisperKit? in
            defer { pipeline = nil }
            return pipeline
        }
        await loaded?.unloadModels()
    }

    private func loadedPipeline() async throws -> WhisperKit {
        if let pipeline = lock.withLock({ self.pipeline }) { return pipeline }
        guard let folder = store.folder(for: model) else {
            throw TranscriptionError.modelUnavailable("Le modèle \(model.label) n'est pas encore téléchargé.")
        }
        let config = WhisperKitConfig(model: model.rawValue, downloadBase: store.directory, modelFolder: folder.path,
                                      tokenizerFolder: store.directory, verbose: false, logLevel: .none,
                                      prewarm: false, load: true, download: false)
        let loaded: WhisperKit
        do {
            loaded = try await WhisperKit(config)
        } catch {
            throw TranscriptionError.modelUnavailable("Impossible de charger \(model.label) sur cet iPhone.")
        }
        lock.withLock { self.pipeline = loaded }
        return loaded
    }

    /// `language` nil : détection par Whisper lui-même. La tâche reste toujours `transcribe` (jamais de traduction).
    static func options(language: String?, prompt: [Int]?) -> DecodingOptions {
        DecodingOptions(task: .transcribe, language: language, temperature: 0, usePrefillPrompt: true,
                        detectLanguage: language == nil, skipSpecialTokens: true, withoutTimestamps: true,
                        promptTokens: prompt)
    }

    static func promptTokens(for kit: WhisperKit) -> [Int]? {
        guard let tokenizer = kit.tokenizer else { return nil }
        let begin = tokenizer.specialTokens.specialTokenBegin
        let tokens = tokenizer.encode(text: " " + WhisperPrompt.bilingual).filter { $0 < begin }
        return tokens.isEmpty ? nil : tokens
    }

    static func hypothesis(language: String, results: [TranscriptionResult]) -> Hypothesis {
        let segments = results.flatMap(\.segments)
        let average = segments.isEmpty
            ? -Double.infinity
            : segments.map { Double($0.avgLogprob) }.reduce(0, +) / Double(segments.count)
        return Hypothesis(language: language, text: results.map(\.text).joined(separator: " "),
                          averageLogProbability: average)
    }
}
