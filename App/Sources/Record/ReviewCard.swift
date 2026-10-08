import AVFAudio
import EngramCapture
import EngramCore
import SwiftUI

/// Texte d'une dictée en cours de vérification.
struct ReviewDraft: Equatable, Identifiable {
    let sourceID: UUID
    var text: String
    var keepLocal = false

    var id: UUID { sourceID }
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

/// Contenu de « Vérifie ta note » : corriger la transcription, la réécouter, la garder sur l'iPhone ou la jeter.
/// Le texte d'origine reste toujours conservé ; la correction est rangée à part. « Classer » est dans la barre du
/// haut de l'écran qui l'affiche : il reste visible au-dessus du clavier.
struct ReviewCard: View {
    @Binding var draft: ReviewDraft
    let audioURL: URL?
    let onDiscard: () -> Void
    @State private var player = ReviewPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextEditor(text: $draft.text)
                .frame(minHeight: 120, maxHeight: 260)
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
                        .font(.subheadline)
                        .accessibilityLabel(player.isPlaying ? "Arrêter la lecture" : "Réécouter")
                }
                Spacer()
                Button("Jeter la dictée", systemImage: "trash", role: .destructive, action: onDiscard)
                    .font(.subheadline)
                    .tint(.red)
            }
        }
        .padding(16)
        .onDisappear { player.stop() }
    }
}

/// « Vérifie ta note » juste après une dictée, en feuille sur l'écran Enregistrer. La feuille garde sa propre copie
/// du texte (rien n'est relu après sa fermeture) ; la fermer d'un geste garde la dictée dans « À vérifier ».
struct ReviewSheet: View {
    @State private var draft: ReviewDraft
    let audioURL: URL?
    let onConfirm: (ReviewDraft) -> Void
    let onLater: () -> Void
    let onDiscard: () -> Void

    init(draft: ReviewDraft, audioURL: URL?, onConfirm: @escaping (ReviewDraft) -> Void,
         onLater: @escaping () -> Void, onDiscard: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.audioURL = audioURL
        self.onConfirm = onConfirm
        self.onLater = onLater
        self.onDiscard = onDiscard
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ReviewCard(draft: $draft, audioURL: audioURL, onDiscard: onDiscard)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Vérifie ta note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Plus tard", action: onLater)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Classer") { onConfirm(draft) }
                        .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Une note de la file « À vérifier », ouverte depuis les Notes (dictée faite avant une fermeture de l'app).
struct ReviewScreen: View {
    @Environment(AppModel.self) private var model
    let sourceID: UUID
    @State private var loaded: ReviewDraft?
    @State private var audioURL: URL?
    @State private var isMissing = false

    var body: some View {
        Group {
            if let loaded {
                ReviewScreenContent(initial: loaded, audioURL: audioURL)
            } else if isMissing {
                ContentUnavailableView("Note déjà vérifiée", systemImage: "checkmark.circle")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Vérifie ta note")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let source = try? model.memories.source(id: sourceID), source.needsReview else {
                isMissing = true
                return
            }
            audioURL = source.audioPath.map { AudioFiles.url(forRelativePath: $0, in: model.storageDirectory) }
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            loaded = ReviewDraft(sourceID: sourceID, text: source.referenceText ?? "")
        }
    }
}

/// Édition d'une dictée de la file : sa propre copie du texte, « Classer » dans la barre du haut.
private struct ReviewScreenContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReviewDraft
    let audioURL: URL?
    @State private var isFiling = false

    init(initial: ReviewDraft, audioURL: URL?) {
        _draft = State(initialValue: initial)
        self.audioURL = audioURL
    }

    var body: some View {
        ScrollView {
            ReviewCard(draft: $draft, audioURL: audioURL, onDiscard: discard)
            if isFiling { ProgressView("Classement…") }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(isFiling)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Classer", action: confirm)
                    .disabled(isFiling || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func confirm() {
        isFiling = true
        let edited = draft
        Task {
            _ = await model.confirmReview(sourceID: edited.sourceID, text: edited.text, keepLocal: edited.keepLocal)
            isFiling = false
            dismiss()
        }
    }

    private func discard() {
        model.perform { try model.memories.discardReview(sourceID: draft.sourceID) }
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
