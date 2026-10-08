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

/// Lecture de l'enregistrement sur la carte. L'icône revient à « Réécouter » quand la lecture finit toute seule,
/// et la musique des autres apps reprend ensuite.
@MainActor
@Observable
final class ReviewPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if isPlaying {
            stop()
            return
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        self.player = player
        isPlaying = player.play()
    }

    /// Sans effet si rien ne joue (la session audio d'un enregistrement en cours n'est jamais touchée).
    func stop() {
        guard let player else { return }
        player.stop()
        finish()
    }

    private func finish() {
        player = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }
}

/// « Vérifie ta note » : corriger la transcription, réécouter, puis classer (ou annuler).
/// Le texte d'origine reste toujours conservé ; la correction est rangée à part.
struct ReviewCard: View {
    @Binding var draft: ReviewDraft
    let audioURL: URL?
    let onConfirm: () -> Void
    let onDiscard: () -> Void
    @State private var player = ReviewPlayer()

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
                .tint(.green)
                .font(.subheadline)
            HStack(spacing: 12) {
                if let audioURL {
                    Button(player.isPlaying ? "Arrêter" : "Réécouter",
                           systemImage: player.isPlaying ? "stop.circle" : "play.circle") { player.toggle(audioURL) }
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .accessibilityLabel(player.isPlaying ? "Arrêter la lecture" : "Réécouter")
                }
                Spacer()
                Button("Annuler", role: .destructive, action: onDiscard)
                    .tint(.red)
                Button("Classer", action: onConfirm)
                    .buttonStyle(.prominent)
                    .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .onDisappear { player.stop() }
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
            draft = ReviewDraft(sourceID: sourceID, text: source.referenceText ?? "")
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
                    Text(source.referenceText ?? "Note vocale")
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
