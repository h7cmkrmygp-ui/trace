#if os(iOS)
import AVFAudio
import Foundation
import Observation

public struct RecordingResult: Sendable, Equatable {
    public let url: URL
    public let relativePath: String
    public let duration: TimeInterval
}

public enum RecorderError: Error, Equatable, Sendable {
    case couldNotStart
}

/// Enregistrement du micro dans un fichier CAF (PCM 16 kHz mono), écrit au fil de l'eau :
/// si l'app est interrompue, l'audio déjà capté reste sur le disque.
@MainActor
@Observable
public final class VoiceRecorder {
    public enum State: Equatable, Sendable {
        case idle
        case recording
        /// Arrêt automatique (durée maximale ou interruption) : appeler `stop()` pour récupérer l'audio.
        case finished
    }

    public static let maxDuration: TimeInterval = 5 * 60

    public private(set) var state: State = .idle
    public private(set) var elapsed: TimeInterval = 0
    /// Niveau du micro, de 0 à 1.
    public private(set) var level: Float = 0

    private var recorder: AVAudioRecorder?
    private var recording: AudioFiles.Recording?
    private var meterTask: Task<Void, Never>?
    private var interruptionObserver: (any NSObjectProtocol)?

    public init() {}

    public static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func start(in base: URL) throws {
        guard state == .idle else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)
        let recording = try AudioFiles.newRecording(in: base)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: recording.url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record(forDuration: Self.maxDuration) else { throw RecorderError.couldNotStart }
        self.recorder = recorder
        self.recording = recording
        elapsed = 0
        state = .recording
        startMetering()
        observeInterruptions()
    }

    /// Termine l'enregistrement et renvoie le fichier (nil si rien n'était enregistré).
    public func stop() -> RecordingResult? {
        guard let recorder, let recording else { return nil }
        let duration = max(recorder.currentTime, elapsed)
        recorder.stop()
        tearDown()
        return RecordingResult(url: recording.url, relativePath: recording.relativePath, duration: duration)
    }

    /// Annule et supprime le fichier.
    public func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        tearDown()
    }

    private func tearDown() {
        meterTask?.cancel()
        meterTask = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        recorder = nil
        recording = nil
        level = 0
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let recorder = self.recorder else { return }
                if recorder.isRecording {
                    recorder.updateMeters()
                    let decibels = recorder.averagePower(forChannel: 0)
                    self.level = max(0, min(1, (decibels + 50) / 50))
                    self.elapsed = recorder.currentTime
                } else if self.state == .recording {
                    self.state = .finished
                    self.level = 0
                }
            }
        }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .recording else { return }
                self.recorder?.pause()
                self.state = .finished
                self.level = 0
            }
        }
    }
}
#endif
