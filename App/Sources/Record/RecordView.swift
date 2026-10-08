import EngramCapture
import SwiftUI

/// Écran principal : un grand cercle, toucher pour parler, toucher pour arrêter.
struct RecordView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = RecordModel()
    @State private var isTyping = false
    @State private var levels: [Float] = Array(repeating: 0, count: 24)
    /// Whisper est choisi mais son modèle n'est pas encore sur l'iPhone.
    @State private var needsWhisperDownload = false

    private var isRecording: Bool { model.recorder.state != .idle }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if needsWhisperDownload && !isRecording { whisperBanner }
                Spacer(minLength: 16)
                status
                RecordButton(isRecording: isRecording, level: reduceMotion ? 0 : model.recorder.level) {
                    Task { await model.toggle(app: app) }
                }
                .disabled(model.isBusy)
                hint
                if isRecording {
                    Waveform(levels: levels)
                    Button("Annuler", systemImage: "xmark", role: .cancel) { model.cancel() }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Annuler l'enregistrement")
                }
                Spacer(minLength: 16)
                outcome
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Écrire", systemImage: "keyboard") { isTyping = true }
                        .disabled(isRecording || model.isBusy)
                }
            }
            .sheet(isPresented: $isTyping) {
                TextCaptureSheet { text, keepLocal in Task { await model.submit(text: text, keepLocal: keepLocal, app: app) } }
            }
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .onChange(of: model.recorder.level) { _, level in
                levels.removeFirst()
                levels.append(level)
            }
            .onChange(of: model.recorder.state) { _, state in
                if state == .finished { Task { await model.finish(app: app) } }
            }
            .onAppear(perform: refreshWhisperStatus)
            .onChange(of: app.preparingModels) { _, _ in refreshWhisperStatus() }
        }
    }

    /// Invitation à télécharger Whisper (en attendant, la reconnaissance d'Apple transcrit).
    private var whisperBanner: some View {
        let whisper = app.whisperModel
        return VStack(alignment: .leading, spacing: 8) {
            Text("Transcription bilingue").font(.subheadline.weight(.semibold))
            Text("Télécharge Whisper (\(whisper.approximateSizeMB) Mo, une seule fois, Wi-Fi conseillé) pour qu'Engram comprenne ton français québécois et tes mots anglais.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if app.preparingModels.contains(whisper) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Préparation du modèle… garde l'app ouverte.").font(.footnote)
                }
            } else if let progress = app.modelDownloads[whisper] {
                ProgressView(value: progress) {
                    Text("Téléchargement \(Int(progress * 100)) %").font(.footnote)
                }
            } else {
                Button("Télécharger Whisper") {
                    Task {
                        await app.downloadWhisperModel(whisper)
                        refreshWhisperStatus()
                    }
                }
                .buttonStyle(.prominent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 8)
    }

    private func refreshWhisperStatus() {
        needsWhisperDownload = app.transcriptionEngine == .whisper && !app.whisperModels.isDownloaded(app.whisperModel)
    }

    @ViewBuilder private var status: some View {
        if isRecording {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("\(Self.clock(model.recorder.elapsed)) / \(Self.clock(VoiceRecorder.maxDuration))")
                    .font(.title3.monospacedDigit())
            }
        } else {
            Text(" ").font(.title3).accessibilityHidden(true)
        }
    }

    private var hint: some View {
        Text(hintText.uppercased())
            .font(.caption)
            .tracking(2)
            .foregroundStyle(.secondary)
    }

    private var hintText: String {
        switch model.phase {
        case .recording: "Toucher pour arrêter"
        case .transcribing: "Transcription…"
        case .review: "Vérifie ta note"
        case .filing: "Classement…"
        default: "Toucher pour parler"
        }
    }

    @ViewBuilder private var outcome: some View {
        switch model.phase {
        case .result:
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.items) { FiledResultCard(item: $0) }
                }
            }
            .frame(maxHeight: 260)
        case .message(let text):
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .review:
            if let draft = Binding($model.review) {
                ScrollView {
                    ReviewCard(draft: draft, audioURL: model.reviewAudioURL,
                               onConfirm: { Task { await model.confirmReview(app: app) } },
                               onDiscard: { model.discardReview(app: app) })
                }
                .frame(maxHeight: 380)
                .scrollDismissesKeyboard(.interactively)
            }
        case .transcribing, .filing:
            ProgressView()
        default:
            EmptyView()
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct RecordButton: View {
    let isRecording: Bool
    let level: Float
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red.opacity(0.08) : Color.primary.opacity(0.03))
                Circle()
                    .strokeBorder(isRecording ? Color.red.opacity(0.4) : Color.primary.opacity(0.18), lineWidth: 1)
                Image(systemName: isRecording ? "stop.fill" : "mic")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(isRecording ? Color.red : Color.primary)
            }
            .frame(width: 200, height: 200)
            .scaleEffect(1 + CGFloat(level) * 0.06)
            .animation(.easeOut(duration: 0.12), value: level)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
        .accessibilityLabel(isRecording ? "Arrêter l'enregistrement" : "Commencer l'enregistrement")
    }
}

struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 3, height: 4 + CGFloat(levels[index]) * 36)
            }
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }
}
