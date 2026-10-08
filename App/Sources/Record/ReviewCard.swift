import AVFAudio
import EngramCapture
import EngramCore
import SwiftUI

/// Texte d'une dictée en cours de vérification.
struct ReviewDraft: Equatable {
    let sourceID: UUID
    var text: String
    var keepLocal = false
}

/// « Vérifie ta note » : corriger la transcription, réécouter, puis classer (ou annuler).
/// Le texte d'origine reste toujours conservé ; la correction est rangée à part.
struct ReviewCard: View {
    @Binding var draft: ReviewDraft
    let audioURL: URL?
    let onConfirm: () -> Void
    let onDiscard: () -> Void
    @State private var player: AVAudioPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vérifie ta note")
                .font(.headline)
            TextEditor(text: $draft.text)
                .frame(minHeight: 110, maxHeight: 220)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Transcription à vérifier")
            Toggle("Garder sur l'iPhone", isOn: $draft.keepLocal)
                .font(.subheadline)
            HStack(spacing: 12) {
                if audioURL != nil {
                    Button(player?.isPlaying == true ? "Arrêter" : "Réécouter",
                           systemImage: player?.isPlaying == true ? "stop.circle" : "play.circle", action: togglePlayback)
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .accessibilityLabel(player?.isPlaying == true ? "Arrêter la lecture" : "Réécouter")
                }
                Spacer()
                Button("Annuler", role: .destructive, action: onDiscard)
                    .tint(.red)
                Button("Classer", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .onDisappear { player?.stop() }
    }

    private func togglePlayback() {
        if let player, player.isPlaying {
            player.stop()
            self.player = nil
            return
        }
        guard let audioURL else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: audioURL)
        player?.play()
    }
}

/// Une note de la file « À vérifier », ouverte depuis les Notes (dictée faite avant une fermeture de l'app).
struct ReviewScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let sourceID: UUID
    @State private var draft: ReviewDraft?
    @State private var audioURL: URL?
    @State private var isFiling = false

    var body: some View {
        Group {
            if let binding = Binding($draft) {
                ScrollView {
                    ReviewCard(draft: binding, audioURL: audioURL, onConfirm: confirm, onDiscard: discard)
                    if isFiling { ProgressView("Classement…") }
                }
                .disabled(isFiling)
            } else {
                ContentUnavailableView("Note déjà vérifiée", systemImage: "checkmark.circle")
            }
        }
        .navigationTitle("À vérifier")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let source = try? model.memories.source(id: sourceID), source.needsReview else { return }
            draft = ReviewDraft(sourceID: sourceID, text: source.originalText ?? "")
            audioURL = source.audioPath.map { AudioFiles.url(forRelativePath: $0, in: model.storageDirectory) }
        }
    }

    private func confirm() {
        guard let draft else { return }
        isFiling = true
        Task {
            _ = await model.confirmReview(sourceID: draft.sourceID, text: draft.text, keepLocal: draft.keepLocal)
            isFiling = false
            dismiss()
        }
    }

    private func discard() {
        model.perform { try model.memories.discardReview(sourceID: sourceID) }
        dismiss()
    }
}

/// Les dictées qui attendent « Vérifie ta note ».
struct ReviewQueueView: View {
    @Environment(AppModel.self) private var model
    @State private var sources: [Source] = []

    var body: some View {
        List(sources) { source in
            NavigationLink(value: NotesRoute.review(source.id)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.originalText ?? "Note vocale")
                        .lineLimit(2)
                    Text(source.capturedAt, format: .relative(presentation: .named))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if sources.isEmpty { ContentUnavailableView("Rien à vérifier", systemImage: "checkmark.circle") }
        }
        .navigationTitle("À vérifier")
        .task {
            do {
                for try await list in model.memories.sourcesAwaitingReviewStream() { sources = list }
            } catch {
                model.errorMessage = AppModel.describe(error)
            }
        }
    }
}
