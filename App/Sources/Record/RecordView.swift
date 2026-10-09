import EngramCapture
import EngramCore
import EngramStore
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
        @Bindable var app = app
        NavigationStack(path: $app.recordPath) {
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
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .animation(reduceMotion ? nil : .snappy, value: model.phase)
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
            // « Vérifie ta note » (si l'option est active) : une feuille au-dessus du clavier, avec sa propre copie du
            // texte. Fermée d'un geste, la dictée reste dans « À vérifier ».
            .sheet(item: Binding(get: { model.review }, set: { if $0 == nil { model.postponeReview() } })) { draft in
                ReviewSheet(draft: draft, audioURL: model.reviewAudioURL,
                            onConfirm: { edited in Task { await model.confirmReview(edited, app: app) } },
                            onLater: { model.postponeReview() },
                            onDiscard: { model.discardReview(app: app) })
            }
            .sensoryFeedback(.success, trigger: model.phase) { _, phase in phase == .result }
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .onChange(of: model.recorder.level) { _, level in
                levels.removeFirst()
                levels.append(level)
            }
            .onChange(of: model.recorder.state) { _, state in
                if state == .finished { Task { await model.finish(app: app) } }
            }
            .onAppear {
                refreshWhisperStatus()
                #if DEBUG
                // Tests d'interface : la carte « Vérifie ta note » d'une dictée inventée, sans micro.
                if UITestSeed.wantsRecordReview, model.phase == .idle,
                   let source = try? app.memories.sourcesAwaitingReview().first {
                    model.showReview(of: source, audioURL: nil)
                }
                #endif
            }
            .onChange(of: app.preparingModels) { _, _ in refreshWhisperStatus() }
            // Siri ou le bouton Action : l'enregistrement commence dès que l'écran est là.
            .task(id: app.recordingRequest) {
                guard app.consumeRecordingRequest(), !isRecording, !model.isBusy else { return }
                await model.start(app: app)
            }
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
        VStack(spacing: 6) {
            Text(hintText.uppercased())
                .font(.caption)
                .tracking(2)
                .foregroundStyle(.secondary)
            if model.phase == .recording && app.stopsOnSilence {
                Text("Je m'arrête tout seul quand tu te tais.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
            VStack(spacing: 10) {
                Label(model.items.count > 1 ? "Enregistré · \(model.items.count) notes" : "Enregistré",
                      systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.items) { FiledResultCard(item: $0) }
                    }
                }
                .frame(maxHeight: 240)
            }
        case .message(let text):
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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

/// Le bouton de l'accueil : une sphère de verre, avec derrière elle une lumière aux couleurs des catégories qui tourne
/// lentement. Pendant l'enregistrement, la lumière devient rouge, grandit avec la voix et des ondes s'en échappent.
struct RecordButton: View {
    let isRecording: Bool
    let level: Float
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    private var glowColors: [Color] {
        if isRecording { return [.red, .orange, .pink, .red] }
        let hues = CategoryPalette.hues.prefix(6).map { Color(hue: $0, saturation: 0.55, brightness: 0.95) }
        return hues + [hues[0]]
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: glowColors, center: .center))
                    .blur(radius: 30)
                    .opacity(isRecording ? 0.6 : 0.42)
                    .scaleEffect(1.02 + CGFloat(level) * 0.28)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                if isRecording && !reduceMotion { RippleRings() }
                Color.clear
                    .glassEffect(.regular.interactive(), in: Circle())
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(isRecording ? Color.red : Color.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 200, height: 200)
            .scaleEffect(1 + CGFloat(level) * 0.04)
            .animation(.easeOut(duration: 0.12), value: level)
            .animation(.smooth(duration: 0.4), value: isRecording)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
        .accessibilityLabel(isRecording ? "Arrêter l'enregistrement" : "Commencer l'enregistrement")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

/// Ondes qui s'éloignent du bouton pendant l'enregistrement.
private struct RippleRings: View {
    private let epoch = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let time = timeline.date.timeIntervalSince(epoch)
            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    let phase = (time / 1.8 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(Color.red.opacity(0.35 * (1 - phase)), lineWidth: 1.5)
                        .scaleEffect(1 + 0.4 * phase)
                }
            }
        }
        .accessibilityHidden(true)
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
